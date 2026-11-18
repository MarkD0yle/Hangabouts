# Hangabouts

*(Working name.)*

Odd little creatures that show what your AI agents are doing.

This is a **test build**: a macOS menu bar app with one species, **Snuffler**, driven by Claude Code hooks. Each agent type will get its own species. A creature's behaviour *is* the agent's status, so you can read it at a glance without opening a terminal.

**Claude Code session?** Read [`CLAUDE.md`](CLAUDE.md) next.

## The core idea

- **Busy:** the creature stays quiet in the menu bar.
- **Needs you:** it drops down, swings, then hangs holding a sign.
- **Done:** a badge on its menu bar icon. Finished work waits for you.
- **Failed:** it looks sheepish and gives a one-line reason. Serious errors get a plain system alert instead.

The rule: motion matches urgency. Only "needs you" and "failed" are allowed to pull your eye.

Built so far: Busy and Needs you. Done and Failed come in Spec 002's last milestone.

## Status

| Spec | What | State |
|---|---|---|
| [001](specs/001-hook-reliability.md) | Can Claude Code hooks drive the creatures reliably? | Ready to run |
| [002](specs/002-test-hangabout.md) | The test app: menu bar icon, hook server, Snuffler, card | In progress (M4 of 5) |
| [003](specs/003-snuffler-character.md) | Snuffler as a 3D character, with a burrow icon | In progress (built, checks not run) |
| [004](specs/004-snuffler-motion-and-fur.md) | Physics swing, fur, messy burrow, rope | Waiting on a decision |
| [005](specs/005-readme.md) | This README | In progress |

Each spec's header holds the detail. Later: answer prompts from the creature's card.

## Requirements

- macOS 14 or later. The app doesn't build anywhere else.
- Swift 5.9 or later. The Xcode Command Line Tools are enough: `xcode-select --install`.
- Node 18 or later, for the Spec 001 harness. No packages to install.
- Claude Code, to send the hook events.
- No third-party dependencies.

## Run the app

```bash
# Terminal A, repo root
./app/scripts/bundle.sh
open app/build/Hangabouts.app

# Terminal B, repo root
cd sandbox-002 && claude
```

- A burrow icon appears in the menu bar. There is no Dock icon.
- Ask Claude Code for something that needs permission. Snuffler drops down.
- No Claude Code to hand? Click the icon, then **Debug › Simulate Needs you**. **Clear all** sends him back up.

Behaviour, milestones and acceptance tests are in [`specs/002-test-hangabout.md`](specs/002-test-hangabout.md).

## Run Spec 001

```bash
# Terminal A, repo root
npm run listen

# Terminal B
cd sandbox && claude

# Before each scenario
npm run mark -- A2

# When you're done: paste the output into a copy of results/TEMPLATE.md
npm run analyze
```

Full steps, scenarios and pass criteria are in [`specs/001-hook-reliability.md`](specs/001-hook-reliability.md).

## Repo layout

```
specs/       Test, build and design specs, 001 to 005
harness/     Spec 001: local listener, scenario tagger and analyser (Node 18+, no packages)
sandbox/     Spec 001: throwaway Claude Code project, hooks post to the listener on :7777
sandbox-002/ Spec 002: throwaway Claude Code project, hooks post to the app on :7788
app/         Spec 002: the macOS test app (Swift package, bundled by scripts/bundle.sh)
app-assets/  Snuffler creature (one HTML page with a JS API) and menu bar icons
design/      Character notes, explorations and links to design files
results/     Results from each test run
```

`KICKOFF.md` and `KICKOFF-M2.md` are the briefs for milestones already built.

## Privacy

- Two local servers: the Spec 001 listener on port 7777 and the app on port 7788. Both bind to `127.0.0.1` only. Nothing leaves your machine.
- Both answer every hook with `{}`. They never approve or deny a prompt.
- Hook payloads include file paths and tool inputs. The listener writes them to `logs/`, which is git-ignored. Don't commit it.
- The app keeps its own event log at `~/Library/Application Support/Hangabouts/events.jsonl`.
