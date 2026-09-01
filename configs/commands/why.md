Explain the most recent Supercharger hook action. Arguments: $ARGUMENTS

If `$ARGUMENTS` is empty, examine the most recent hook activity. If `$ARGUMENTS` names a hook (e.g., `confidence-gate`), explain that hook's last firing specifically.

**Sources to consult (read in order, stop at first match).** Scope files gained
`-<session>`/`-<project-hash>` suffixes over time — these are the CURRENT names, so
use the globs exactly as written (pick the most-recently-MODIFIED match, `ls -t … | head -1`):

1. `~/.claude/supercharger/scope/.scan-alert-*` (mtime + content; newest) — last scanner finding
2. `~/.claude/supercharger/scope/.blocked-commands` (last line — **single global file, NO suffix**) — last block reason
3. `~/.claude/supercharger/scope/.user-corrections*` (last line of newest) — last correction
4. `~/.claude/supercharger/scope/.failed-commands-*` (last line of newest — per-project hash) — last failure cluster
4a. `~/.claude/supercharger/scope/.subagent-report-*` (last 3 lines of newest — per-session) — a subagent whose final message came back degraded ("Ready.", "Done.", "Standing by."), i.e. Claude Code's return-channel bug. Its findings were recovered to disk. **Report the path and tell the user to read it** with `bash ~/.claude/supercharger/tools/subagent-report.sh <agent-id>` (or `--latest`). This is not a block and nothing failed — the work completed, only the reply was lost.
4b. `~/.claude/supercharger/scope/.prompt-notes-*` (last 3 lines of newest — per-session) — prompt-validator's phrasing advice. It runs **async**, so this note may have scrolled past or arrived beside the answer; this file is where it is kept. Report it as guidance on how the request was phrased, never as something that blocked anything.
4c. `~/.claude/supercharger/scope/.detect-overruns` (count the lines; report only if the newest entry is from this session's timeframe) — safety.sh's deep scanner hit its wall-clock budget and was killed, so it fell back to the regex checks alone. This is the one source here that explains why something did **not** fire: `check_archive_secrets` and `check_secret_directory` live only in `safety-detect.py`, so while it is cut short those rules are not running. Measured at ~0.6% of calls under heavy parallel load. Report it as a fail-OPEN that already happened — nothing was blocked, a check was skipped — and name the lever: `SUPERCHARGER_DETECT_BUDGET_S` (default 0.5). Usually just a loaded machine.
5. `~/.claude/supercharger/audit/$(date -u +%Y-%m-%d).jsonl` (last 5 entries **that have a `hook` field** — skip timing/field-less rows) — recent audit events
6. `~/.claude/supercharger/scope/.tool-history-*` (last line of newest — per-session) — last tool result

For each source that matched, explain:

- **What fired** — hook name + event (e.g., `confidence-gate.sh on PreToolUse:Edit`)
- **Why** — the specific signal (e.g., "3 failures in last 5 tool calls + read-before-write violation on /tmp/foo.ts → score 0.50, warn tier")
- **Where** — file:line if applicable
- **What to do** — concrete next step (e.g., "Run `bash tools/hook-toggle.sh confidence-gate off` for this session, or read the file before editing")

Output format (one block per source matched, max 3):

```
=== Why the last action fired ===

[1] <hook-name> at <relative time>
    Event:   <PreToolUse|PostToolUse|...>:<tool>
    Reason:  <one sentence>
    Detail:  <evidence snippet — file:line, score, threshold, etc.>
    Fix:     <concrete next step>
```

If no hook activity is found in any source: print `No recent hook activity recorded.`

Do not narrate the investigation. Lead with the answer.
