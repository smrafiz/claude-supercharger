---
description: "Strict mode: ask before every action for a while."
argument-hint: "<duration> [session|global] | off | status"
disable-model-invocation: true
---
Strict mode — "ask me everything" for a while. Arguments: $ARGUMENTS (<duration> [session|global] | off | status)

While strict mode is on, Supercharger **auto-approves nothing** — every tool call falls through to Claude Code's normal permission prompt, including the read-only calls it would usually wave through. Use it near a deploy, on production config, or any time you want to eyeball each step. It **overrides `/supercharger:autopilot`** while active. It **auto-expires** and is hard-capped at **2 hours**.

Strict does not *add* blocks — the always-on safety hooks already do that. It only removes auto-approvals, so you're asked to confirm more.

**Scope (default is per-session):**
- **`session`** (default) — only **this** Claude session is strict.
- **`global`** — every session on the machine is strict.

**Run it** (pass the argument straight through; default to `status` if none given):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/strict.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- `/supercharger:strict 30m` — confirm every call for 30 minutes in **this session only**. Accepts `30m`, `2h`, `90s`, or a bare number (minutes).
- `/supercharger:strict 30m global` — strict for **all** sessions on the machine.
- `/supercharger:strict off` — turn it off now; normal auto-approvals return.
- `/supercharger:strict status` — show whether it's on (per-session and/or global) and how long is left.

Notes to surface to the user:
- It ends automatically at the deadline (checked on each tool call — no background timer). The statusline shows a `🛡 Strict: Nm left` indicator while it's active.
- Part of the time-boxed **modes** family: `/supercharger:autopilot` loosens (skip prompts), `/supercharger:readonly` and `/supercharger:strict` tighten. Strict overrides autopilot; read-only (a hard block on edits) beats both.
