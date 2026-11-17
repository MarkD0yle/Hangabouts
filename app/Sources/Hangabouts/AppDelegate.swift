import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Must live as long as the app, or the icon disappears at once.
    private var statusItem: NSStatusItem!

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

        statusItem.menu = buildMenu()
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
        debugMenu.addItem(disabled("Simulate Needs you"))      // M2
        debugMenu.addItem(disabled("Simulate Failed"))         // M5
        debugMenu.addItem(disabled("Simulate Done"))           // M5
        debugMenu.addItem(disabled("Clear all"))               // M2
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

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
