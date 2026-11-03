---
description: "Time-boxed auto-approve: stop permission prompts for a while."
argument-hint: "<duration> [session|global] [full] | off | status"
disable-model-invocation: true
---
Time-boxed auto-approve — stop the yes/no prompts for a while. Arguments: $ARGUMENTS (<duration> [session|global] [full] | off | status)

While autopilot is on, Supercharger auto-approves **every** permission request so you're not prompted. It only removes the yes/no friction — the safety hooks still run, so dangerous commands (`rm -rf`, force-push, credential leaks, `curl|bash`, self-modification) stay blocked. Your own `permissions.deny` and `permissions.ask` rules are also honoured — autopilot never auto-approves a call they cover. It **auto-expires** after the duration you give it, up to a **ceiling of 8 hours** (a full workday, so it can't be left on forever). Ask for more than the ceiling and it's clamped to the ceiling with a loud notice — never silently. Raise or lower the ceiling with `SUPERCHARGER_AUTOPILOT_MAX_HOURS=<hours>`.

**Scope (default is per-session):**
- **`session`** (default) — only **this** Claude session auto-approves; other sessions are unaffected.
- **`global`** — every session on the machine auto-approves.

**`full`** — also approve the confirms Supercharger's own guards raise (force push to a feature branch, `.env` overwrite, CI and lockfile edits, kill by name, push to another host). It still asks before payments, turning Supercharger or a guard off, autopilot renewing itself, and leaving the sandbox. Hard blocks stay blocked.

**Run it** (pass the argument straight through; default to `status` if none given):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/autopilot.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- `/supercharger:autopilot 30m` — auto-approve for 30 minutes in **this session only**. Accepts `30m`, `2h`, `90s`, or a bare number (minutes).
- `/supercharger:autopilot 30m global` — auto-approve for **all** sessions on the machine.
- `/supercharger:autopilot 2h full` — also approve guard confirms (see `full` above). Order is free: `2h global full` works.
- `/supercharger:autopilot off` — turn it off now (clears both this session's and the global window); normal prompts return.
- `/supercharger:autopilot status` — show whether it's on (per-session and/or global) and how long is left.

Notes to surface to the user:
- This does **not** disable any safety guard — only the permission prompts. `rm -rf`, force-push, credential leaks, etc. are still blocked by the PreToolUse hooks.
- It ends automatically at the deadline (checked on each request — no background timer). The statusline shows a `⚡ Autopilot: Nm left` indicator while it's active.
- Different from `/sc off`, which disables **all** Supercharger guards (no safety floor). Autopilot keeps the safety floor.
