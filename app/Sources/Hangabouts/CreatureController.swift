import AppKit
import WebKit
import os

/// Owns Snuffler's panel and web view, and talks to the page's JS API
/// (see app/Resources/snuffler-hanging.html). Main thread only.
@MainActor
final class CreatureController: NSObject {
    private let panel: CreaturePanel
    private let webView: CreatureWebView
    private weak var statusItem: NSStatusItem?
    private let logger = Logger(subsystem: "com.markdoyle.hangabouts", category: "creature")

    private var isReady = false
    private var pendingCalls: [String] = []
    private(set) var isShowing = false

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        panel = CreaturePanel()

        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        webView = CreatureWebView(frame: NSRect(origin: .zero, size: CreaturePanel.size), configuration: config)

        super.init()

        // Register before loading: the page posts "ready" as soon as it loads.
        // The proxy avoids a retain cycle (WKUserContentController holds handlers strongly).
        contentController.add(WeakMessageProxy(target: self), name: "hangabout")

        // Transparent web view. "drawsBackground" is not public API but is the widely used workaround.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.autoresizingMask = [.width, .height]
        panel.contentView = webView

        loadPage()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Public

    /// Debug › Simulate Needs you. Shows Snuffler, or nudges him if he's already hanging.
    func simulateNeedsYou() {
        if isShowing {
            call("hangabout.nudge(1)")
            return
        }
        positionPanel()
        panel.orderFrontRegardless() // never makeKey: focus must stay where it is
        isShowing = true
        call("hangabout.show('needs')")
    }

    /// Debug › Clear all. Climbs back up; the panel is ordered out when the page says "climbed".
    func clearAll() {
        guard isShowing else { return }
        call("hangabout.climb()")
    }

    // MARK: - Page

    private func loadPage() {
        guard let url = Bundle.main.url(forResource: "snuffler-hanging", withExtension: "html") else {
            log("snuffler-hanging.html is missing from the app's Resources")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Runs a fixed JS call now, or queues it until the page is ready.
    private func call(_ script: String) {
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
            log("clicked") // the card comes in M4
        case "climbed":
            panel.orderOut(nil) // remove the window so nothing invisible blocks clicks
            isShowing = false
            log("climbed")
        default:
            log("unknown message: \(type)")
        }
    }

    // MARK: - Placement

    private func positionPanel() {
        let size = CreaturePanel.size

        if let button = statusItem?.button, let buttonWindow = button.window {
            let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let onAScreen = NSScreen.screens.contains { $0.frame.intersects(iconFrame) }
            if onAScreen {
                // Hands at the top centre of the page meet the bottom of the menu bar.
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

    private func log(_ text: String) {
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
