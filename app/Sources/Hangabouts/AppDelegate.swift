import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Must live as long as the app, or the icon disappears at once.
    private var statusItem: NSStatusItem!
    private var creature: CreatureController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let image = Bundle.main.image(forResource: "menubar-icon") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false // the icon is coloured
                button.image = image
            } else {
                button.title = "H" // fallback if resources are missing
            }
            button.setAccessibilityLabel("Hangabouts")
        }

        creature = CreatureController(statusItem: statusItem)
        statusItem.menu = buildMenu()
    }

    // MARK: - Debug actions (M2)

    @objc private func simulateNeedsYou() {
        creature.simulateNeedsYou()
    }

    @objc private func simulateNeedsYouDelayed() {
        // Gives the human time to click into another app and start typing (focus test M2-5).
        perform(#selector(simulateNeedsYou), with: nil, afterDelay: 5)
    }

    @objc private func clearAll() {
        creature.clearAll()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        creature.setScale(CGFloat(sender.tag) / 100)
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    /// Debug › Size submenu. Tags are percentages.
    private func sizeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = Int((creature.scale * 100).rounded())
        for (title, percent) in [("Small (50%)", 50), ("Medium (70%)", 70), ("Full (100%)", 100)] {
            let option = action(title, #selector(setSize(_:)))
            option.tag = percent
            option.state = (percent == current) ? .on : .off
            menu.addItem(option)
        }
        item.submenu = menu
        return item
    }

    // M1: full structure, later items disabled.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "Hangabouts", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(disabled("No sessions yet"))
        menu.addItem(.separator())

        let hide = disabled("Hide Hangabouts") // built in M5
        hide.keyEquivalent = "h"
        hide.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(hide)

        let source = disabled("Needs you comes from") // built in M3
        let sourceMenu = NSMenu()
        sourceMenu.autoenablesItems = false
        sourceMenu.addItem(disabled("PermissionRequest only"))
        sourceMenu.addItem(disabled("Notification only"))
        sourceMenu.addItem(disabled("Both"))
        source.submenu = sourceMenu
        menu.addItem(source)

        let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        debugMenu.autoenablesItems = false
        debugMenu.addItem(action("Simulate Needs you", #selector(simulateNeedsYou)))
        debugMenu.addItem(action("Simulate Needs you in 5 s", #selector(simulateNeedsYouDelayed))) // debug-only, focus test
        debugMenu.addItem(disabled("Simulate Failed"))         // M5
        debugMenu.addItem(disabled("Simulate Done"))           // M5
        debugMenu.addItem(action("Clear all", #selector(clearAll)))
        debugMenu.addItem(sizeMenuItem())
        debugMenu.addItem(disabled("Short escalation timers")) // M5
        debugMenu.addItem(disabled("Open event log"))          // M3
        debug.submenu = debugMenu
        menu.addItem(debug)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hangabouts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
