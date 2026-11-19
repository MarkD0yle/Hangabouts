import AppKit
import SwiftUI

/// What the card shows. The app delegate fills it from the session Snuffler speaks for.
@MainActor
final class CardModel: ObservableObject {
    @Published var failed = false
    @Published var reason: String?
    @Published var folder = ""
    @Published var since = Date()
    @Published var othersWaiting = 0
    /// Bundle id of the app the session lives in, if a prompt has told us. Nil until then.
    @Published var hostApp: String?

    static let claudeDesktop = "com.anthropic.claudefordesktop"

    var hostIsClaude: Bool { hostApp == CardModel.claudeDesktop }

    /// The host app's name for the card's first row. Nil when the app isn't known or isn't installed.
    var hostName: String? {
        guard let hostApp else { return nil }
        if hostIsClaude { return "Claude Code, desktop app" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostApp) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// The small card under Snuffler (Spec 002, "Click and card").
struct CardView: View {
    @ObservedObject var model: CardModel
    let goToTerminal: () -> Void
    let hideForTenMinutes: () -> Void

    /// As narrow as the two buttons allow side by side (measured: 96 + 110 pt, plus spacing and padding).
    static let width: CGFloat = 244

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.failed ? "Snuffler hit a problem" : "Snuffler needs you")
                    .font(.headline)
                if let reason = model.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let host = model.hostName {
                    Label(host, systemImage: "macwindow")
                }
                Label(model.folder, systemImage: "folder")
                // Ticks once a second while the card is open.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(CardView.waiting(from: model.since, to: context.date), systemImage: "clock")
                }
                if model.othersWaiting > 0 {
                    Label("+\(model.othersWaiting) more waiting", systemImage: "ellipsis.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Hide 10 min", action: hideForTenMinutes)
                    .accessibilityLabel("Hide for 10 minutes")
                Spacer()
                Button(model.hostIsClaude ? "Go to Claude" : "Go to terminal", action: goToTerminal)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: CardView.width, alignment: .leading)
    }

    /// "Waiting 45 s", "Waiting 3 min", "Waiting 1 h 5 min".
    static func waiting(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "Waiting \(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "Waiting \(minutes) min" }
        return "Waiting \(minutes / 60) h \(minutes % 60) min"
    }
}

/// The card's window. Unlike Snuffler's panel it may become key, so Escape and the buttons work.
/// It is non-activating: it takes the keyboard without bringing Hangabouts forward as an app.
private final class CardPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } // 53 = Escape
    }
}

/// Opens, places and closes the card. Main thread only.
@MainActor
final class CardController: NSObject, NSWindowDelegate {
    let model = CardModel()
    var onGoToTerminal: (() -> Void)?
    var onHideForTenMinutes: (() -> Void)?

    private let panel: CardPanel
    private let hosting: NSHostingView<CardView>
    private var anchor: NSRect = .zero
    private var closedAt = Date.distantPast

    private(set) var isOpen = false

    /// Share of Snuffler's panel height that is empty under him when he hangs at rest.
    /// Measured from the renders in results/spec-006-m1 (about 0.23); kept a little under so the card never touches him.
    private static let emptyShareBelowSnuffler: CGFloat = 0.18

    override init() {
        panel = CardPanel(
            contentRect: NSRect(x: 0, y: 0, width: CardView.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Placeholder actions; the real ones need `self`, which isn't ready yet.
        hosting = NSHostingView(rootView: CardView(model: model, goToTerminal: {}, hideForTenMinutes: {}))
        super.init()

        hosting.rootView = CardView(
            model: model,
            goToTerminal: { [weak self] in self?.onGoToTerminal?() },
            hideForTenMinutes: { [weak self] in self?.onHideForTenMinutes?() }
        )

        // A real blurred background: SwiftUI materials don't blur what's behind a clear window.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.setAccessibilityLabel("Snuffler details")
    }

    /// Opens the card under `anchor` (Snuffler's panel, in screen coordinates).
    /// This is the one place Hangabouts takes the keyboard, and only after a click on Snuffler.
    func open(under anchor: NSRect) {
        self.anchor = anchor
        layout()
        isOpen = true
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        closedAt = Date()
        panel.orderOut(nil)
    }

    /// A click on Snuffler that also closed the card (by taking key from it) must not reopen it.
    var justClosed: Bool { Date().timeIntervalSince(closedAt) < 0.3 }

    /// Call after changing the model: the card may have grown or shrunk.
    func layout() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        // Snuffler's panel is empty below his sign, so the card tucks up into that space to sit near him.
        let tuck = anchor.height * CardController.emptyShareBelowSnuffler
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY + tuck - size.height - 4)
        // Keep it on the screen Snuffler is on.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
            origin.y = max(origin.y, area.minY)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    // Clicking anywhere else takes key away, which closes the card.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
