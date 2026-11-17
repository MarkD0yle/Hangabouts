# Kickoff M2: Snuffler drops from the menu bar

**For Claude Code.** M1 is proven: the icon and menu work on macOS. This brief covers M2 only.

To start, the human pastes this into Claude Code at the repo root, on branch `spec-002-m2`:

> Read KICKOFF-M2.md and follow it.

---

## 1. Read first

1. `CLAUDE.md`: repo rules.
2. `specs/002-test-hangabout.md`: the sections **Placement**, **Assets already in the repo** and **Milestones**.
3. `KICKOFF.md`, section 3: the traps, especially **Traps for later milestones**.
4. `app/Resources/snuffler-hanging.html`: the creature's JavaScript API.
5. The M1 code in `app/Sources/Hangabouts/`.

## 2. Goal

Debug › **Simulate Needs you** makes Snuffler drop from under his menu bar icon, swing 2–3 times over about 2 seconds, then hang completely still. Debug › **Clear all** makes him climb back up and disappear.

No hooks, no card, no state machine. Those are M3 and M4.

## 3. Risks to watch (read before coding)

| Risk | Why it matters | What to do in M2 |
|---|---|---|
| **The panel steals focus** | If Snuffler takes focus from the app you're typing in, the product fails. | Non-activating panel. Never call `makeKey`, `makeKeyAndOrderFront` or `NSApp.activate`. Use `orderFrontRegardless()`. Check with test M2-5. |
| **The transparent corners block clicks** | The panel is 180×225 pt, but Snuffler only fills part of it. The empty corners would swallow clicks on browser tabs and toolbars underneath. | Don't fix it in M2. Measure it in test M2-6 and report. A fix (toggling `ignoresMouseEvents` from the pointer position) is a later decision. |
| **The panel stays after climbing** | An invisible window left on screen blocks clicks forever. | After the page sends `climbed`, call `orderOut(nil)`. Check with test M2-6. |
| **Web view memory** | The spec accepts roughly 30–50 MB for this test. More than that changes the plan. | Report the app's memory in Activity Monitor with Snuffler showing. |
| **White box behind Snuffler** | `WKWebView` draws a white background by default. | Make the web view transparent (see section 5). If the only way is a private key, say so in the report. |

## 4. Build

### Files

```
app/Sources/Hangabouts/
  AppDelegate.swift        add: enable Simulate Needs you and Clear all, wire to the controller
  CreaturePanel.swift      new: the floating NSPanel
  CreatureWebView.swift    new: WKWebView subclass (first-click fix)
  CreatureController.swift new: owns panel + web view, talks to the page's JS API
```

### `CreaturePanel`

- `NSPanel` with style mask `[.borderless, .nonactivatingPanel]`.
- Size: the page is built for 180×225 pt. Since M2 testing it's drawn at 35% by default with `pageZoom`. Debug › Size offers 25%, 35%, 50%, 70% and 100%.
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
- `level = .statusBar`.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- `hidesOnDeactivate = false`.
- Override `canBecomeKey` and `canBecomeMain` to return `false` for M2. M4 will revisit this for the card.

### `CreatureWebView`

- Subclass `WKWebView`. Override `acceptsFirstMouse(for:)` to return `true`, so the first click on Snuffler counts.

### `CreatureController`

- **Load:** `loadFileURL` with `snuffler-hanging.html` from `Bundle.main`, allowing read access to the Resources folder.
- **Message handler:** register `hangabout` on the `WKUserContentController` **before** loading. The page posts `ready` straight away.
- **Avoid a retain cycle:** `WKUserContentController` holds its handlers strongly. Use a small weak-forwarding proxy object as the handler.
- **Queue calls until `ready`.** If Simulate is pressed before the page has loaded, run the call after `ready` arrives.
- **Messages from the page:**

| Message | Do this |
|---|---|
| `ready` | Mark the page ready. Run any queued call. |
| `shown` | Log it. |
| `clicked` | Log it (`print` or `os_log`). The card comes in M4. |
| `climbed` | `orderOut(nil)` on the panel. |

