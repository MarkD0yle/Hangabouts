# Spec 002: Build a test Hangabout

**Status:** In progress (M4 of 5 done). M1 to M4 are merged. M5, polish for the test, is next.
**Owner:** Mark (product), Claude Code (build)
**Depends on:** Spec 001 for the final "needs you" event. This build listens to both candidate events, so it can start now.
**Working name:** Hangabouts. Known risk: "hang" means "frozen" in software. Revisit before any public launch.

## Goal

A minimal macOS menu bar app with **one Hangabout: Snuffler**. It must prove one thing:

> When a Claude Code session needs you, Snuffler drops from the menu bar, you notice, you click, and you're back in the terminal faster than without it.

This is a test build, not the product. Favour speed and learning over polish.

## What "done" looks like

1. Snuffler sits as a still icon in the menu bar.
2. A Claude Code session in `sandbox-002/` hits a permission prompt.
3. Within about 1 second, Snuffler drops below its icon, swings 2–3 times, then hangs still holding a "?" sign.
4. You click him. A small card says what's needed and offers **Go to terminal**.
5. You answer in the terminal. Snuffler climbs back up by himself.

## Out of scope

- Answering prompts from the card. That's version 2.
- More species, the "Busy" and "Done" creature poses on screen, sound.
- Detecting screen sharing automatically. There's no reliable public macOS API for it. A manual hide is enough for this test.
- Signing, notarising, an installer, auto-start at login.
- The Claude app's background tasks.

## Tech choices

| Choice | Decision | Why |
|---|---|---|
| Language and UI | Swift, SwiftUI plus AppKit | Native menu bar item and floating panel. |
| Minimum macOS | 14 (Sonoma) | Modern SwiftUI and Observation. |
| Project shape | Swift Package with one executable target, plus `scripts/bundle.sh` that wraps it into `Hangabouts.app` | Claude Code can build it from the terminal without an Xcode project file. |
| Menu bar only | `LSUIElement = true` in the bundle's `Info.plist` | No Dock icon. |
| Creature rendering | Transparent `WKWebView` loading `app-assets/snuffler-hanging.html` | Reuses the design's SVG and CSS animation exactly. The trade-off is roughly 30–50 MB of memory. Fine for a test. Native drawing comes later. |
| Hook receiver | Built-in HTTP server using `Network.framework` (`NWListener`), bound to `127.0.0.1:7788` | No dependencies. Port 7788 avoids clashing with Spec 001's listener on 7777. |
| Dependencies | None | Keep the build simple. |

## Repo layout to create

```
app/
  Package.swift
  Sources/Hangabouts/
    HangaboutsApp.swift      App entry, menu bar item, menu
    HookServer.swift         NWListener HTTP server, parses POST /hooks/<Event>
    SessionStore.swift       Per-session state machine (see below)
    CreaturePanel.swift      Floating NSPanel + WKWebView, positioning
    DetailCard.swift         SwiftUI card shown on click
    TerminalActivator.swift  Brings the terminal app to the front
    EventLog.swift           Appends JSON lines to the log file
  Resources/
    snuffler-hanging.html    Copy of app-assets/snuffler-hanging.html
    menubar-icon.png, @2x, @3x
  scripts/
    bundle.sh                swift build -c release, then assemble Hangabouts.app with Info.plist and resources
sandbox-002/.claude/settings.json   Already created. Hooks post to port 7788
```

## Assets already in the repo

- `app-assets/snuffler-hanging.html` is the creature, with its animation and a small JavaScript API:

| Call | What it does |
|---|---|
| `hangabout.show("needs" or "failed", label)` | Drops in, swings once, then hangs still. `"failed"` shows a "!" sign, a droopy eyelid and a sweat drop. |
| `hangabout.nudge(1 or 2)` | Level 1: one settling swing. Level 2: a bigger swing plus a leg kick. |
| `hangabout.climb()` | Climbs back up and out of sight, then sends a `climbed` message. |
| `hangabout.hide()` | Hides at once. |
| `hangabout.setReducedMotion(true or false)` | Turns all motion off. |

