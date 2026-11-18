import AppKit

/// Borderless, transparent, non-activating panel that Snuffler hangs in.
/// It must never take focus from the app the user is typing in.
final class CreaturePanel: NSPanel {
    /// Snuffler is designed for exactly this size, at 100%.
    /// The controller makes the panel smaller; SnufflerView draws him to fit.
    /// It is wider than Snuffler so he has room to swing and to turn left and right,
    /// and tall enough for the swing he hangs from.
    static let baseSize = NSSize(width: 270, height: 262)

    convenience init() {
        self.init(
            contentRect: NSRect(origin: .zero, size: CreaturePanel.baseSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    // M2: never key or main. M4 revisits this for the card.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
