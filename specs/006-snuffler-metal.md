# Spec 006: Snuffler in Metal (no WebKit)

**Status:** Built, M1 to M5. WebKit is gone from the app. Not merged. The human hasn't run the on-screen checks (E5, E6, most of E7).
**Measured (M4 Mac, 35%):** resting 19 MB, hanging still 21 MB, one process. With idle life on: about 80 MB and 8% CPU while he animates (WebGL was about 105 MB and 21%).
**Owner:** Mark (product and design), Claude Code (build)
**Depends on:** Specs 003 and 004. The look, motion, poses and Swift-facing API stay the same. Only the engine underneath changes.
**Written to stand alone.** It can be added to a Claude project as background without the rest of the repo.
**Numbering:** written as "Spec 005". Saved as 006 because `005-readme.md` already had that number.

## Why

- Spec 002 budgeted 30–50 MB. Spec 003 measured 66–82 MB with Snuffler showing.
- Almost all of that is WebKit: a Web Content process, a GPU process and a networking process. They are a fixed cost. Snuffler's own pixels are under 1 MB at 35%.
- Snuffler is already one fragment shader plus a little JavaScript physics. Both port almost line for line to Metal and Swift.
- More species are coming. One Metal view can draw them all. Each web view can add another Web Content process, about 30–50 MB (estimated).

## Goal

- Snuffler looks and moves **the same** as the WebGL version, at every size and pose.
- **No WebKit** in the app.
- Memory with him hanging: **under 40 MB total** for the app (target; adjust once M1 is measured).
- CPU near zero when he's still, as now.
- Still no third-party code. Metal, MetalKit and QuartzCore are system frameworks.

## Not in this spec

- New poses (Busy, Done), new species, Spec 004's icon changes (5–7).
- Fixing click-blocking in the transparent area. M4 makes it easy; doing it is a later decision.

## Risks and open questions

Read these before writing code.

| Risk | Why it matters | What to do |
|---|---|---|
| **He looks slightly different** | GLSL and Metal differ in small ways. `mod()` vs `fmod()` with negative numbers. `atan(y, x)` vs `atan2`. Y is flipped (`gl_FragCoord` starts bottom-left; Metal starts top-left). Precision defaults. | Write GLSL-style helpers (`glsl_mod`, etc.). Flip Y once, in one place. Compare screenshots side by side (M1). |
| **Transparent edges look wrong** | WebGL output is premultiplied alpha. If the Metal layer isn't set up the same, he gets a dark or bright halo on wallpapers. | `CAMetalLayer`: `isOpaque = false`, `.bgra8Unorm`, clear to (0,0,0,0). Keep the shader writing `col * a, a`. Check on light and dark wallpapers. |
| **Two copies of the shader drift** | The design pages in `design/` and the Claude Design canvas still use GLSL. After this, the app uses Metal. | **Mark to decide.** Recommended: the `.metal` file becomes the source of truth. The design HTML pages stay as frozen references. |
| **Drop and climb are CSS today** | The page adds `dropping` and `climbing` classes to `#stage`. CSS moves him. That code doesn't port by itself. | Read the CSS for `#stage.dropping` and `#stage.climbing` first. Copy the exact timing and easing into Swift. Animate inside the view, not the panel. The panel and the rope must not move. |
| **The drop shadow may be CSS** | If it's a CSS `filter`, it disappears in the port. | Find where it's drawn. If it's CSS, add it to the shader (preferred: one pass, no extra layer). A `CALayer` shadow on a Metal layer is expensive. |
| **Accessibility is lost** | Today the DOM `#hit` element carries the `aria-label` and handles Enter and Space. A Metal view has neither. | Implement `NSAccessibility` on the view: button role, the same labels, press action. Test with VoiceOver. |
| **Shader compile time** | Compiling from source at launch costs time. | Compile once at launch with `device.makeLibrary(source:)`. Measure it. If it's over 150 ms, move it off the main thread. |
| **Build pipeline** | `bundle.sh` builds a hand-assembled `.app`. SwiftPM doesn't compile `.metal` files into a `.metallib` here. | Ship the shader as a text resource (`app/Resources/snuffler.metal`) and compile it at runtime. No build changes. Same `Bundle.main` rule as before. |

## Approach

- **Keep both renderers until M5.** Add Debug › Renderer: WebGL / Metal. This gives a side-by-side check and an instant way back.
- **Same public API.** `CreatureController` keeps `present(_:)`, `nudge()`, `pump()`, `swapArms()`, `setIdleLife(_:)`, `setTired(_:)`, `setScale(_:)` and `onHangingChanged`. `AppDelegate` shouldn't change.
- **Draw only when moving.** Use the view's display link (`NSView.displayLink(target:selector:)`, macOS 14). Pause it when everything is still, using the same rule as `frame()` in the page.

## Files