- It sends messages to Swift through `window.webkit.messageHandlers.hangabout`: `{type: "ready"}`, `"shown"`, `"clicked"` and `"climbed"`.
- The page is exactly 270×262 px with a transparent background. Snuffler hangs by one hand from a swing: two ropes from the top centre, (135, 0), down to a wooden bar. The page is wider than he is, so he can swing and turn.
- **Redesigned after M2:** Snuffler is now a 3D model drawn live with WebGL (no libraries). Extra calls: `hangabout.turn(angle)`, `hangabout.setIdle(true or false)`, `hangabout.setZoom(zoom)`. The page also sends `{type: "error", message}` if WebGL fails. Design pages are in `design/`.
- **Menu bar icon:** drawn in code (`MenuBarIcon.swift`). It's his burrow, the hole he drops out of. Resting, his eyes and nose peek out. While he hangs, the hole is empty and the swing's rope runs from it down to the panel. `app-assets/menubar-icon*.png` is no longer used.
- **Risk:** idle life (blink, sniff, breathing) breaks "then completely still". It's off by default, behind Debug › Idle life.

## Behaviour

### Events to state

The app keeps state **per Claude Code session** (key: `session_id`). Ignore events without one, but log them.

| Event received | Session state becomes |
|---|---|
| `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | **Working** |
| `PreToolUse` for the `AskUserQuestion` tool | **Needs you** (reason: "Has a question") |
| `PermissionRequest` | **Needs you** (reason: tool name, e.g. "Wants to run Bash") |
| `PermissionDenied` (auto mode blocked a tool call) | **Needs you** (reason: e.g. "Auto mode blocked Bash") |
| `Notification` with `notification_type` `permission_prompt` | **Needs you**, unless already Needs you |
| `Notification` with `notification_type` `idle_prompt` | **Done**, if the session was Working. Otherwise no change |
| `Stop` | **Done** |
| `StopFailure` | **Failed** (reason: `error`, plus `error_details` if present) |
| `SessionEnd` | Remove the session |

**How "Needs you" clears:** any later `PreToolUse`, `PostToolUse`, `UserPromptSubmit` or `Stop` for that session means you answered. Snuffler climbs back up.

**Exception, auto mode blocks:** a later tool event clears it (Claude found a way round). `Stop` does not: if the turn ends still blocked, he stays until your next prompt.

**How "Failed" clears:** only the next `UserPromptSubmit` or `SessionStart` for that session. Tool events and `Stop` leave it Failed.

**Event source switch:** a menu setting, "Needs you comes from", with three options: `PermissionRequest` only, `Notification` only, or both (default). Spec 001 decides which wins.

### What's on screen

| Overall state (across all sessions) | Menu bar icon | Snuffler |
|---|---|---|
| Nothing running | Still icon | Hidden |
| Any session Working | Still icon. The menu lists sessions as "Digging" | Hidden |
| Any session Done, none Needs you | Icon with a small blue dot badge | Hidden |
| Any session Needs you | Still icon | **Hanging**, "?" sign |
| Any session Failed | Still icon | **Hanging**, "!" sign, sheepish |

- **Priority:** Failed > Needs you > Done > Working > Nothing. Snuffler shows the highest one.
- **Several sessions need you:** show one Snuffler for the oldest. The card lists the rest, e.g. "+2 more waiting." (The chain of hanging creatures is a later idea.)
- **Done badge clears** when you open the menu.

### Escalation

- Needs you for 5 minutes: `nudge(1)`.
- Needs you for 15 minutes: `nudge(2)`.
- Nothing after that. It never swings constantly.
- A debug setting shortens these to 10 and 30 seconds.

### Placement

- The panel is a borderless, non-activating `NSPanel`, transparent, no shadow.
- **Size:** the creature page is designed at 270×262 px. It is drawn at **35% by default (95×92 pt)** using the web view's page zoom. Debug › Size offers 25%, 35%, 50%, 70% and 100%, saved between launches. Changed after M2 testing: full size, then 50%, felt too big.
- Window level: above normal windows, on all Spaces, allowed over full-screen apps (`.statusBar` level, `.canJoinAllSpaces`, `.fullScreenAuxiliary`).
- Position: horizontally centred on the menu bar icon (from the status item button's window frame). Top edge flush with the bottom of the menu bar, on the same screen as the icon.
- Hanging must not steal focus from the app you're typing in.
- If the icon is hidden behind the MacBook notch or there's no space for it, place the panel just left of the notch. If that's unreliable, log it as a known issue. Don't block the build on it.

### Click and card

- Clicking Snuffler opens a small SwiftUI card under him, anchored to the panel. It shows:
  - the title "Snuffler needs you" or "Snuffler hit a problem"
  - the reason
  - the session's folder name (last part of `cwd`)
  - how long it's been waiting
  - "+N more waiting" if there are others
- Buttons:
  - **Go to terminal** brings the session's app forward: whichever app was frontmost when you last sent that session a prompt. Falls back to Terminal.
  - **Hide for 10 minutes** sends Snuffler up without clearing the state.
- `Escape`, clicking elsewhere, or clicking Snuffler again closes the card.

As built in M4:

- **The app is noted at `UserPromptSubmit`, not `SessionStart`.** `SessionStart` doesn't arrive over HTTP hooks. A prompt is also the better moment: you have just typed in that app.
- **It can't pick the right window or tab.** It only brings the app forward.
- **No setting to name a terminal app yet.** Add one if the default guesses wrong.
- **Hide for 10 minutes hides everything.** A different session that needs you in that time won't show either. Debug › Simulate Needs you and Clear all end the hide early.
- **The card takes the keyboard while it is open,** so Escape works. It never opens on its own: only after a click on Snuffler.
- **Debug:** `Hangabouts --simulate-needs --open-card` opens the card with no click, for checking a build from a terminal.

### Menu bar menu

- A list of sessions: folder name and state ("Digging", "Needs you", "Done", "Failed").
- **Hide Hangabouts** toggle, with a global shortcut ⌃⌥H. This is the manual stand-in for screen-share hiding.
- "Needs you comes from" setting (see above).
- **Debug** submenu:
  - Simulate Needs you, Simulate Failed, Simulate Done, Clear all. These must work with no Claude Code session at all.
  - Short escalation timers (on or off).
  - Open the event log.
- Quit.

### Accessibility

- Respect macOS "Reduce motion" (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`). Call `setReducedMotion` on load and whenever it changes.
- The creature is a real button with an accessible label. VoiceOver should announce "Snuffler needs you".
- The card's buttons need to be keyboard-reachable.

