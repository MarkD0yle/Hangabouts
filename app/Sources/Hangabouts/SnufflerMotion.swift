import Foundation

/// How Snuffler moves. Ported from the script in design/snuffler-hanging.html (the old web page, kept as a
/// reference): same state, same constants, same order.
/// Copy, don't re-tune (Spec 006 M2). Pure Swift, no AppKit: every call takes the time, in seconds, so it can be
/// run against a fake clock.
///
/// The page used `setTimeout` and `requestAnimationFrame`. Here the owner does both jobs:
/// - call `fire(now:)` when `nextEventTime` is due, and before every frame;
/// - call `frame(now:)` once per display refresh while `running` is true.
final class SnufflerMotion {
    static let rest = 0.95                       // resting turn: three-quarter view, facing right

    enum Output: Equatable { case shown, climbed }

    /// The page's `#stage` classes.
    enum Stage: Equatable {
        case hidden
        case hanging
        case dropping(since: Double)
        case climbing(since: Double)
    }

    struct Frame {
        var uniforms: SnufflerUniforms
        /// The CSS `translateY` of the drop and climb, as a fraction of his height. Positive is down.
        var translateY: Double
    }

    private enum Action { case landed, letGo, climbed }

    private(set) var stage: Stage = .hidden
    private(set) var failed = false
    private(set) var reduced = false
    private(set) var alive = false               // idle life
    private(set) var tired = false
    private var idleNextIsPump = true
    private var timers: [(at: Double, action: Action)] = []   // the page's `later`
    private var tiredAt: Double?                               // the page's `tiredTimer`
    /// 0 ..< 1. Only the idle loop's delay uses it. Replaceable for tests.
    var random: () -> Double = { Double.random(in: 0..<1) }

    // The page's `S`.
    private var yaw = rest, yawV = 0.0, yawT = rest
    private var th = 0.0, thV = 0.0, ph = 0.0, phV = 0.0, sg = 0.0, sgV = 0.0, lg = 0.0, lgV = 0.0
    private var pumpUntil = 0.0, kickAt = -1e9, busyUntil = 0.0, last = 0.0
    private var holdLeft = false, swapAt = -1e9
    private var drag: (x: Double, yaw: Double, moved: Bool)?
    /// True while frames are wanted. The page's `S.running`.
    private(set) var running = false

    var isHidden: Bool { stage == .hidden }

    /// When `fire(now:)` next has something to do, if ever.
    var nextEventTime: Double? {
        let first = timers.map(\.at).min()
        guard let tiredAt else { return first }
        return min(first ?? tiredAt, tiredAt)
    }

    // MARK: - Small helpers, as in the page

    private func clear() { timers.removeAll() }
    private func later(_ ms: Double, _ action: Action, _ now: Double) { timers.append((now + ms / 1000, action)) }
    private func damped(_ t: Double, _ amp: Double, _ decay: Double, _ period: Double) -> Double {
        (t < 0 || t > 4) ? 0 : amp * exp(-decay * t) * sin(2 * .pi * t / period)
    }
    private func wake(_ sec: Double, _ now: Double) {
        busyUntil = max(busyUntil, now + sec)
        if !running { running = true; last = now }
    }

    // MARK: - Swing physics
    // The swing is a pendulum. His body hangs off it from the gripping hand; his legs and the sign hang off him.
    // Each one lags behind the one above it, so motion ripples down through him.

    private static let W0 = 2 * Double.pi / 1.1              // the swing's own rhythm: about 1.1 s a swing

    /// A push: amp is roughly how far it then swings, in radians.
    private func swing(_ amp: Double, _ now: Double) { thV += amp * SnufflerMotion.W0; wake(1, now) }

    /// He pumps the swing himself: legs kick forward and his body leans back in time with it.
    private func pump(_ sec: Double, _ now: Double) {
        if reduced { return }
        if abs(thV) < 0.15 { thV += 0.45 }                   // a first push off, so there is a beat to pump with
        pumpUntil = now + sec; wake(1, now)
    }

