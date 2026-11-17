# Design

## Snuffler (research agent)

- Design canvas: https://claude.ai/artifact/NBAnuVM9QeS96zB8wYyS2U (private)
- Artboards: field guide entry, behaviour sheet (5 states), clickable in-context prototype

## States

| State | Trigger | Motion | Where |
|---|---|---|---|
| Resting | no events | none | menu bar icon |
| Digging | `PreToolUse`, `PostToolUse` | slow sniff, only seen in its menu | menu bar dropdown |
| Dangling | needs you (see Spec 001) | drops, swings 2–3 times, settles | hangs below its icon |
| Delivering | `Stop` | one waddle, then a badge | menu bar badge |
| Sheepish | `StopFailure` | one slow droop | hangs, with a reason |

## Known design problems

- At 24px the menu bar icon reads as a yellow blob. It needs a simpler silhouette made for that size.
- The canvas uses CSS motion. Real character animation needs frame-by-frame work.
- Creatures must hide automatically during screen sharing.
