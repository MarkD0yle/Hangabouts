import AppKit
import WebKit
import os

/// Owns Snuffler's panel and whichever view draws him. Main thread only.
/// Until Spec 006 M5 there are two: the web page (app/Resources/snuffler-hanging.html, driven through
/// its JS API) and the Metal view (SnufflerView). Debug › Renderer picks one; only that one exists.
@MainActor
final class CreatureController: NSObject {
    private let panel: CreaturePanel
    private var webView: CreatureWebView?
    private var snufflerView: SnufflerView?
    private weak var statusItem: NSStatusItem?
    private let logger = Logger(subsystem: "com.markdoyle.hangabouts", category: "creature")

    private var isReady = false
    private var pendingCalls: [String] = []
    private(set) var isShowing = false

    /// The page's two poses (see `hangabout.show`).
    enum Pose: String {
        case needs
        case failed
    }

    private var wanted: Pose?   // what the sessions call for
    private var shown: Pose?    // what the page was last told to show
    private var climbing = false

    /// Called with `true` when Snuffler drops and `false` once he has climbed back.
    /// The app delegate swaps the menu bar icon between his head and his burrow.
    var onHangingChanged: ((Bool) -> Void)?

    /// Called when Snuffler is clicked (or activated from the keyboard).
    var onClicked: (() -> Void)?

    /// Where his panel is, in screen coordinates. The card hangs under it.
    var panelFrame: NSRect { panel.frame }

    /// Width of the swing's two ropes where they leave the top of the page at 100%, in points.
    /// The burrow icon draws the top of them.
    static let ropeWidthAtFullSize: CGFloat = 9.5

    /// Blink, sniff, breathing, a tail sway, and now and then a pump or an arm swap while he hangs. Off by default:
    /// the spec says he hangs completely still. Saved between launches.
    private(set) var idleLife: Bool
    static let idleLifeKey = "creatureIdleLife"

    /// Every 9 s he swaps the arm he hangs by, looking tired. Off by default (Spec 004 risks). Saved between launches.
    private(set) var tired: Bool
    static let tiredKey = "creatureTired"

    /// Which engine draws him. WebGL until the Metal one is complete (Spec 006). Saved between launches.
    enum Renderer: String {
        case webgl
        case metal
    }
    private(set) var renderer: Renderer
    static let rendererKey = "creatureRenderer"

    /// Size of Snuffler relative to the 180×225 design. Saved between launches.
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
        renderer = Renderer(rawValue: UserDefaults.standard.string(forKey: CreatureController.rendererKey) ?? "") ?? .webgl
        panel = CreaturePanel()

        super.init()

        installRenderer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Public

    /// What Snuffler should be doing: hanging in a pose, or (nil) up in his burrow.
    /// Safe to call at any time, including mid-climb: he finishes the climb, then drops again.
    func present(_ pose: Pose?) {
        wanted = pose
        reconcile()
    }

    /// Debug › Renderer. Swaps the engine that draws him. If he is hanging, he drops again in the new one.
    func setRenderer(_ new: Renderer) {
        guard new != renderer else { return }
        renderer = new
        if isShowing || climbing {
            panel.orderOut(nil)
            isShowing = false
            shown = nil
            climbing = false
            onHangingChanged?(false)
        }
        installRenderer()
        UserDefaults.standard.set(renderer.rawValue, forKey: CreatureController.rendererKey) // after: Metal may have fallen back
        reconcile()
    }

    /// Moves the page towards `wanted`, one step at a time.
    private func reconcile() {
        guard !climbing, wanted != shown else { return }
        if let pose = wanted {
            positionPanel()
            panel.orderFrontRegardless() // never makeKey: focus must stay where it is
            isShowing = true
            shown = pose
            onHangingChanged?(true)
            if let snufflerView {
                snufflerView.showStill(failed: pose == .failed) // Spec 006 M1: no drop yet
                log("shown")
            } else {
                call("hangabout.show('\(pose.rawValue)')")
            }
        } else {
            // The panel is ordered out when the page says "climbed".
            climbing = true
            if snufflerView != nil { didClimb() } // Spec 006 M1: no climb yet
            else { call("hangabout.climb()") }
        }
    }

    /// A push on the swing. Only while he hangs.
    func nudge() {
        guard isShowing else { return }
        call("hangabout.nudge(1)")
    }

    /// Debug › Idle life.
    func setIdleLife(_ on: Bool) {
        idleLife = on
        UserDefaults.standard.set(on, forKey: CreatureController.idleLifeKey)
        call("hangabout.setIdle(\(on))")
    }