    private func step(_ dt: Double, _ now: Double) {
        let n = max(1, Int((dt / 0.004).rounded(.up))), h = dt / Double(n)
        let W0 = SnufflerMotion.W0
        let WB = 2 * Double.pi / 0.85, WL = 2 * Double.pi / 0.5, WS = 2 * Double.pi / 0.6
        for _ in 0..<n {
            let pumping = now < pumpUntil, beat = tanh(thV * 5)
            let thA = -W0 * W0 * sin(th) - 1.6 * thV + (pumping ? 1.9 * beat : 0)
            let phA = -WB * WB * (ph - (pumping ? -0.12 * beat : 0)) - 3.2 * phV - thA       // body: swung by the swing, leans back while pumping
            let lgA = -WL * WL * (lg - (pumping ? 0.5 * beat : 0)) - 4.0 * lgV - (thA + phA) // legs: trail, or kick while pumping
            let sgA = -WS * WS * sg - 2.2 * sgV - (thA + phA)                                // the sign on his nose
            thV += thA * h; th += thV * h
            phV += phA * h; ph += phV * h
            lgV += lgA * h; lg += lgV * h
            sgV += sgA * h; sg += sgV * h
        }
    }
    private var energy: Double { abs(th) + abs(thV) + abs(ph) + abs(phV) + abs(lg) + abs(lgV) + abs(sg) + abs(sgV) }
    private func resetSwing() { th = 0; thV = 0; ph = 0; phV = 0; lg = 0; lgV = 0; sg = 0; sgV = 0; pumpUntil = 0 }

    // MARK: - Arm swap (off by default)
    // 0 to 3.4 s: the free arm reaches up (0 to 0.6), both hold (to 0.9), the tired arm lets go (to 1.4) and shakes out.

    func swapArms(now: Double) {
        if isHidden { return }
        holdLeft.toggle()
        swapAt = now; wake(3.6, now)
        later(1150, .letGo, now)   // as the tired hand lets go, his body drops onto the other hand and sways
    }

    /// While he hangs: Tired swaps arms every 9 s. Idle life takes turns pumping the swing and swapping arms, every 8 to 14 s.
    private func loopTired(_ firstDelay: Double, _ now: Double) {
        tiredAt = nil
        if reduced || !(tired || alive) { return }
        tiredAt = now + firstDelay
    }

    private func armVals(_ t: Double, into u: inout SnufflerUniforms) {
        func sm(_ v: Double) -> Double { let x = max(0, min(1, v)); return x * x * (3 - 2 * x) }
        let ts = reduced ? 99 : t - swapAt
        let up = sm(ts / 0.6), down = 1 - sm((ts - 0.9) / 0.5)
        let shake = ts > 1.4 && ts < 3.4 ? exp(-2.2 * (ts - 1.4)) * sin(2 * .pi * (ts - 1.4) / 0.28) : 0
        let tiredness = sm((ts - 0.1) / 0.5) * (1 - sm((ts - 2.6) / 0.6))
        let rR = holdLeft ? down : up, rL = holdLeft ? up : down
        u.uRaiseR = Float(rR); u.uRaiseL = Float(rL)
        u.uShakeR = Float(holdLeft ? shake : 0); u.uShakeL = Float(holdLeft ? 0 : shake)
        u.uTired = Float(tiredness)
        u.uGrip = Float((rR - rL) / max(rR + rL, 0.001))
    }

    // MARK: - Frames

    /// One display refresh. Call only while `running`. Moves him on, and decides whether another frame is wanted.
    func frame(now t: Double) -> Frame {
        let dt = min(t - last, 0.05); last = t
        // turn: a spring toward the target, with a little overshoot
        if reduced { yaw = yawT; yawV = 0 }
        else { let acc = 46 * (yawT - yaw) - 8.5 * yawV; yawV += acc * dt; yaw += yawV * dt }
        if !reduced { step(dt, t) }
        let result = current(now: t)
        // Stop drawing once he is still, so a hanging Snuffler costs nothing. Idle life keeps it running.
        let life = alive && !reduced
        let moving = t < busyUntil || t < pumpUntil || energy > 0.004 || abs(yawT - yaw) > 0.002 || abs(yawV) > 0.01 || drag != nil
        running = !isHidden && (moving || life)
        return result
    }

