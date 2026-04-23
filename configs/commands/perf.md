Show hook performance timing report. Options: $ARGUMENTS (e.g. --slow, --days 7)

Run the hook performance profiler and display results.

**Step 1 — Run the report**

```bash
bash ~/.claude/supercharger/tools/hook-perf.sh $ARGUMENTS
```

If the command exits with "No hook timing data found", explain:
- Profiling data is only collected while the `.profiling` sentinel is active
- To start collecting: `touch ~/.claude/supercharger/scope/.profiling`
- To stop: `rm ~/.claude/supercharger/scope/.profiling`
- Then use Claude normally for a session; re-run `/perf` to see results

**Step 2 — Interpret results**

Present the table as-is. Then add a one-line summary:
- Highlight the slowest hook (highest avg_ms)
- Note if any hook averages >200ms (flag as candidate for SUPERCHARGER_PROFILE=minimal)
- Note total overhead per Claude invocation

**Step 3 — Suggest action (only if data warrants it)**

If total overhead >500ms/call or any hook >200ms avg:
- Suggest `{"profile": "minimal"}` in `.supercharger.json` if the slow hooks are in the minimal skip list
- Otherwise name the specific hook and suggest `disableHooks` if it's safe to skip
