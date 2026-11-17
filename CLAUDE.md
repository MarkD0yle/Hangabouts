# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this project is

Hangabouts (codename agent-bestiary): animated creatures in the macOS menu bar that show the status of AI agents. Read `README.md` first.

## Current phase

Two specs run in parallel:

- **Spec 001** (`specs/001-hook-reliability.md`): tests whether Claude Code hook events are reliable. The human runs it.
- **Spec 002** (`specs/002-test-hangabout.md`): build the test app in `app/`. You build it, milestone by milestone (M1 to M5). Stop after each milestone so the human can run it.

When building Spec 002:
- Read the whole spec first, then `app-assets/snuffler-hanging.html` for the creature's JS API.
- Copy assets from `app-assets/` into `app/Resources/`. Don't edit the creature's look; that's a design change.
- No third-party dependencies.
- The human runs the app on macOS; you may be on another platform. Make sure `scripts/bundle.sh` gives clear errors.

## How the test is split

- **The human runs the scenarios.** Most of them depend on window focus (switching apps, minimising, second monitor). You can't do that from here.
- **You can help with:**
  - starting the listener: `npm run listen`
  - tagging scenarios: `npm run mark -- <id>`
  - analysing: `npm run analyze`
  - writing `results/run-<date>.md` from the analysis, using `results/TEMPLATE.md`
  - proposing the Go / Stop decision against the spec's pass criteria

## Rules

- Don't edit `sandbox/.claude/settings.json` during a test run. It changes what's being measured.
- Never commit `logs/`. Hook payloads contain paths and tool inputs.
- Keep the harness dependency-free (Node 18+ built-ins only).
- The listener and the app's hook server must only bind to `127.0.0.1`.
- When the listener or the app answers a hook, it returns `{}`. Never return a decision. For `PermissionRequest` that would approve or deny prompts and spoil the test.

## Writing style for docs in this repo

Short sentences. Bullet points. Lead with problems and risks, then the plan.