- **Calls into the page:** `evaluateJavaScript("hangabout.show('needs')")` and so on. Pass strings safely. Don't build JavaScript from untrusted text. M2 only uses fixed strings.

### Placement

- Get the icon's frame from `statusItem.button?.window?.frame`. That's in screen coordinates.
- Panel x = icon `midX` − 90. Panel top = icon window `minY` (the bottom of the menu bar), so panel origin y = icon window `minY` − 225.
- Use the screen the icon is on: `statusItem.button?.window?.screen`.
- Recalculate every time Snuffler shows, and when `NSApplication.didChangeScreenParametersNotification` fires.
- If the icon's window or frame isn't available (for example, hidden behind the notch), log it and place the panel at the top right of the main screen, 120 pt from the right edge. Report it if it happens.

### Debug menu (M2 items)

| Item | Behaviour |
|---|---|
| **Simulate Needs you** | If hidden: position the panel, `orderFrontRegardless()`, then `hangabout.show('needs')`. If already showing: `hangabout.nudge(1)`. This lets the human preview the nudge too. |
| **Simulate Needs you in 5 s** | New, debug-only. Same thing after a 5-second delay. Needed for the focus test M2-5. |
| **Clear all** | `hangabout.climb()`. The panel is ordered out when `climbed` arrives. |

Leave the other Debug items disabled.

## 5. Transparent web view

- Set the web view's `drawsBackground` to `false` with `setValue(false, forKey: "drawsBackground")`. This is a widely used workaround but it is not public API. Note it in the report.
- Also set `underPageBackgroundColor = .clear`.
- If a white or grey box still shows, report it with a screenshot description. Don't try a different rendering approach without asking.

## 6. M2 is done when

The human runs these on macOS after `./app/scripts/bundle.sh && open app/build/Hangabouts.app`.

| ID | Steps | Pass when |
|---|---|---|
| M2-1 (T2) | Debug › Simulate Needs you | Drops from under the icon, 2–3 swings over about 2 s, then completely still |
| M2-2 | Look closely while he hangs | Hands meet the bottom of the menu bar, centred on the icon. No white or grey box |
| M2-3 | Simulate Needs you again while he hangs | One settling swing (nudge), then still |
| M2-4 | Debug › Clear all | Climbs up and disappears within about 1 s |
| M2-5 (T14 early) | Simulate Needs you in 5 s, then click into TextEdit and keep typing | Snuffler drops. Typing continues. TextEdit keeps focus |
| M2-6 | Show Snuffler. Click in the empty transparent corners. Then Clear all and click where he was | First part: note whether the clicks reach the app underneath (expected: they don't, report it). Second part: clicks **do** reach the app underneath |
| M2-7 | Click Snuffler | "clicked" appears in the log. The frontmost app doesn't change |
| M2-8 | While he hangs, switch to another Space (Desktop 2) | Snuffler is still there |
| M2-9 | Optional: a full-screen app in front, then Simulate Needs you in 5 s | Shows over the full-screen app, or record that it doesn't |
| M2-10 | Optional: second display. Simulate on each screen's menu bar | Appears under the icon on the right screen |
| M2-11 | Activity Monitor with Snuffler showing | Record the memory figure |

## 7. Then stop

Don't start M3. Report to the human, briefly:

- **Results:** each test above. Mark which you could check yourself (build, logs) and which need the human's eyes.
- **Memory** from M2-11.
- **Click-through** result from M2-6, and your recommendation: fix now, fix in M5, or leave.
- **Private API use:** `drawsBackground`, and anything else.
- **Changes from the spec**, or "none."
- **Risks for M3**, especially anything about the open questions in Spec 002 (`idle_prompt`, clearing Failed, Esc interrupts).

Suggest the commit message `M2: Snuffler drops and climbs`. Commit only if the human says yes.