## Hook server details

- Accept only `POST /hooks/<EventName>`. Anything else gets a 404.
- Bind to `127.0.0.1` only. Never `0.0.0.0`.
- Read headers, then exactly `Content-Length` bytes. Reject bodies over 5 MB.
- **Always reply `200` with body `{}` straight away.** Never return a decision. For `PermissionRequest`, a decision would approve or deny the prompt.
- Post each parsed event to the main thread for the state machine.
- Log every event as one JSON line to `~/Library/Application Support/Hangabouts/events.jsonl`, using the same shape as Spec 001's listener (`event`, `receivedAt`, `receivedAtMs`, `payload`). Add `stateAfter`.
- If port 7788 is taken, show "Port 7788 in use" in the menu and keep running.

## Build and run

```bash
cd app
./scripts/bundle.sh          # builds release and assembles build/Hangabouts.app
open build/Hangabouts.app

# separate terminal
cd sandbox-002 && claude
```

## Milestones

Build in this order. Each one should run before starting the next.

1. **M1 Skeleton:** menu bar icon, menu with Quit and Debug, `bundle.sh` works, no Dock icon.
2. **M2 Creature:** panel and web view placed under the icon. Debug "Simulate Needs you" makes Snuffler drop, swing and settle. "Clear all" makes him climb back.
3. **M3 Hooks:** HTTP server, event log, per-session state machine. A real permission prompt in `sandbox-002` triggers Snuffler.
4. **M4 Card:** click opens the card, Go to terminal works, answering in the terminal makes him climb.
5. **M5 Polish for test:** escalation timers, several sessions, Failed pose, Reduce motion, hide toggle and shortcut, Done badge.

## Acceptance tests (manual)

Run with `sandbox-002`. Use "yes, once" on every permission prompt, never "always allow."

