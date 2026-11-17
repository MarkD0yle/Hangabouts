# Hangabouts

*(Working name.)*

**Building the app?** Open Claude Code at the repo root and say: "Read KICKOFF.md and follow it."

Odd little creatures that show what your AI agents are doing.

Each agent type gets its own species. A creature's behaviour *is* the agent's status, so you can read it at a glance without opening a terminal. The first species is **Snuffler**, a research agent that lives in the macOS menu bar and only comes down when it needs you.

## The core idea

- **Busy:** the creature stays quiet in the menu bar.
- **Needs you:** it drops down, swings 2–3 times, then hangs still holding a sign.
- **Done:** a badge on its menu bar icon. Finished work waits for you.
- **Failed:** it looks sheepish and gives a one-line reason. Serious errors get a plain system alert instead.

The rule: motion matches urgency. Only "needs you" and "failed" are allowed to pull your eye.

## Status

| Phase | What | State |
|---|---|---|
| 0 | Character design: Snuffler, 5 states | Done (design canvas) |
| 1 | **Spec 001:** can Claude Code hooks drive the creatures reliably? | **Ready to run** |
| 2 | **Spec 002:** test Hangabout, a macOS menu bar app with Snuffler | **Ready to build** (listens to both candidate events) |
| 3 | Answer prompts from the creature's card | Later |

## Repo layout

```
specs/      Test specs. Start with 001-hook-reliability.md
harness/    Local listener, scenario tagger and analyser (Node 18+, no packages)
sandbox/    Spec 001: throwaway Claude Code project, hooks post to the listener on :7777
sandbox-002/ Spec 002: throwaway Claude Code project, hooks post to the app on :7788
app-assets/ Snuffler creature (HTML/SVG/CSS with a JS API) and menu bar icons
app/        Spec 002: the macOS test app (to be built)
results/    Results from each test run
design/     Character notes and links to design files
```

## Run Spec 001

```bash
# Terminal A, repo root
npm run listen

# Terminal B
cd sandbox && claude

# Before each scenario
npm run mark -- A2

# When you're done
npm run analyze > results/run-$(date +%F).md
```

Full steps, scenarios and pass criteria are in [`specs/001-hook-reliability.md`](specs/001-hook-reliability.md).

## Privacy

- The listener binds to `127.0.0.1` only. Nothing leaves your machine.
- Hook payloads include file paths and tool inputs. `logs/` is git-ignored. Don't commit it.