    /// Debug › Pump. He pumps the swing himself for a few beats. Only while he hangs.
    func pump() {
        guard isShowing else { return }
        call("hangabout.nudge(2)")
    }

    /// Debug › Swap arms. One swap now. Only while he hangs.
    func swapArms() {
        guard isShowing else { return }
        call("hangabout.swapArms()")
    }

    /// Debug › Tired.
    func setTired(_ on: Bool) {
        tired = on
        UserDefaults.standard.set(on, forKey: CreatureController.tiredKey)
        call("hangabout.setTired(\(on))")
    }

    /// Debug › Size. Resizes Snuffler, and keeps him under the icon if he's showing.
    func setScale(_ newScale: CGFloat) {
        scale = newScale
        UserDefaults.standard.set(Double(newScale), forKey: CreatureController.scaleKey)
        applyScale()
        if isShowing { positionPanel() }
    }

    // MARK: - Size

    /// The page is laid out at 270×262 CSS px; page zoom draws it smaller without touching the design.
    private func applyScale() {
        webView?.pageZoom = scale
        snufflerView?.setZoom(scale)
        panel.setContentSize(scaledSize)
        // Tell the page, so it doesn't draw more pixels than are shown.
        call("hangabout.setZoom(\(Double(scale)))")
    }

    // MARK: - Renderer

    /// Builds the view for `renderer` and drops the other one, so only one engine's memory is paid for.
    private func installRenderer() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        snufflerView = nil
        isReady = false
        pendingCalls.removeAll()

        if renderer == .metal {
            do {
                let view = try SnufflerView(size: CreaturePanel.baseSize)
                view.onClicked = { [weak self] in
                    self?.log("clicked")
                    self?.onClicked?()
                }
                view.autoresizingMask = [.width, .height]
                snufflerView = view
                panel.contentView = view
                log(String(format: "Metal renderer ready; shader compiled in %.0f ms", view.renderer.compileSeconds * 1000))
            } catch {
                log("Metal renderer failed (\(error)); using WebGL")
                renderer = .webgl
            }
        }
        if renderer == .webgl { installWebView() }
        applyScale()
    }

    private func installWebView() {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        let webView = CreatureWebView(frame: NSRect(origin: .zero, size: CreaturePanel.baseSize), configuration: config)
        self.webView = webView

        // Register before loading: the page posts "ready" as soon as it loads.
        // The proxy avoids a retain cycle (WKUserContentController holds handlers strongly).
        contentController.add(WeakMessageProxy(target: self), name: "hangabout")

        // Transparent web view. "drawsBackground" is not public API but is the widely used workaround.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.autoresizingMask = [.width, .height]
        panel.contentView = webView
        if idleLife { call("hangabout.setIdle(true)") }
        if tired { call("hangabout.setTired(true)") }

        loadPage()
    }

    private func loadPage() {
        guard let webView, let url = Bundle.main.url(forResource: "snuffler-hanging", withExtension: "html") else {
            log("snuffler-hanging.html is missing from the app's Resources")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Runs a fixed JS call now, or queues it until the page is ready.
    private func call(_ script: String) {
        guard let webView else { return } // Metal: motion arrives in Spec 006 M2
        guard isReady else {
            pendingCalls.append(script)
            return
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.log("JS call failed: \(script) – \(error.localizedDescription)")
            }
        }
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        guard message.webView === webView else { return } // a page that has since been replaced
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            log("Unreadable message from page")
            return
        }
        switch type {
        case "ready":
            isReady = true
            log("page ready")
            let queued = pendingCalls
            pendingCalls.removeAll()
            queued.forEach { call($0) }
        case "shown":
            log("shown")
        case "clicked":
            log("clicked")
            onClicked?()
        case "climbed":
            didClimb()
        case "error":
            log("page error: \(body["message"] as? String ?? "unknown")")
        default:
            log("unknown message: \(type)")
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

    // MARK: - Placement

    private func positionPanel() {
        let size = scaledSize

        if let button = statusItem?.button, let buttonWindow = button.window {
            let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let onAScreen = NSScreen.screens.contains { $0.frame.intersects(iconFrame) }
            if onAScreen {
                // The swing's ropes start at the top centre of the page. They meet the bottom
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

    @objc private func screenParametersChanged() {
        if isShowing { positionPanel() }
    }

    // MARK: - Logging

    func log(_ text: String) {
        logger.log("\(text, privacy: .public)")
        print("[Hangabouts] \(text)") // visible when running the binary from Terminal
    }
}

/// Forwards script messages without retaining the controller.
@MainActor
private final class WeakMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: CreatureController?

    init(target: CreatureController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message)
    }
}
