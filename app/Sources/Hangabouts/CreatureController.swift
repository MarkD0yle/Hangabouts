import AppKit
import os

/// Owns Snuffler's panel and the Metal view that draws him (SnufflerView). Main thread only.
@MainActor
final class CreatureController: NSObject {
    private let panel: CreaturePanel
    private var snufflerView: SnufflerView?   // nil only if Metal isn't available
    private weak var statusItem: NSStatusItem?
    private let logger = Logger(subsystem: "com.markdoyle.hangabouts", category: "creature")

    private(set) var isShowing = false

    /// His two poses.
    enum Pose: String {
        case needs
        case failed
    }

    private var wanted: Pose?   // what the sessions call for
    private var shown: Pose?    // what the view was last told to show
    private var climbing = false

    /// Called with `true` when Snuffler drops and `false` once he has climbed back.
    /// The app delegate swaps the menu bar icon between his head and his burrow.
    var onHangingChanged: ((Bool) -> Void)?

    /// Called when Snuffler is clicked (or activated from the keyboard or by accessibility).
    var onClicked: (() -> Void)?

    /// Where his panel is, in screen coordinates. The card hangs under it.
    var panelFrame: NSRect { panel.frame }

    /// Width of the swing's two ropes where they leave the top of the panel at 100%, in points.
    /// The burrow icon draws the top of them.
    static let ropeWidthAtFullSize: CGFloat = 9.5

    /// Blink, sniff, breathing, a tail sway, and now and then a pump or an arm swap while he hangs. Off by default:
    /// the spec says he hangs completely still. Saved between launches.
    private(set) var idleLife: Bool
    static let idleLifeKey = "creatureIdleLife"

    /// Every 9 s he swaps the arm he hangs by, looking tired. Off by default (Spec 004 risks). Saved between launches.
    private(set) var tired: Bool
    static let tiredKey = "creatureTired"

    /// Size of Snuffler relative to the 270×262 design. Saved between launches.
    private(set) var scale: CGFloat
    static let scaleKey = "creatureScale"
    static let defaultScale: CGFloat = 0.35

    private var scaledSize: NSSize {
        NSSize(width: (CreaturePanel.baseSize.width * scale).rounded(),
               height: (CreaturePanel.baseSize.height * scale).rounded())
    }

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        let saved = UserDefaults.standard.double(forKey: CreatureController.scaleKey)
        scale = saved > 0 ? CGFloat(saved) : CreatureController.defaultScale
        idleLife = UserDefaults.standard.bool(forKey: CreatureController.idleLifeKey)
        tired = UserDefaults.standard.bool(forKey: CreatureController.tiredKey)
        panel = CreaturePanel()

        super.init()

        installView()
        applyScale()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func installView() {
        do {
            let view = try SnufflerView(size: CreaturePanel.baseSize)
            view.onReady = { [weak self] seconds in self?.log(String(format: "Snuffler ready; shader compiled in %.0f ms", seconds * 1000)) }
            view.onFailed = { [weak self] error in self?.log("Snuffler can't be drawn: \(error)") }
            view.onShown = { [weak self] in self?.log("shown") }
            view.onClicked = { [weak self] in
                self?.log("clicked")
                self?.onClicked?()
            }
            view.onClimbed = { [weak self] in self?.didClimb() }
            view.autoresizingMask = [.width, .height]
            view.setIdle(idleLife)
            view.setTired(tired)
            view.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            snufflerView = view
            panel.contentView = view
        } catch {
            log("Snuffler can't be drawn: \(error)")
        }
    }

    // MARK: - Public

    /// What Snuffler should be doing: hanging in a pose, or (nil) up in his burrow.
    /// Safe to call at any time, including mid-climb: he finishes the climb, then drops again.
    func present(_ pose: Pose?) {
        wanted = pose
        reconcile()
    }

    /// Moves him towards `wanted`, one step at a time.
    private func reconcile() {
        guard let snufflerView, !climbing, wanted != shown else { return }
        if let pose = wanted {
            positionPanel()
            panel.orderFrontRegardless() // never makeKey: focus must stay where it is
            isShowing = true
            shown = pose
            onHangingChanged?(true)
            snufflerView.show(failed: pose == .failed)
        } else {
            // The panel is ordered out when the view says he has climbed.
            climbing = true
            snufflerView.climb()
        }
    }

    /// He is back in his burrow.
    private func didClimb() {
        panel.orderOut(nil) // remove the window so nothing invisible blocks clicks
        isShowing = false
        shown = nil
        climbing = false
        onHangingChanged?(false)
        log("climbed")
        reconcile() // something may have needed him again while he climbed
    }

    /// A push on the swing. Only while he hangs.
    func nudge() {
        guard isShowing else { return }
        snufflerView?.nudge(level: 1)
    }

    /// Debug › Idle life.
    func setIdleLife(_ on: Bool) {
        idleLife = on
        UserDefaults.standard.set(on, forKey: CreatureController.idleLifeKey)
        snufflerView?.setIdle(on)
    }

    /// Debug › Pump. He pumps the swing himself for a few beats. Only while he hangs.
    func pump() {
        guard isShowing else { return }
        snufflerView?.nudge(level: 2)
    }

    /// Debug › Swap arms. One swap now. Only while he hangs.
    func swapArms() {
        guard isShowing else { return }
        snufflerView?.swapArms()
    }

    /// Debug › Tired.
    func setTired(_ on: Bool) {
        tired = on
        UserDefaults.standard.set(on, forKey: CreatureController.tiredKey)
        snufflerView?.setTired(on)
    }

    /// Debug › Size. Resizes Snuffler, and keeps him under the icon if he's showing.
    func setScale(_ newScale: CGFloat) {
        scale = newScale
        UserDefaults.standard.set(Double(newScale), forKey: CreatureController.scaleKey)
        applyScale()
        if isShowing { positionPanel() }
    }

    // MARK: - Size

    /// He is designed at 270×262. The panel shrinks; the view draws only as many pixels as are shown.
    private func applyScale() {
        snufflerView?.setZoom(scale)
        panel.setContentSize(scaledSize)
    }

    // MARK: - Placement

    private func positionPanel() {
        let size = scaledSize

        if let button = statusItem?.button, let buttonWindow = button.window {
            let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let onAScreen = NSScreen.screens.contains { $0.frame.intersects(iconFrame) }
            if onAScreen {
                // The swing's ropes start at the top centre of the panel. They meet the bottom
                // of the menu bar, where the burrow icon's rope ends.
                let menuBarBottom = buttonWindow.frame.minY
                panel.setFrameOrigin(NSPoint(x: iconFrame.midX - size.width / 2, y: menuBarBottom - size.height))
                return
            }
        }

        // Fallback: icon not available (e.g. hidden behind the notch).
        log("Menu bar icon not found on screen; using fallback position")
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.maxX - 120 - size.width / 2
        let y = screen.visibleFrame.maxY - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func reduceMotionChanged() {
        snufflerView?.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    @objc private func screenParametersChanged() {
        if isShowing { positionPanel() }
    }

    // MARK: - Logging

    func log(_ text: String) {
        logger.log("\(text, privacy: .public)")
        print("[Hangabouts] \(text)") // visible when running the binary from Terminal
    }
}
