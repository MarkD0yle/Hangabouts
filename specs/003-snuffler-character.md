# Spec 003: Snuffler, the character

**Status:** Built on branch `spec-002-m2`. Not yet tested against the checks at the end.
**Owner:** Mark (product and design), Claude Code (build)
**Depends on:** Spec 002. This spec replaces the creature and the menu bar icon from that spec. Events, states, the hook server and the card are unchanged.
**Written to stand alone.** It can be added to a Claude project as background without the rest of the repo.

## What Hangabouts is, in three lines

- Animated creatures in the macOS menu bar that show what your AI agents are doing.
- The first creature is **Snuffler**, a research agent. He stays out of sight while the agent works.
- When a Claude Code session needs you, he drops from the menu bar and hangs there until you answer.

## Problems this redesign fixes

The first Snuffler was a flat drawing. Five things were wrong with it:

- **Too many small parts.** At the real on-screen size most of it turned to noise.
- **The snout was the weakest shape.** He's named for it, but it read as a second arm.
- **The "?" sign was the smallest thing on screen.** It's the whole message.
- **No edge on dark wallpapers.** A brown outline disappears on a dark desktop.
- **The icon was a yellow blob** at menu bar size, with no link to the creature below it.

## Risks and open questions

Read these before changing anything.

| Risk | Why it matters | Where it stands |
|---|---|---|
| **Idle life breaks "completely still"** | Spec 002 says he swings 2–3 times, then hangs still. Blinking and sniffing forever is the opposite. | Off by default. A debug toggle turns it on. **Mark to decide.** |
| **Bigger click-blocking area** | The panel is transparent but still swallows clicks. It grew from 63×79 pt to 95×92 pt at the default size. | Not fixed. A fix (ignore clicks outside his shape) is a later decision. |
| **Graphics cost** | He's drawn on the graphics card every frame he moves. | He stops drawing once still. Just after a drop, CPU was 5–8%. Not measured on an older Mac or over a long hang. |
| **Memory** | Spec 002 budgeted 30–50 MB. | Measured 66–82 MB with him showing. Over budget. |
| **Hard to edit** | His shape is maths in shader code, not a drawing. A designer can't open it in a drawing tool. | Accepted for the test. Revisit if the look needs frequent changes. |
| **Rope alignment** | The rope in the icon must meet the ropes on the panel, at every size. | Calculated, not yet seen on screen at each size. |
| **Dark menu bars** | A dark hole on a dark bar can vanish. | The soil rim is light enough in previews. Not checked on a real dark menu bar. |
| **One unexplained page reload** | Seen once in the app. It didn't repeat. | Unknown cause. Watch for it. |
| **Failed pose untested since reshaping** | The droopy ear and lid positions moved when he was made rounder. | Check before M5 uses it. |

## The character

**Who he is:** a small, round, mustard-coloured burrowing animal with a long snout. A researcher: monocle on one eye, satchel of papers on his hip.

**What he's made of:**

- Round body and a big round head, joined softly. Pale belly patch.
- Long snout that goes forward, then down, ending in a wet black nose. It gets darker toward the tip.
- Two eyes of different sizes. The big one has the gold monocle.
- Round ears, pink inside. They droop when he's failed.
- Short arms and legs, chubby feet, a ringed tail that curls up behind him.
- Green satchel on his left hip, strap over his right shoulder, a sheet of paper sticking out.
- **The sign:** a white card hanging on a string from his nose. Blue "?" when he needs you. Red "!" when he's failed. The card always turns to face you.

**How he hangs:**

- From a **swing**: two ropes from one point at the top, down to a wooden bar.
- He grips the bar with his right fist. His arm goes straight up from the shoulder.
- Everything swings from the top point. Because the ropes meet at one point, the swing twists with him when he turns.

**Poses:**

| Pose | Sign | Face |
|---|---|---|
| Needs you | Blue "?" | Normal |
| Failed | Red "!" | Half-closed big eye, worried brows, ears down |

## How he's drawn

- A real 3D model, drawn live in the app's web view with WebGL.
- **No third-party code.** The model is a set of rounded shapes (spheres, capsules, boxes) blended together, described in one shader. This keeps the repo's "no dependencies" rule.
- Lit from the top left. Soft shadows, contact shading where parts meet, gloss on the eyes, nose and monocle.
- A soft drop shadow under him separates him from the wallpaper.
- The page is **270×262 px**, transparent. The ropes start at the top centre, (135, 0). One unit of his world is 79 px.
- The page is wider than he is, so he has room to swing and turn.

## Motion

| Moment | What happens |
|---|---|
| Drop | Falls in over 0.75 s with a small bounce. He spins from facing left to his resting angle as he falls. |
| Settle | One damped swing from the top: about 10° at first, each swing about 1 s, fading out over about 4 s. |
| Follow-through | The sign and the tail swing a beat behind his body. |
| Rest | Three-quarter view, facing right. Then still. |
| Nudge 1 | The settle swing again. |
| Nudge 2 | A bigger swing (about 15°) plus a leg kick. |
| Turn | He can face anywhere from left profile to right profile. The turn is springy, with a little overshoot. Dragging him turns him. |
| Climb | Turns to face you, then rises out of sight in 0.65 s. |
| Idle life (optional) | A blink every 5 s, a sniff every 7 s, slow breathing, a tail sway. |
| Reduce motion | No movement at all. He appears and disappears in place. |

