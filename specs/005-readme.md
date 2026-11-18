# Spec 005: The README

**Status:** In progress. README rewritten. Checks R2 and R3 (clean-clone run steps) not yet run by Mark.
**Owner:** Mark (product), Claude Code (writing)
**Depends on:** Nothing. It describes Specs 001 to 004, it doesn't change them.
**Scope:** `README.md` at the repo root only.

## Problems with the README today

- **The status table is wrong.** It says Spec 002 is "Ready to build". M1 to M3 are merged and M4 is in progress on `spec-002-m4`.
- **Specs 003 and 004 are missing.** The character redesign and the motion, fur and burrow work aren't mentioned anywhere.
- **You can't run the app from it.** The only run steps are for Spec 001. The app's build steps live in Spec 002.
- **The first line points at a finished job.** "Read KICKOFF.md and follow it" is the M1 brief. M1 is done.
- **The repo layout is out of date.** `app/` is listed as "to be built". `specs/` is described as "test specs", but three of the four are build or design specs.
- **The core idea may no longer match the creature.** It says "swings 2–3 times, then hangs still". Spec 004's physics swing settles in 4 to 5 seconds, and the arm swap is an open decision.
- **Privacy covers only the listener.** The app also runs a hook server, on port 7788.
- **No requirements.** It doesn't say macOS only, which macOS version, or which toolchains you need.

## Risks and open questions

| Risk | Why it matters | Where it stands |
|---|---|---|
| **It goes stale again** | Status is written in the README, in each spec header and in `CLAUDE.md`. Three copies drift. Spec 002's own header still says "Ready to build". | The README keeps one short state per spec and links to the spec. Detail stays in the spec. See "Keeping it current". |
| **Two audiences** | Mark needs run steps. A newcomer needs to know what this is. A long README serves neither. | Idea first, then run steps, then everything else as links. Budget below. |
| **Promises the product can't keep yet** | The core idea reads like a shipped product. This is a test build with one species. | Say "test build" in the opening lines. Keep the status table near the top. |
| **Who is the reader?** | A private repo needs less explaining than a public one. | **Mark to decide.** This spec assumes private: Mark, plus Claude Code sessions. |
| **The name** | "Hangabouts" is a working name. `package.json` still says `agent-bestiary`. | Keep the "(Working name.)" line. Renaming the package is not in this spec. |
| **Motion wording** | The README can't say "2–3 swings" until Spec 004's damping and arm swap are decided. | Describe the behaviour without numbers: "drops down, swings, then hangs holding a sign". **Mark to confirm.** |
| **Has Spec 001 been run?** | `results/` holds only the template. The status table needs the true state. | **Mark to confirm** before the rewrite. |

## Who reads it

- **Mark, coming back after a break.** Wants: where things stand, and how to run the app.
- **A Claude Code session.** Reads it first because `CLAUDE.md` says to. Wants: what the project is and where the specs are.
- **A newcomer** (only if the repo goes public). Wants: what it is, in ten seconds.

## Sections, in order

| # | Section | What it holds | Limit |
|---|---|---|---|
| 1 | Title and pitch | Name, "(Working name.)", what it is, that it's a macOS test build with one species | 4 lines |
| 2 | The core idea | The four states and the "motion matches urgency" rule | Keep today's text, minus the swing count |
| 3 | Status | One row per spec, 001 to 005: what it is, state, link | One line per row |
| 4 | Requirements | macOS only. Minimum macOS version from `app/Package.swift`. Swift toolchain. Node 18+. Claude Code. | 5 bullets |
| 5 | Run the app | Build, open, start Claude Code in `sandbox-002`. Where the Debug menu is. | One code block, under 10 lines |
| 6 | Run Spec 001 | Today's steps, unchanged | As today |
| 7 | Repo layout | Every top-level folder, one line each | As today, corrected |
| 8 | Privacy | Both servers, both ports, `logs/` | 4 bullets |

Dropped:

- The "Building the app?" line. Replace it with a pointer to `CLAUDE.md` for Claude Code sessions.

## Rules for the content

- Follow the repo's writing style: short sentences, bullets.
- Under 120 lines. Today's is 62.
- No detail that a spec already owns. Link to it. That covers events, states, milestones, acceptance tests and character design.
- Every command must run as written from the stated folder.
- Both ports named: 7777 (listener, Spec 001) and 7788 (app, Spec 002).
- State that both servers bind to `127.0.0.1` only.
- State that the app answers every hook with `{}` and never approves or denies a prompt.
- No screenshots or GIFs yet. The creature is still changing. Revisit when Spec 004 closes.
- No badges, no licence section, no contributing section while the repo is private.

## Status table: allowed states

One of these per spec, nothing longer:

- Draft
- Ready to run / Ready to build
- In progress (with the milestone, such as "M4 of 5")
- Done
- Waiting on a decision

## Keeping it current

- The spec header is the source of truth for a spec's state.
- When a milestone merges, update the spec header and the README row in the same pull request.
- `CLAUDE.md`'s "Current phase" section is updated in that pull request too.

## Checks (manual)

| # | Check | Pass |
|---|---|---|
| R1 | Read only the top 10 lines | You can say what Hangabouts is and that it's a test build |
| R2 | Follow "Run the app" on a clean clone | The burrow icon shows in the menu bar with no extra steps |
| R3 | Follow "Run Spec 001" on a clean clone | The listener starts and logs a tagged scenario |
| R4 | Compare each status row to its spec header | They agree |
| R5 | Compare the repo layout to `ls` at the root | Every folder is listed, none are extra |
| R6 | Click every link | None are broken |
| R7 | Count lines | Under 120 |
| R8 | Search for "to be built" and "KICKOFF" | No stale pointers |

## Not in this spec

- Fixing the stale status lines inside Specs 001 to 004. Do it alongside, but it's a separate change.
- `design/README.md`. Its state names (Digging, Delivering) are also old.
- Retiring `KICKOFF.md` and `KICKOFF-M2.md`.
- Renaming the package in `package.json`.
- A public landing page, screenshots or a demo video.
