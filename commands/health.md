---
description: "Check that the install is healthy and the core guards actually stop a known-bad call."
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/tools/command-context.py:*)
---
Show the Supercharger health check.

**The report** (run when this command loaded):

```
!`python3 ${CLAUDE_PLUGIN_ROOT}/tools/command-context.py health`
```

Present the score table as-is. The Security line is behavioural: each core guard
(safety, git-safety, path-guard, harness-tamper-guard) was run through the command
`settings.json` registers, on a call it must stop. A ✗ there means that guard is
not protecting this install, whatever the other lines say.

For each issue listed, give one line on the fix:
- "matcher does not select …" → the hook is registered for the wrong tools; re-run the installer (`/supercharger:update`).
- "let it through" → the registered command does not run the guard; re-run the installer.
- "not registered" → the guard was removed from settings.json or disabled; check `/supercharger:status` for disabled hooks.

If everything passes, say so in one line.
