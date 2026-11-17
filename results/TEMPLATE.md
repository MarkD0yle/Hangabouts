# Spec 001 run: YYYY-MM-DD

## Setup

- Claude Code version (`claude --version`):
- Terminal app:
- macOS version:
- Second monitor used for A3: yes / no
- Runs per scenario:

## Decision

| Question | Answer | Evidence |
|---|---|---|
| Does `PermissionRequest` fire in A1–A5, every run? | | |
| Does `Notification(permission_prompt)` fire in A3 (second monitor)? | | |
| Gap between `Stop` and `idle_prompt` (B2) | | |
| Does `Stop` fire in every B, C and D run? | | |
| D1: one `PreToolUse` and one `PostToolUse` per tool call? | | |
| E1: do `SubagentStart` and `SubagentStop` fire? | | |
| Delay from `PermissionRequest` to `Notification(permission_prompt)` | | |
| Do all events carry `session_id` and `cwd`? | | |
| In A1, did the event show within about 1 second of the prompt? | | |

**Go / Go with caveat / Stop:**

**Event to use for "needs you":**

## Surprises

-

## Analyser output

<!-- paste `npm run analyze` output here -->
