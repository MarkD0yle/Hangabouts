# Spec 004: Snuffler's motion, fur and burrow

**Status:** Part done. The creature page, the messy burrow, the rope and the debug menu are built and ready to test. The blinking icon (change 7) waits on a decision.
**Owner:** Mark (product and design), Claude Code (build)
**Depends on:** Spec 003. The events, states, hook server and card are unchanged.
**Where it came from:** Mark's review of Snuffler on a Claude Design canvas ("Snuffler — Hangabouts character"). Each change below matches a comment from that review.
**Written to stand alone.** It can be added to a Claude project as background without the rest of the repo.

## What changes, in one table

| # | Change | Where | State |
|---|---|---|---|
| 1 | Shorter hanging arm | Creature page (shader) | Done |
| 2 | Physics swing, driven by his body | Creature page (JS + shader) | Done |
| 3 | Arm swap when tired | Creature page (JS + shader) | Done, **off by default** |
| 4 | Fur | Creature page (shader) | Done |
| 5 | Messy burrow | `MenuBarIcon.swift` | Done |
| 6 | Rope that looks like rope | `MenuBarIcon.swift` | Done |
| 7 | Blinking burrow icon | `MenuBarIcon.swift` + `CreatureController.swift` | **To build**, open question |

The two copies of the creature, `app-assets/snuffler-hanging.html` and `app/Resources/snuffler-hanging.html`, are still identical.

## Risks and open questions

Read these before building.

| Risk | Why it matters | Where it stands |
|---|---|---|
| **Moves for longer** | Spec 002 says 2–3 swings, then still. The physics swing settles in about 4–5 s after a drop. | Tune with the damping (`1.6` in `step()`). A higher number stops him sooner. **Mark to decide.** |
| **Arm swap breaks "completely still"** | A swap every 9 s means he's never still. It costs CPU and pulls your eye when nothing is new. | Off by default. `setTired(true)` turns it on. Better idea: swap only once you've left him waiting 2+ minutes, so his tiredness shows how long he's waited. **Mark to decide.** |
| **Blinking icon draws the eye** | A blink every few seconds is movement in the menu bar when no agent needs you. It weakens "he moved, so I'm needed". | Not built. Options in change 7. **Mark to decide.** |
| **Fur costs more to draw** | About 4 extra noise lookups per pixel, plus extra work at his outline. | Only while he moves. Measure CPU with check C10 / C11 from Spec 003. |
| **Fur is lost at 35%** | Strands are about 1 px wide at the default size. They read as a soft texture, not hairs. | Accepted. Clear strands only show at 70–100%. |
| **Body doesn't hang under the gripping hand** | A real one-handed hang would tilt the bar about 35° and pull him under that hand. | Left out on purpose: it looks broken and knocks the swing out of line with the icon's rope. |
| **Leg direction worked out, not seen** | The legs should trail the swing. At some turn angles they may lead instead. | If they look wrong, flip the sign of `legs` in `frame()`. |
| **Memory** | Spec 003 already measured 66–82 MB, over budget. | These changes add no textures or libraries. Not measured. |

## 1. Shorter hanging arm

- His body sits 0.25 units (about 20 px at 100%) closer to the bar. His fist stays on the bar.
- One constant controls it: `ARM = .25` in the shader. A higher number gives a shorter arm. Above about 0.3, his fist touches his ear.
- The ropes and bar don't move, so they still meet the icon's rope.

## 2. Physics swing, driven by his body

The old swing was a fixed fading wave. Now it's a chain of springs, each lagging behind the one above it:

| Part | What it is | Rhythm |
|---|---|---|
| Swing | A pendulum from the top point | About 1.1 s a swing |
| Body | Hangs off the gripping hand. Swung by the swing speeding up or slowing down. | About 0.85 s |
| Legs | Hang off the body. Trail behind it. | About 0.5 s |
| Sign | Hangs off his nose. | About 0.6 s |
| Tail | Follows the sign, the other way. | (no spring of its own) |

**Moments:**

| Moment | What happens now |
|---|---|
| Drop | Unchanged until landing. On landing, the swing takes his weight; his body and legs carry on, then jolt and settle. |
| Nudge 1 | A push on the swing (about 10°). Body, legs and sign follow behind it. |
| Nudge 2 | **He pumps the swing himself** for 2.6 s. His legs kick forward and his body leans back in time with it, building up to about 12°. Then it settles. Replaces "bigger swing plus a leg kick". |
| Reduced motion | No movement. Unchanged. |

He stops drawing once everything is still, as before. "Still" now means everything has nearly stopped moving, not that a timer has run out.

## 3. Arm swap when tired (off by default)

