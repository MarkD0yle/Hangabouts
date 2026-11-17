import AppKit

// Menu bar only: LSUIElement = true in Info.plist keeps it out of the Dock and ⌘Tab.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