## The menu bar icon

The icon is **his burrow: the hole he drops out of.** It's drawn in code, so it always lines up with the creature.

| State | Icon |
|---|---|
| Resting | A mound of soil with a dark opening. His two uneven eyes show in the dark. The tip of his snout rests on the front lip. |
| Hanging | The same hole, empty. The swing's rope comes out of it and runs to the bottom of the menu bar, where it meets the ropes on the panel. |

- Size: 26 pt wide, about 19 pt tall. That's close to the most a 24 pt menu bar allows.
- The rope's width follows Snuffler's size setting.
- The icon swaps to "hanging" the moment he drops, and back to "resting" when the page reports he has climbed.

## How the app talks to the creature

The creature is one HTML file. Swift calls into it and listens for messages.

**Calls into the page** (`window.hangabout`):

| Call | What it does |
|---|---|
| `show("needs" or "failed", label)` | Drops in, swings, then hangs. `label` is the accessible name. |
| `nudge(1 or 2)` | Level 1: a settling swing. Level 2: a bigger swing and a kick. |
| `climb()` | Climbs out of sight, then sends `climbed`. |
| `hide()` | Hides at once. |
| `setReducedMotion(true or false)` | Turns all motion off. |
| `setIdle(true or false)` | Idle life on or off. Off by default. |
| `turn(angle)` | Angle in radians. Negative faces left, 0 faces you, positive faces right. Limits: ±1.45. Rest is 0.95. |
| `setZoom(zoom)` | The web view's page zoom, so the page doesn't draw more pixels than are shown. |

**Messages from the page** (to the `hangabout` message handler):

| Message | Meaning |
|---|---|
| `{type: "ready"}` | The page has loaded. Queue calls until this arrives. |
| `{type: "shown"}` | He has landed. |
| `{type: "clicked"}` | He was clicked (not dragged). |
| `{type: "climbed"}` | He's out of sight. Remove the panel and swap the icon back. |
| `{type: "error", message}` | WebGL or the shader failed. Log it. |

## Sizes

- The page is designed at 270×262 px and scaled with the web view's page zoom.
- Default: **35%**, which is 95×92 pt. Debug › Size offers 25%, 35%, 50%, 70% and 100%, saved between launches.
- The panel sits centred under the icon, with its top edge flush with the bottom of the menu bar.

## Files

| File | What it is |
|---|---|
| `app-assets/snuffler-hanging.html` | The creature. The source of truth. |
| `app/Resources/snuffler-hanging.html` | A copy, bundled into the app. Keep the two identical. |
| `app/Sources/Hangabouts/MenuBarIcon.swift` | Draws both icon states. |
| `app/Sources/Hangabouts/CreatureController.swift` | Owns the panel and web view, calls the page, swaps the icon. |
| `app/Sources/Hangabouts/CreaturePanel.swift` | The floating, non-activating panel. Holds the page size. |
| `design/snuffler-explore.html` | Three early directions next to the old Snuffler. |
| `design/snuffler-profile.html` | The chosen direction as a detailed flat drawing. |
| `design/snuffler-3d.html` | The flat drawing with 3D-style shading. |
| `design/snuffler-real3d.html` | The first real 3D model. Older than the app: no swing, less round. |

## How we got here

1. Three directions were sketched: a tidied version, a mole, and a side-on Snuffler. The side-on one won: the snout becomes the silhouette.
2. It was drawn in detail, with follow-through motion.
3. The icon was linked to the drop, so he comes out of it.
4. He was shaded to look 3D, then rebuilt as a real 3D model so he could turn.
5. He was hung from a swing, his arm was straightened, and he was made rounder.
6. The icon became a hole in both states, and was made bigger.

## Checks (manual)

Run the app, then Debug › Simulate Needs you.

| ID | Step | Pass when |
|---|---|---|
| C1 | Launch | The hole icon shows, with eyes and nose in it. Readable at a glance. |
| C2 | Simulate Needs you | He drops, spins in, swings, and comes to rest facing right. |
| C3 | Look at the icon while he hangs | The hole is empty. The rope lines up with the ropes on the panel. |
| C4 | Debug › Size, each option | He scales. The rope still lines up. |
| C5 | Drag him left and right | He turns smoothly. The sign keeps facing you. |
| C6 | Click him without dragging | A `clicked` line appears in the log. |
| C7 | Clear all | He climbs out. The eyes and nose return to the icon. |
| C8 | Type in another app while he drops | Typing isn't interrupted. |
| C9 | Dark menu bar or dark wallpaper | The hole and Snuffler both stay readable. |
| C10 | Idle life on, leave him 1 minute | He blinks and sniffs. CPU stays low. |
| C11 | Idle life off, leave him 1 minute | Completely still. CPU near zero. |

## Not in this spec

- The Failed pose in the app. The model supports it; the menu item arrives in Spec 002's M5.
- Busy and Done poses on screen.
- More species.
- Fixing click-blocking in the transparent area.