- Every 9 s he grabs the bar with his free hand, hangs by both for a moment, lets go with the tired arm, swings a little, and shakes that hand out.
- While swapping, his eyelids get heavy and his ears droop. Then he recovers.
- His body sways onto the new hand as the old one lets go.
- **New page calls:**

| Call | What it does |
|---|---|
| `setTired(true or false)` | Swaps arms every 9 s while he hangs. Off by default. |
| `swapArms()` | One swap now. For a debug menu item. |

## 4. Fur

- Light and dark strands that run downward and move with him.
- Each strand catches the light a little differently, so he isn't smooth plastic.
- His outline breaks into strands, with a few stray hairs just past it.
- Fur only: the eyes, nose, monocle, satchel, sign, rope and bar stay smooth.

## 5. Messy burrow (done)

Reference drawings: `design/burrow-icon-resting.svg` and `design/burrow-icon-hanging.svg`. They use the same 100×100 grid as `MenuBarIcon.swift`, so the numbers carry straight across.

- The mound, the rim and the opening are lumpy, not ovals. Copy the path points from the SVGs into `NSBezierPath` (move to the first point, line to the rest, close).
- The opening is a little less lumpy than the mound, so his eyes and snout still sit cleanly in it.
- More loose soil: two outlined clods at the sides, four crumbs, two grey pebbles. Positions and colours are in the SVGs.
- The tiny crumbs are under 1 px at real size. If they blur into a halo, drop them and keep the two clods.

## 6. Rope that looks like rope (done)

The old rope was a flat bar with vertical stripes. Now:

- **Twist:** diagonal bands at -38°, `#CCA86B` and `#8F6C3A`, repeating every 0.7 × the rope width. Same colours as the rope on the panel.
- **Roundness:** light on the left (`#FFF4DC` at 35%) and dark on the right (`#2B1A0C` at 45%).
- **Edges:** a thin `#4A2F1A` line down each side, 0.12 × the rope width (at least 0.9 grid units).
- Drawn as clipped diagonal bands in Swift.
- The rope is clipped to "inside the opening or outside the mound", so it comes out of the hole. The old code redrew the front lip over it, which left a faint seam at y = 58.

## 7. Blinking burrow icon (to build, open question)

What the canvas does: the resting icon blinks every 4.5 s, for about 0.16 s.

- **Blink frame:** eye heights 9.5 → 0.9 and 6.5 → 0.7; pupil heights 5 → 0.3 and 3.4 → 0.2. Same centres and widths.
- **In Swift:** add `MenuBarIcon.restingBlink(barHeight:)`. In `CreatureController`, a timer swaps the status item's image to the blink frame and back. Only while resting. Stop the timer while he hangs.
- **Pick one before building:**
  - (a) Every 4.5 s, like the canvas.
  - (b) Every 20–30 s, rare enough not to draw the eye.
  - (c) Only while an agent is working, so a blink means "busy" and the drop means "needs you". This fits Hangabouts best.

## Debug menu additions (done)

| Item | Calls |
|---|---|
| Debug › Pump | `hangabout.nudge(2)` |
| Debug › Swap arms | `hangabout.swapArms()` |
| Debug › Tired | `hangabout.setTired(true/false)`, saved between launches like Idle life |

## Checks (manual)

Run the app, then Debug › Simulate Needs you. Spec 003's checks C1–C11 still apply.

| ID | Step | Pass when |
|---|---|---|
| D1 | Look at him hanging | His arm is shorter. His fist is on the bar. The ropes still meet the icon's rope. |
| D2 | Simulate Needs you | On landing his body and legs jolt behind the swing, then settle. Still within about 5 s. |
| D3 | Debug › Pump | His legs kick and his body leans in time with the swing. It builds, then settles. |
| D4 | Drag him to turn mid-swing | His legs trail the swing, not lead it, at every turn angle. |
| D5 | Debug › Swap arms | Free hand up, both hold, tired hand lets go and shakes. Lids heavy, ears droop, then recover. |
| D6 | Debug › Tired on, wait 30 s | He swaps about every 9 s. Off: he never swaps. |
| D7 | Look at him at 100% and at 35% | Fur shows as strands at 100% and a soft texture at 35%. His outline is fuzzy, not cut out. |
| D8 | Reduced motion on | No swing, pump, jolt or swap animation. |
| D9 | Leave him still 1 minute, Tired off | CPU near zero (same as C11). |
| D10 | After change 5 | Messy hole readable at 1× on light and dark menu bars. |
| D11 | After change 6 | The rope reads as twisted rope at 1× and at 100%. |

## Not in this spec

- Making Busy and Done show on screen.
- Tilting the swing under a one-handed hang.
- Fixing click-blocking in the transparent area.