| File | What it is |
|---|---|
| `app/Resources/snuffler.metal` | **New.** The fragment shader, ported from `<script id="fs">` in `snuffler-hanging.html`. A vertex shader for one full-screen quad. |
| `app/Sources/Hangabouts/SnufflerUniforms.swift` | **New.** One struct with every uniform. It must match the Metal struct exactly (see below). |
| `app/Sources/Hangabouts/SnufflerMotion.swift` | **New.** Pure Swift. The state `S`, `step()`, the yaw spring, `swing`, `pump`, `armVals`, blink and sniff timing, drop and climb timing. No AppKit. Easy to unit test. |
| `app/Sources/Hangabouts/SnufflerView.swift` | **New.** `NSView` backed by `CAMetalLayer`. Owns the device, pipeline and display link. Handles click, drag-to-turn, keyboard and accessibility. |
| `app/Sources/Hangabouts/CreatureController.swift` | **Changed.** Owns a `SnufflerView` instead of a web view (behind the Debug switch until M5). |
| `CreatureWebView.swift`, `WeakMessageProxy`, `snuffler-hanging.html` (both copies) | **Removed in M5.** Keep `app-assets/snuffler-hanging.html` in `design/` as a reference. |

### Uniforms

Today: `uRes` (vec2) plus 17 floats: `uYaw, uSwing, uSignSwing, uSignYaw, uBlink, uKick, uTail, uSniff, uFail, uBreathe, uRaiseR, uRaiseL, uShakeR, uShakeL, uTired, uBody, uGrip`.

- Put `uRes` first as `SIMD2<Float>` / `float2`. Then the floats, in the same order on both sides.
- Pass it with `setFragmentBytes`. It's under 4 KB, so no buffer is needed.
- Add a `MemoryLayout<SnufflerUniforms>.stride` check against the Metal side in a test or debug assert.

### Sizes

- Keep the page's logic: design size 270×262, pixel scale `k = min(dpr, max(0.5, zoom × dpr × 1.5))`, with dpr capped at 2.
- The view's drawable size = 270 × k by 262 × k. The view's frame = the panel's content size.
- Recompute on scale change and when the panel moves to a screen with a different backing scale.

## Milestones

### M1: Still image matches

- Port the shader. Render a **still** Snuffler from fixed uniform values.
- Debug › Renderer switch in place.
- **Pass when:** side-by-side screenshots match at 35% and 100%, for:
  - Needs and Failed
  - yaw −1.45, 0, 0.95 (rest), 1.45
  - blink 1, kick 0.5, tired 1
- "Match" means no visible difference at 1×. Any difference you can see must be listed in the report, with a screenshot.
- **Measure memory** (all Hangabouts processes, resting and showing). Report it before going further. If it isn't well under the WebGL number, stop and report.

### M2: Motion matches

- Port `SnufflerMotion`: physics `step()` (keep the 4 ms sub-steps), yaw spring, pump, swing, arm swap, idle life, reduced motion.
- Port drop (0.75 s, spin-in from yaw −0.9) and climb (0.65 s) from the CSS.
- Keep every constant the same as the page. Copy, don't re-tune.
- **Pass when:** recorded side by side, Drop, Nudge 1, Pump, Swap arms and Climb look the same. Spec 004 checks D2–D6 and D8 pass on Metal.

### M3: Wire into the controller

- `CreatureController` drives `SnufflerView` directly. `shown`, `clicked` and `climbed` become direct calls, not messages.
- No `ready` wait is needed. Keep the call queue only if shader compile happens off the main thread.
- **Pass when:** Spec 003 checks C1–C8 pass on Metal.

### M4: Input and accessibility

- Click without drag → `onClicked`. Drag → turn (dx / 70 radians, as now). Enter and Space → click.
- `NSAccessibility`: role button, label "Snuffler needs you. Show details" or "Snuffler hit a problem. Show details", press action.
- Never make the panel key when he drops. Same rule as before.
- **Pass when:** C5, C6 and C8 pass. VoiceOver reads the label and can press him.

### M5: Remove WebKit and measure

- Delete the WebGL path, the Debug › Renderer switch, `CreatureWebView`, `WeakMessageProxy` and the `drawsBackground` hack.
- Remove `import WebKit` everywhere. Confirm WebKit no longer loads (`vmmap` or Activity Monitor shows no Web Content process).
- **Pass when:** all the checks below pass.

## Checks

| ID | Step | Pass when |
|---|---|---|
| E1 | Activity Monitor, search "Hangabouts", him resting | One process. No Web Content, GPU or Networking process from WebKit. |
| E2 | Same, him hanging | Under 40 MB total (or the target agreed after M1). |
| E3 | Hanging still, 1 minute, idle life off | CPU near zero. Display link paused. |
| E4 | Idle life on, 1 minute | Blinks and sniffs. CPU low (report the number). |
| E5 | Light and dark wallpaper, 35% and 100% | No halo or dark fringe around him. Drop shadow present. |
| E6 | Drag him to a second display with a different scale | Sharp, correctly sized, still under the icon. |
| E7 | Spec 003 C1–C11 and Spec 004 D1–D9 | All pass on Metal. |
| E8 | First drop after launch | No visible delay compared with WebGL. Report shader compile time. |

## Report back after each milestone

- What passed and what didn't.
- Memory and CPU numbers (all Hangabouts processes).
- Any visual difference from WebGL, with screenshots.
- Anything in this spec that turned out to be wrong.
