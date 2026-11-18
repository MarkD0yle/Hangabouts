// Spec 006 M2: the Swift half of the motion check. Prints what SnufflerMotion would draw, in page.cjs's format.
import Foundation

struct Action: Decodable { let step: Int; let `do`: String; let arg: Arg?
    enum Arg: Decodable { case bool(Bool), number(Double), text(String)
        init(from d: Decoder) throws { let c = try d.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) } else if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .text(try c.decode(String.self)) } }
        var bool: Bool { if case .bool(let b) = self { return b }; return false }
        var number: Double { if case .number(let n) = self { return n }; return 0 }
        var text: String { if case .text(let s) = self { return s }; return "" } } }
struct Scenario: Decodable { let steps: Int; let actions: [Action] }
let scenario = try! JSONDecoder().decode(Scenario.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))

let m = SnufflerMotion()
m.random = { 0.5 }
for i in 0..<scenario.steps {
    let now = 100 + Double(i) / 60
    var out: [SnufflerMotion.Output] = []
    for a in scenario.actions where a.step == i {
        switch a.do {
        case "show": out += m.show(failed: a.arg!.text == "failed", now: now)
        case "nudge": m.nudge(level: Int(a.arg!.number), now: now)
        case "swap": m.swapArms(now: now)
        case "turn": m.turn(to: a.arg!.number, now: now)
        case "tired": m.setTired(a.arg!.bool, now: now)
        case "idle": m.setIdle(a.arg!.bool, now: now)
        case "reduced": m.setReducedMotion(a.arg!.bool, now: now)
        case "climb": out += m.climb(now: now)
        default: fatalError(a.do)
        }
    }
    out += m.fire(now: now)
    var drawn = "still"
    if m.running {
        let u = m.frame(now: now).uniforms
        drawn = [u.uYaw, u.uSwing, u.uSignSwing, u.uSignYaw, u.uBlink, u.uKick, u.uTail, u.uSniff, u.uFail, u.uBreathe, u.uRaiseR, u.uRaiseL, u.uShakeR, u.uShakeL, u.uTired, u.uBody, u.uGrip]
            .map { String(format: "%.6f", $0) }.joined(separator: ",")
    }
    let st: String
    switch m.stage { case .hidden: st = "hidden"; case .hanging: st = "hanging"; case .dropping: st = "dropping"; case .climbing: st = "climbing" }
    print([String(i), st, out.map { $0 == .shown ? "shown" : "climbed" }.joined(separator: "+"), drawn].joined(separator: ";"))
}
