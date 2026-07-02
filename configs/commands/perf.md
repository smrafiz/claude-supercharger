Show hook performance timing report. Options: $ARGUMENTS (e.g. --slow, --days 7)

Run the hook performance profiler and display results.

**Step 1 — Run the report**

```bash
bash ~/.claude/supercharger/tools/hook-perf.sh $ARGUMENTS
```

If the command exits with "No hook timing data found", explain:
- On **bash 5+** (zero-fork `EPOCHREALTIME` clock), hooks slower than ~40ms are
  recorded **automatically** — no setup; just use Claude and re-run `/perf`.
  Tune with `SUPERCHARGER_PERF_THRESHOLD_MS`.
- On **bash 3.2** (macOS default — no cheap ms clock) auto-timing is off to avoid
  a per-hook python fork. Check `bash --version`; if 3.2, enable full profiling.
- **Full profiling** (every hook fire, any bash): `touch ~/.claude/supercharger/scope/.profiling`,
  use Claude for a session, re-run `/perf`, then `rm ~/.claude/supercharger/scope/.profiling`.

**Step 2 — Interpret results**

Present the table as-is. Then add a one-line summary:
- Highlight the slowest hook (highest avg_ms)
- Note if any hook averages >200ms (flag as candidate for SUPERCHARGER_PROFILE=minimal)
- Note total overhead per Claude invocation

**Step 3 — Suggest action (only if data warrants it)**

If total overhead >500ms/call or any hook >200ms avg:
- Suggest `{"profile": "minimal"}` in `.supercharger.json` if the slow hooks are in the minimal skip list
- Otherwise name the specific hook and suggest `disableHooks` if it's safe to skip
