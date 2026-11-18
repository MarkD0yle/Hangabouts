import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // Must live as long as the app, or the icon disappears at once.
    private var statusItem: NSStatusItem!
    private var creature: CreatureController!
    private let sessions = SessionStore()
    private let server = HookServer()
    private let eventLog = EventLog()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) // the icon is wider than it is tall

        statusItem.button?.setAccessibilityLabel("Hangabouts")

        creature = CreatureController(statusItem: statusItem)
        creature.onHangingChanged = { [weak self] hanging in self?.updateIcon(hanging: hanging) }
        updateIcon(hanging: false)

        // The menu is rebuilt each time it opens (menuNeedsUpdate), so the session list is always current.
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        populate(menu)
        statusItem.menu = menu

        sessions.onChange = { [weak self] in self?.sessionsChanged() }
        eventLog.onLog = { [weak self] in self?.creature.log($0) }
        eventLog.open()
        server.onLog = { [weak self] in self?.creature.log($0) }
        server.onEvent = { [weak self] in self?.received($0) }
        server.start()

        // For checking a build from a terminal: Hangabouts --simulate-needs
        if CommandLine.arguments.contains("--simulate-needs") {
            perform(#selector(simulateNeedsYou), with: nil, afterDelay: 1)
        }
    }

    /// Resting: his eyes peek out of his burrow. Hanging: the empty burrow, with the swing's rope running down to the creature panel.
    private func updateIcon(hanging: Bool) {
        guard let button = statusItem.button else { return }
        let barHeight = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        button.image = hanging
            ? MenuBarIcon.hanging(barHeight: barHeight, ropeWidth: CreatureController.ropeWidthAtFullSize * creature.scale)
            : MenuBarIcon.resting(barHeight: barHeight)
    }

    // MARK: - Hook events (M3)

    private func received(_ event: HookEvent) {
        let stateAfter = sessions.apply(event)
        eventLog.append(event, stateAfter: stateAfter?.rawValue)
        if event.payload["session_id"] as? String == nil {
            creature.log("\(event.name) had no session_id; logged and ignored")
        }
    }

    /// Snuffler hangs for the highest-priority session: Failed, then Needs you. Otherwise he stays up.
    private func sessionsChanged() {
        switch sessions.top?.state {
        case .failed: creature.present(.failed)
        case .needsYou: creature.present(.needs)
        default: creature.present(nil)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    @objc private func setNeedsYouSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = NeedsYouSource(rawValue: raw) else { return }
        sessions.needsYouSource = source
    }

    @objc private func openEventLog() {
        eventLog.open() // makes sure the file exists
        NSWorkspace.shared.open(eventLog.url)
    }

    // MARK: - Debug actions

    @objc private func simulateNeedsYou() {
        // Already simulated: give him a push instead, as in M2.
        if !sessions.simulateNeedsYou() { creature.nudge() }
    }

    @objc private func simulateNeedsYouDelayed() {
        // Gives the human time to click into another app and start typing (focus test M2-5).
        perform(#selector(simulateNeedsYou), with: nil, afterDelay: 5)
    }

    @objc private func clearAll() {
        sessions.clearAll()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        creature.setScale(CGFloat(sender.tag) / 100)
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        if creature.isShowing { updateIcon(hanging: true) } // the rope in the icon follows his size
    }

    @objc private func toggleIdleLife(_ sender: NSMenuItem) {
        creature.setIdleLife(!creature.idleLife)
        sender.state = creature.idleLife ? .on : .off
    }

    @objc private func pump() {
        creature.pump()
    }

    @objc private func swapArms() {
        creature.swapArms()
    }

    @objc private func toggleTired(_ sender: NSMenuItem) {
        creature.setTired(!creature.tired)
        sender.state = creature.tired ? .on : .off
    }

    /// Debug › Size submenu. Tags are percentages.
    private func sizeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = Int((creature.scale * 100).rounded())
        for (title, percent) in [("Tiny (25%)", 25), ("Small (35%)", 35), ("Medium (50%)", 50), ("Large (70%)", 70), ("Full (100%)", 100)] {
            let option = action(title, #selector(setSize(_:)))
            option.tag = percent
            option.state = (percent == current) ? .on : .off
            menu.addItem(option)
        }
        item.submenu = menu
        return item
    }

    // Items for later milestones are present but disabled.
    private func populate(_ menu: NSMenu) {
        let title = NSMenuItem(title: "Hangabouts", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        switch server.status {
        case .portInUse: menu.addItem(disabled("Port \(HookServer.port) in use"))
        case .failed: menu.addItem(disabled("Hook server not running"))
        case .starting, .listening: break
        }
        let list = sessions.ordered
        if list.isEmpty { menu.addItem(disabled("No sessions yet")) }
        for session in list {
            menu.addItem(disabled("\(session.folderName) – \(session.state.menuLabel)"))
        }
        menu.addItem(.separator())

        let hide = disabled("Hide Hangabouts") // built in M5
        hide.keyEquivalent = "h"
        hide.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(hide)

        let source = NSMenuItem(title: "Needs you comes from", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu()
        sourceMenu.autoenablesItems = false
        for option in NeedsYouSource.allCases {
            let item = action(option.menuLabel, #selector(setNeedsYouSource(_:)))
            item.representedObject = option.rawValue
            item.state = (option == sessions.needsYouSource) ? .on : .off
            sourceMenu.addItem(item)
        }
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
        let idle = action("Idle life (blink, sniff, pump, swap arms)", #selector(toggleIdleLife(_:))) // debug-only, off by default
        idle.state = creature.idleLife ? .on : .off
        debugMenu.addItem(idle)
        debugMenu.addItem(action("Pump", #selector(pump)))            // Spec 004
        debugMenu.addItem(action("Swap arms", #selector(swapArms)))   // Spec 004
        let tired = action("Tired (swap arms every 9 s)", #selector(toggleTired(_:))) // Spec 004, off by default
        tired.state = creature.tired ? .on : .off
        debugMenu.addItem(tired)
        debugMenu.addItem(disabled("Short escalation timers")) // M5
        debugMenu.addItem(action("Open event log", #selector(openEventLog)))
        debug.submenu = debugMenu
        menu.addItem(debug)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hangabouts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
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