    /// What to draw at `t`, without moving him on. For a redraw when nothing else changed (a resize).
    func current(now t: Double) -> Frame {
        let legs = reduced ? 0 : lg * sin(yaw) * 1.4          // legs swing toward the way he faces, or away
        let life = alive && !reduced
        let blinkPhase = t.truncatingRemainder(dividingBy: 5.2) / 0.2, sniffT = t.truncatingRemainder(dividingBy: 7) - 5.4
        var u = SnufflerUniforms()
        u.uYaw = Float(yaw)
        u.uSwing = Float(reduced ? 0 : th)
        u.uBody = Float(reduced ? 0 : ph)
        u.uSignSwing = Float(reduced ? 0 : sg)
        u.uSignYaw = Float(reduced ? 0 : max(-0.9, min(0.9, -yawV * 0.16)))     // the sign lags behind a turn
        u.uBlink = Float(life && blinkPhase < 1 ? sin(.pi * blinkPhase) : 0)
        u.uKick = Float((reduced ? 0 : damped(t - kickAt, 0.55, 2.2, 0.46)) + legs)
        u.uTail = Float((reduced ? 0 : -sg * 1.2 - phV * 0.08) + (life ? 0.07 * sin(t * 1.05) : 0))
        u.uSniff = Float(life && sniffT > 0 && sniffT < 1.2 ? sin(sniffT * 15.7) * (1 - sniffT / 1.2) : 0)
        u.uFail = failed ? 1 : 0
        u.uBreathe = Float(life ? 0.012 * sin(t * 1.5) : 0)
        armVals(t, into: &u)
        return Frame(uniforms: u, translateY: translateY(t))
    }

    private func turnTo(_ a: Double, _ sec: Double = 1.5, _ now: Double) { yawT = max(-1.45, min(1.45, a)); wake(sec, now) }

    // MARK: - Drop and climb
    // CSS in the page:
    //   @keyframes hb-drop  { 0% -110%, 62% 5%, 80% -1.5%, 100% 0 }   .75s cubic-bezier(.3,1.1,.5,1) both
    //   @keyframes hb-climb { 0% 0, 18% 4%, 100% -110% }              .65s cubic-bezier(.5,0,.8,.4) both
    // In CSS the easing runs between each pair of keyframes, not across the whole animation.

    static let dropSeconds = 0.75, climbSeconds = 0.65

    private func translateY(_ t: Double) -> Double {
        if reduced { return 0 }                                // #stage.reduced { animation: none }
        switch stage {
        case .hidden, .hanging: return 0
        case .dropping(let since):
            return SnufflerMotion.keyframes([(0, -1.10), (0.62, 0.05), (0.80, -0.015), (1, 0)],
                                            bezier: (0.3, 1.1, 0.5, 1), progress: (t - since) / SnufflerMotion.dropSeconds)
        case .climbing(let since):
            return SnufflerMotion.keyframes([(0, 0), (0.18, 0.04), (1, -1.10)],
                                            bezier: (0.5, 0, 0.8, 0.4), progress: (t - since) / SnufflerMotion.climbSeconds)
        }
    }

    static func keyframes(_ frames: [(at: Double, value: Double)], bezier b: (Double, Double, Double, Double), progress: Double) -> Double {
        let p = max(0, min(1, progress))                       // fill-mode: both
        for i in 1..<frames.count where p <= frames[i].at {
            let a = frames[i - 1], z = frames[i]
            return a.value + (z.value - a.value) * cubicBezier(b, (p - a.at) / (z.at - a.at))
        }
        return frames[frames.count - 1].value
    }

    /// CSS cubic-bezier(x1, y1, x2, y2): the curve's y where its x is `x`.
    static func cubicBezier(_ b: (Double, Double, Double, Double), _ x: Double) -> Double {
        func curve(_ p1: Double, _ p2: Double, _ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * p1 + 3 * (1 - s) * s * s * p2 + s * s * s }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<60 {                                      // x(s) rises steadily, so halving finds s
            s = (lo + hi) / 2
            if curve(b.0, b.2, s) < x { lo = s } else { hi = s }
        }
        return curve(b.1, b.3, s)
    }

