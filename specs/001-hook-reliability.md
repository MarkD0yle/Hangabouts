# Spec 001: Can Claude Code hooks drive the creatures?

**Status:** Ready to run
**Owner:** Mark
**Time needed:** About 60 minutes

## Why this test exists

The whole product depends on one thing. When an agent needs you, the creature must know within a second or two. If hooks miss that moment, the creature is just decoration.

The riskiest part: Claude Code only sends `Notification` events when you *appear to be away* from the terminal. We don't know exactly what "away" means. A terminal on a second monitor might count as "not away," and then Snuffler would never drop down.

## Questions this test answers

1. **Needs you:** Does `Notification` (`permission_prompt`) fire in each focus situation?
2. **Fallback:** Does `PermissionRequest` fire every time a permission prompt appears, whatever the focus? If yes, it can replace `Notification` for the "needs you" state.
3. **Idle:** How long after `Stop` does `idle_prompt` arrive?
4. **Done:** Does `Stop` fire after every turn?
5. **Busy:** Do `PreToolUse` and `PostToolUse` fire on every tool call?
6. **Helpers:** Do `SubagentStart` and `SubagentStop` fire?
7. **Routing:** Does every event carry enough data (such as `session_id` and `cwd`) to send it to the right creature?
8. **Speed:** Does the event reach the listener about as soon as the prompt appears on screen? Target: within about 1 second, judged by eye in A1. The listener prints each event live.

## Setup

1. Node 18 or later. No packages to install.
2. Terminal A, at the repo root: `npm run listen`
3. Terminal B: `cd sandbox && claude`
   - `sandbox/.claude/settings.json` sends every hook event to the listener.
   - The hooks only apply inside `sandbox/`. Your other projects are untouched.
4. Keep Claude Code's permission mode at **default**, so permission prompts appear.
5. Optional: a second monitor for scenario A3.

## How to run a scenario

1. Tag the run: `npm run mark -- A2` (in terminal A or any other).
2. Set up the focus situation the scenario describes.
3. Paste the scenario's prompt into the sandbox Claude session.
4. Act as the scenario says, then answer the prompt.
5. Write anything odd in `results/run-<date>.md`.

Run each scenario **3 times**. One run proves nothing about reliability.

## Scenarios

### A. Needs you: permission prompts

Prompt for every A scenario:

> Run `date` in the shell and tell me the time.

`date` is not pre-approved, so Claude Code must ask permission.

| ID | Focus situation | Expected `Notification` | Expected `PermissionRequest` |
|---|---|---|---|
| A1 | Terminal B focused, you watch it | Maybe not (you're "present") | Yes |
| A2 | Switch to another app within 2 seconds of sending, same screen | Yes | Yes |
| A3 | Terminal B visible on a second monitor, another app focused | **Unknown: the key question** | Yes |
| A4 | Terminal B minimised | Yes | Yes |
| A5 | Switch away, wait 2 minutes, then come back | Yes, check the delay | Yes |

### B. Idle: Claude is waiting for you

Prompt:

> Ask me one question about my favourite colour, then wait for my answer.

| ID | Focus situation | Expected |
|---|---|---|
| B1 | Stay focused on terminal B | `Stop`. `idle_prompt` maybe not |
| B2 | Switch away right after sending, wait 3 minutes | `Stop`, then `idle_prompt` later. Record the gap |

### C. Done

Prompt:

> Say hello in five languages.

| ID | Focus situation | Expected |
|---|---|---|
| C1 | Focused | `Stop` |
| C2 | Switched away | `Stop`, plus maybe `Notification` |

### D. Busy

Prompt (approve each tool when asked):

> Read README.md in this folder, then list the files here.

| ID | Expected |
|---|---|
| D1 | One `PreToolUse` and one `PostToolUse` per tool call, in order |

### E. Helpers

Prompt:

> Use a subagent to count the words in README.md, then report back.

| ID | Expected |
|---|---|
| E1 | `SubagentStart`, then `SubagentStop`, then `Stop` |

### F. Failure (only if it happens)

`StopFailure` fires on API errors such as rate limits. We can't trigger it on demand. If one shows up in the log during any run, note which run.

### G. Two sessions at once

Open a second sandbox session in terminal C (`cd sandbox && claude`). Give both the A prompt.

| ID | Expected |
|---|---|
| G1 | Two `PermissionRequest` events with **different** `session_id` values |

## Pass criteria

| Result | Decision |
|---|---|
| `PermissionRequest` fires in A1 to A5, 3 of 3 runs each | **Go.** Use it for "needs you." |
| Only `Notification` is reliable, and A3 fails | **Go with a caveat.** Document "second monitor counts as present." |
| Neither fires reliably in A2 and A4 | **Stop.** Look at the terminal status protocol (OSC 7501) instead. |
| `Stop` fires in every B, C and D run | Required for "done." |
| Every event has `session_id` and `cwd` | Required for routing to the right creature. |
| In A1, the event shows in the listener within about 1 second of the prompt appearing | Required. |

## Analysing the results

1. `npm run analyze` prints, for each scenario:
   - which events arrived, in order
   - the gap between `Stop` and `idle_prompt`
   - which payload fields each event type carries
   - which app was in front when each event arrived
2. Copy the output into `results/run-<date>.md` using `results/TEMPLATE.md`.
3. Fill in the decision table.

## Out of scope

- Answering prompts from the creature card. `Notification` has no decision control. That's version 2.
- Any animation or UI.
- The Claude app's background tasks. There is no public event feed for them that we know of.

## Risks to the test itself

- **The listener isn't running.** Hooks fail quietly. Always start `npm run listen` first.
- **Over-approving.** If you choose "always allow" for `date`, later A runs won't prompt. Pick "yes, once" every time. If you slip, remove the rule with `/permissions`.
- **"Away" may use a timer, not focus.** A5 is there to catch that.
