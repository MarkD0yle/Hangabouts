# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this project is

Agent Bestiary: animated creatures in the macOS menu bar that show the status of AI agents. Read `README.md` first.

## Current phase

Spec 001 (`specs/001-hook-reliability.md`). It tests whether Claude Code hook events are reliable enough to drive the creatures. No app code until that spec has a Go decision in `results/`.

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
- The listener must only bind to `127.0.0.1`.
- When the listener answers a hook, it returns `{}`. Never return a decision. For `PermissionRequest` that would approve or deny prompts and spoil the test.

## Writing style for docs in this repo

Short sentences. Bullet points. Lead with problems and risks, then the plan.
