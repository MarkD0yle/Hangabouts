import AppKit
import WebKit

/// Web view that hosts Snuffler.
/// A non-activating panel can ignore the first click; accepting first mouse makes it count.
final class CreatureWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
