import AppKit

// Menu bar only: LSUIElement = true in Info.plist keeps it out of the Dock and ⌘Tab.
// Top-level code runs on the main thread; say so, so the @MainActor delegate can be created here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