    // MARK: - Timers

    /// Runs everything that has come due, in order. Returns what the page would have posted.
    func fire(now: Double) -> [Output] {
        var out: [Output] = []
        while true {
            let i = timers.indices.filter { timers[$0].at <= now }.min { timers[$0].at < timers[$1].at }
            let timerAt = i.map { timers[$0].at }
            if let due = tiredAt, due <= now, timerAt == nil || due < timerAt! {
                tiredAt = nil
                if isHidden { continue }
                if alive && idleNextIsPump { pump(2.6, now); idleNextIsPump = false }
                else { swapArms(now: now); idleNextIsPump = true }
                loopTired(tired ? 9 : 8 + random() * 6, now)
                continue
            }
            guard let i else { return out }
            let action = timers.remove(at: i).action
            switch action {
            case .landed:
                // landing: the swing takes his weight and swings; his body and legs carry on and jolt
                stage = .hanging; swing(0.17, now); phV -= 1.3; lgV -= 2.2
                out.append(.shown); loopTired(5.5, now)
            case .letGo:
                let k = holdLeft ? -1.0 : 1.0; phV += 0.9 * k; lgV += 1.4 * k; wake(1, now)
            case .climbed:
                stage = .hidden; out.append(.climbed)
            }
        }
    }

    // MARK: - The page's `window.hangabout`

    /// He drops in a pose. Returns `.shown` at once if motion is reduced; otherwise it comes from `fire` when he lands.
    func show(failed: Bool, now: Double) -> [Output] {
        clear(); self.failed = failed
        if reduced { stage = .hanging; yaw = SnufflerMotion.rest; yawT = SnufflerMotion.rest; resetSwing(); wake(0.2, now); return [.shown] }
        yaw = -0.9; yawV = 0; yawT = SnufflerMotion.rest; resetSwing()   // he spins in as he drops
        stage = .dropping(since: now); wake(4.5, now)
        later(750, .landed, now)
        return []
    }

    /// level 1: a push on the swing. level 2: he pumps it himself with his legs and body for a few beats.
    func nudge(level: Int, now: Double) {
        if reduced || isHidden { return }
        if level >= 2 { pump(2.6, now) } else { swing(0.17, now) }
    }

    func climb(now: Double) -> [Output] {
        clear(); tiredAt = nil
        if reduced { stage = .hidden; return [.climbed] }
        stage = .climbing(since: now); turnTo(0, 1, now)
        later(650, .climbed, now)
        return []
    }

    func hide() { clear(); tiredAt = nil; stage = .hidden }

    func setReducedMotion(_ on: Bool, now: Double) { reduced = on; wake(0.3, now) }

    /// Blink, sniff, breathing, tail sway, and now and then a pump or an arm swap.
    func setIdle(_ on: Bool, now: Double) {
        alive = on; wake(0.3, now)
        if (alive || tired) && !isHidden { loopTired(3, now) } else { tiredAt = nil }
    }

    /// Every 9 s he swaps the arm he hangs by, looking tired.
    func setTired(_ on: Bool, now: Double) {
        tired = on
        if (tired || alive) && !isHidden { loopTired(2, now) } else { tiredAt = nil }
    }

    /// Angle in radians: negative faces left, 0 faces you, positive faces right.
    func turn(to angle: Double, now: Double) { turnTo(angle, 1.5, now) }

    // MARK: - Drag to turn. x is in design pixels (the 270-wide page).

    func dragBegan(x: Double, now: Double) { drag = (x, yawT, false); wake(1, now) }

    func dragMoved(x: Double, now: Double) {
        guard var d = drag else { return }
        let dx = x - d.x
        if abs(dx) > 4 { d.moved = true }
        drag = d
        if d.moved { turnTo(d.yaw + dx / 70, 1.5, now) }
    }

    /// Returns true if it was a plain click, not a drag.
    func dragEnded() -> Bool {
        defer { drag = nil }
        return drag.map { !$0.moved } ?? false
    }

    func dragCancelled() { drag = nil }
}
