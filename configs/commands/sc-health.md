---
description: "Check that the install is healthy and the core guards actually stop a known-bad call."
allowed-tools: Bash(python3 ~/.claude/supercharger/tools/command-context.py:*)
---
Show the Supercharger health check.

**The report** (run when this command loaded):

```
!`python3 ~/.claude/supercharger/tools/command-context.py health`
```

Present the score table as-is. The Security line is behavioural: each core guard
(safety, git-safety, path-guard, harness-tamper-guard) was run through the command
`settings.json` registers, on a call it must stop. A ✗ there means that guard is
not protecting this install, whatever the other lines say. Every other registered
Supercharger PreToolUse hook is also run once on a harmless call, to prove it starts.

For each issue listed, give one line on the fix:
- "matcher does not select …" → the hook is registered for the wrong tools; re-run the installer (`/sc-update`).
- "let it through" → the registered command does not run the guard; re-run the installer.
- "not registered" → the guard was removed from settings.json or disabled; check `/sc-status` for disabled hooks.
- "hook X does not run … (not executable / not found / exit N)" → that guard is registered but cannot run, so Claude Code lets every call through it. Re-run the installer (`/sc-update`); if it persists, report it as a bug.

If everything passes, say so in one line.
