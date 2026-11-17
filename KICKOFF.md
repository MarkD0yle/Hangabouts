# Kickoff: build the test Hangabout

**For Claude Code.** This file starts the build of Spec 002. Read it top to bottom before writing any code.

To start, the human pastes this into Claude Code at the repo root:

> Read KICKOFF.md and follow it.

---

## 1. Read first, in this order

1. `CLAUDE.md`: repo rules. They override anything here.
2. `specs/002-test-hangabout.md`: the full spec. Read all of it, even though you're only building M1 now.
3. `app-assets/snuffler-hanging.html`: the creature and its JavaScript API. You won't use it until M2, but its size and API shape the panel design.

Don't read the `specs/001` harness unless you need its log format. That's in Spec 002 under "Hook server details".

## 2. Check the machine before coding

Run these and report the results:

```bash
sw_vers -productVersion   # needs 14.0 or later
swift --version           # needs Swift 5.9 or later
xcode-select -p           # must print a path
```

If any check fails, **stop**. Tell the human what's missing and how to fix it. Don't work around it.

## 3. Known traps (read before M1)

- **Resources: use `Bundle.main`, not `Bundle.module`.** Keep assets in `app/Resources/`, outside `Sources/`, and don't declare them as SwiftPM resources. `bundle.sh` copies them into `Hangabouts.app/Contents/Resources/`. SwiftPM's generated `Bundle.module` looks in the wrong place once the binary sits inside a hand-built `.app`, and it crashes at launch.
- **No Dock icon** needs `LSUIElement = true` in `Info.plist`. Don't call `NSApp.setActivationPolicy(.regular)` anywhere.
- **The status item must be retained.** Keep the `NSStatusItem` in a property that lives as long as the app, or the icon disappears at once.
- **SwiftUI `App` vs AppKit.** A `MenuBarExtra` is tempting, but the creature panel needs AppKit control (non-activating `NSPanel`, exact placement under the icon). Use an `NSApplicationDelegate` with an `NSStatusItem`. SwiftUI is fine *inside* views, such as the card in M4.
- **Template image.** The menu bar icon is coloured. Set `isTemplate = false`, and size it to 18×18 pt.

### Traps for later milestones

- **M2: clicks on the creature.** A web view in a non-activating panel may ignore the first click. You may need a `WKWebView` subclass that returns `true` from `acceptsFirstMouse(for:)`.
- **M2: register the `hangabout` message handler before loading the page.** The page posts `ready` as soon as it loads.
- **M4: Escape on the card** needs the card's window to become key. That's fine after a click. Never make anything key when Snuffler first drops.
- **M5: the ⌃⌥H global shortcut.** `NSEvent` global monitors need Accessibility permission. Carbon's `RegisterEventHotKey` doesn't. Prefer it.

## 4. Build M1 only: Skeleton

**Goal:** the app launches, shows Snuffler's icon in the menu bar, and has a working menu. Nothing else.

### Create

```
app/
  Package.swift                   one executable target "Hangabouts", platforms: macOS 14
  Sources/Hangabouts/
    main.swift                    starts NSApplication with AppDelegate
    AppDelegate.swift             status item, icon, menu
  Resources/
    menubar-icon.png              copied from app-assets/
    menubar-icon@2x.png
    menubar-icon@3x.png
    snuffler-hanging.html         copied now, used in M2
  scripts/
    bundle.sh
  Info.plist                      template used by bundle.sh
```

### The menu (M1 version)

```
Hangabouts
──────────
No sessions yet          (disabled)
──────────
Hide Hangabouts  ⌃⌥H     (disabled; built in M5)
Needs you comes from ›   (disabled; built in M3)
Debug ›
   Simulate Needs you    (disabled; built in M2)
   Simulate Failed       (disabled; built in M5)
   Simulate Done         (disabled; built in M5)
   Clear all             (disabled; built in M2)
   Short escalation timers (disabled; built in M5)
   Open event log        (disabled; built in M3)
──────────
Quit Hangabouts  ⌘Q
```

Showing the full menu with later items disabled lets the human check the structure early.

### `scripts/bundle.sh`

It must:

1. Fail clearly if not on macOS: `uname` isn't `Darwin` → print "Hangabouts builds on macOS only" and exit 1.
2. Fail clearly if `swift` is missing.
3. Run `swift build -c release` from `app/`.
4. Assemble `app/build/Hangabouts.app`:
   - `Contents/MacOS/Hangabouts`: the release binary
   - `Contents/Resources/`: everything in `app/Resources/`
   - `Contents/Info.plist`, from the template
5. Print the path of the finished app and the command to open it.

Use `set -euo pipefail`. Make it work from any current directory.

### `Info.plist` must include

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.markdoyle.hangabouts` |
| `CFBundleName` | `Hangabouts` |
| `CFBundleExecutable` | `Hangabouts` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | `0.0.1` |
| `LSMinimumSystemVersion` | `14.0` |
| `LSUIElement` | `true` |

### Add to `.gitignore`

```
app/.build/
app/build/
```

## 5. M1 is done when

- [ ] `./app/scripts/bundle.sh` builds without warnings you introduced.
- [ ] `open app/build/Hangabouts.app` shows the icon in the menu bar.
- [ ] No Dock icon, and the app doesn't appear in ⌘Tab.
- [ ] The menu matches section 4, with later items disabled.
- [ ] Quit works.
- [ ] Running `bundle.sh` on Linux prints the macOS-only message and exits 1.

This is acceptance test **T1** in Spec 002.

## 6. Then stop

Don't start M2. Report back to the human, briefly:

- **What's working.** List the done criteria above and tick each one you verified yourself.
- **What you couldn't verify** and why, e.g. something only visible on screen.
- **How to run it:** the exact commands.
- **Any changes from the spec.** Say what changed and why. If none, say "none."
- **Any risks you noticed** for M2, especially placing the panel under the icon.

Then suggest a commit message: `M1: menu bar skeleton`. Commit only if the human says yes.

## 7. Later milestones

**M1 is done.** For M2, use `KICKOFF-M2.md`. Later milestones follow the same pattern: build, check against the tests, stop and report.

| Milestone | Spec 002 tests to check |
|---|---|
| M2 Creature | T2 |
| M3 Hooks | T3, T13 |
| M4 Card | T4, T5 |
| M5 Polish | T6 to T12, T14 |
