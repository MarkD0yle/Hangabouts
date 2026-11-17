# Sandbox

A throwaway Claude Code project for Spec 001.

Its `.claude/settings.json` sends every hook event to the local listener at `http://127.0.0.1:7777`. Those hooks only apply when you run `claude` inside this folder.

If the listener isn't running, Claude Code shows a non-blocking hook error and carries on as normal.

This file is also something for the test prompts to read and count.
