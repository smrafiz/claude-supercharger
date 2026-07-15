Time-boxed auto-approve — stop the yes/no prompts for a while. Arguments: $ARGUMENTS (<duration> | off | status)

While autopilot is on, Supercharger auto-approves **every** permission request so you're not prompted. It only removes the yes/no friction — the safety hooks still run, so dangerous commands (`rm -rf`, force-push, credential leaks, `curl|bash`, self-modification) stay blocked. It **auto-expires** after the duration and is hard-capped at **2 hours**.

**Run it** (pass the argument straight through; default to `status` if none given):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/autopilot.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- `/sc-autopilot 30m` — auto-approve all prompts for 30 minutes. Accepts `30m`, `2h`, `90s`, or a bare number (minutes).
- `/sc-autopilot off` — turn it off now; normal prompts return.
- `/sc-autopilot status` — show whether it's on and how long is left.

Notes to surface to the user:
- This does **not** disable any safety guard — only the permission prompts. `rm -rf`, force-push, credential leaks, etc. are still blocked by the PreToolUse hooks.
- It ends automatically at the deadline (checked on each request — no background timer). The statusline shows a `⚡ Autopilot` indicator with the time left while it's active.
- Different from `/sc off`, which disables **all** Supercharger guards (no safety floor). Autopilot keeps the safety floor.
