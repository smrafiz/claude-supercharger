Show hook performance timing report. Options: $ARGUMENTS (e.g. --slow, --days 7)

> **Known limitation (v2.4.5):** the timing-emit half of the profiling pipeline is incomplete. `hooks/lib-suppress.sh` captures `HOOK_START_MS` when the `.profiling` sentinel is present, but no hook currently writes `elapsed_ms` to the audit log on exit. This report will always show "No hook timing data found" until that gap is filled. Sentinel toggle is real but not yet useful.

**Step 1 — Run the report**

```bash
bash ~/.claude/supercharger/tools/hook-perf.sh $ARGUMENTS
```

If the command exits with "No hook timing data found", explain the limitation above:
- Profiling pipeline is incomplete — sentinel exists, timing emit does not
- Sentinel commands (will be useful once pipeline lands):
  - `touch ~/.claude/supercharger/scope/.profiling` (start)
  - `rm ~/.claude/supercharger/scope/.profiling` (stop)

**Step 2 — Interpret results**

Present the table as-is. Then add a one-line summary:
- Highlight the slowest hook (highest avg_ms)
- Note if any hook averages >200ms (flag as candidate for SUPERCHARGER_PROFILE=minimal)
- Note total overhead per Claude invocation

**Step 3 — Suggest action (only if data warrants it)**

If total overhead >500ms/call or any hook >200ms avg:
- Suggest `{"profile": "minimal"}` in `.supercharger.json` if the slow hooks are in the minimal skip list
- Otherwise name the specific hook and suggest `disableHooks` if it's safe to skip
