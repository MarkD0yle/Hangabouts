import AppKit

// Menu bar only: LSUIElement = true in Info.plist keeps it out of the Dock and ⌘Tab.
// Top-level code runs on the main thread; say so, so the @MainActor delegate can be created here.
// Line-buffer the console, so log lines show at once even when output is piped to a file.
setlinebuf(stdout)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