| ID | Steps | Pass when |
|---|---|---|
| T1 | Launch the app | Icon in menu bar, no Dock icon, Snuffler hidden |
| T2 | Debug › Simulate Needs you | Drops, 2–3 swings over about 2 s, then completely still |
| T3 | In sandbox: "Run `date` and tell me the time", then switch to another app | Snuffler appears within about 1 s of the prompt |
| T4 | Click Snuffler | Card shows reason "Wants to run Bash", folder `sandbox-002`, wait time |
| T5 | Go to terminal, approve the prompt | Terminal comes forward. Snuffler climbs up within about 1 s of approving |
| T6 | Short timers on. Trigger T3 and wait 30 s | One small swing at 10 s, a bigger one at 30 s, still otherwise |
| T7 | Two sandbox sessions, both prompt | One Snuffler, card says "+1 more waiting" |
| T8 | Turn on Reduce motion in System Settings, repeat T2 | Snuffler appears and leaves without any movement |
| T9 | ⌃⌥H while Snuffler is hanging | Hides at once. Press again, he's back |
| T10 | Debug › Simulate Failed | "!" sign, droopy eye, sweat drop |
| T11 | Prompt finishes normally with no permission needed | No hanging. Blue dot badge on icon, cleared when you open the menu |
| T12 | Full-screen app in front, trigger T3 | Snuffler shows over the full-screen app, or logged as a known issue |
| T13 | Quit the app, use Claude Code in the sandbox | Claude Code works normally. Non-blocking hook errors are expected; nothing blocks or hangs |
| T14 | Typing in another app when Snuffler drops | Typing isn't interrupted; focus doesn't move |

## Decisions made for M3

Auto mode is now Claude Code's default. It approves low-risk tool calls itself, so `PermissionRequest` rarely fires and Snuffler rarely dropped. Two triggers were added for it:

- **A question (`AskUserQuestion`) maps to Needs you.** The source switch doesn't apply to it.
- **An auto mode block (`PermissionDenied`) maps to Needs you.** Risk: Claude often routes round a block within seconds, so he may drop briefly for nothing.
- **Neither has been seen in a real session yet.** Headless runs have no question tool, and auto mode didn't block the harmless test commands. Both were tested with hand-made events built from the hooks docs.

Seen in real sessions:

- **`SessionStart` does not arrive over HTTP hooks.** A session first appears on its first prompt.
- **A failed tool call sends no `PostToolUse`.** It sends `PostToolUseFailure`, which the sandbox doesn't hook.

These were open questions from a review against the Claude Code hooks docs. Not yet checked against Spec 001 results.

- **`idle_prompt` maps to Done, not Needs you.** It fires about 60 s after every finished turn. Mapping it to Needs you would drop Snuffler after every task you walk away from.
- **Failed clears on the next `UserPromptSubmit` or `SessionStart`** for that session.
- **`StopFailure` reason** comes from `error` (e.g. `rate_limit`), with optional `error_details`.

Known limits:

- **`Stop` doesn't fire on Esc.** If you interrupt at a permission prompt, Needs you stays until your next prompt. Add an interrupt scenario to Spec 001 if this matters.
- **Parallel tool calls can clear Needs you early.** A `PostToolUse` from another tool in the same session counts as "you answered".
- **Debug › Clear all forgets real sessions too.** They come back on their next event.

## The experiment this enables

Once T1–T14 pass, run the real test from the product plan:

- **Week 1, without the app:** note how long Claude Code sessions wait for you. The Spec 001 listener can log this: time from `PermissionRequest` to the next `PostToolUse`. Two gaps: the sandbox hooks only cover the sandbox, so real work needs the hooks in your user settings; and `analyze.mjs` doesn't yet calculate this wait time.
- **Week 2, with the app:** the same, from the app's event log.
- **Pass:** median wait time drops by half or more.
- **Also note:** any moment Snuffler annoyed you, and any moment you missed him.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Notch hides the menu bar icon | Snuffler hangs from nowhere | Fallback placement left of the notch. Test on a MacBook. |
| Panel steals focus when shown | Interrupts typing, kills trust | `.nonactivatingPanel`, never call `makeKey` on show. T14 checks this. |
| Web view memory | Heavier than a native app | Acceptable for the test. Native drawing for v1. |
| `PermissionRequest` fires but the prompt is auto-approved by a rule | Snuffler drops for nothing | Climb on the next `PostToolUse`. Log how often it happens. |
| Hook payload fields differ from what's assumed | Missing reasons or folder names | Log raw payloads. Show "Needs you" with no reason rather than failing. |
| Over-cute in a work setting | You hide it and forget it | That's a valid test result. Record it. |
