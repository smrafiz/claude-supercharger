Read-only mode — "look, don't touch" for a while. Arguments: $ARGUMENTS (<duration> [session|global] | off | status)

The inverse of `/sc-autopilot`: while read-only mode is on, Supercharger **blocks every file edit** (Write/Edit/MultiEdit/NotebookEdit) and **every mutating shell command** (`rm`, `mv`, `git commit/push`, `npm install`, `sed -i`, redirects that write a file, …). Reads, searches, and planning stay allowed. Great for exploring or reviewing a codebase without any risk of accidental changes. It **auto-expires** and is hard-capped at **2 hours**.

**Scope (default is per-session):**
- **`session`** (default) — only **this** Claude session is read-only.
- **`global`** — every session on the machine is read-only.

**Run it** (pass the argument straight through; default to `status` if none given):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/readonly.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- `/sc-readonly 20m` — read-only for 20 minutes in **this session only**. Accepts `20m`, `2h`, `90s`, or a bare number (minutes).
- `/sc-readonly 20m global` — read-only for **all** sessions on the machine.
- `/sc-readonly off` — turn it off now; edits are allowed again.
- `/sc-readonly status` — show whether it's on (per-session and/or global) and how long is left.

Notes to surface to the user:
- This is a **workflow guard** ("don't touch"), not a security sandbox — precise for the editor tools, best-effort for Bash. The always-on safety hooks (`rm -rf`, force-push, credential leaks) are the real floor and stay active either way.
- It ends automatically at the deadline (checked on each tool call — no background timer). The statusline shows a `⚡ Read-only: Nm left` indicator while it's active.
- Interacts cleanly with autopilot: read-only **wins** — a blocked edit is blocked even if autopilot would have auto-approved it (tighten beats loosen).
