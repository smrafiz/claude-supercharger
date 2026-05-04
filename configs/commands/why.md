Explain the most recent Supercharger hook action. Arguments: $ARGUMENTS

If `$ARGUMENTS` is empty, examine the most recent hook activity. If `$ARGUMENTS` names a hook (e.g., `confidence-gate`), explain that hook's last firing specifically.

**Sources to consult (read in order, stop at first match):**

1. `~/.claude/supercharger/scope/.scan-alert` (mtime + content) — last scanner finding
2. `~/.claude/supercharger/scope/.blocked-commands-*` (most recent line) — last block reason
3. `~/.claude/supercharger/scope/.user-corrections-*` (most recent line) — last correction
4. `~/.claude/supercharger/scope/.failed-commands` (most recent line) — last failure cluster
5. `~/.claude/supercharger/audit/$(date -u +%Y-%m-%d).jsonl` (last 5 entries) — recent audit events
6. `~/.claude/supercharger/scope/.tool-history` (last entry) — last tool result

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
