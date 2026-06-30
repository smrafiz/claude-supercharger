Render the current Claude Supercharger session state. Arguments: $ARGUMENTS

Read these files (silently — do not show their raw content) and produce a dashboard:

**Files to read (skip any that don't exist):**
- `~/.claude/supercharger/scope/.session-cost`
- `~/.claude/supercharger/scope/.economy-tier`
- `~/.claude/supercharger/scope/.disabled-hooks`
- `~/.claude/supercharger/scope/.tool-history` (last 10 entries)
- `~/.claude/supercharger/scope/.repetition-flag-*` (any session)
- `~/.claude/supercharger/scope/.memory-restored` (mtime → "compaction X min ago")
- `.claude/supercharger/lessons.jsonl` (count + 3 most recent `lesson` fields)
- `.claude/supercharger-memory.md` (size + last modified)
- `.supercharger.json` (role, economy, profile, budget, hints)
- `~/.claude/supercharger/audit/$(date -u +%Y-%m-%d).jsonl` (count of today's events)
- `~/.claude/supercharger/scope/.subagent-costs-*.jsonl` (per-subagent cost rollup — aggregate by `agent_name`, show top 3 by `cost_usd`)

Output format (no other text before/after):

```
=== Claude Supercharger — Session Status ===

Project        : <cwd basename>
Role           : <from .supercharger.json or current rules>
Tier           : <minimal|lean|standard>
MCP profile    : <light|dev|research|full>
Hook profile   : <standard|fast|minimal>

Cost           : $X.XX / $Y.YY budget (Z% used)
Subagents (all sessions): <N runs> | <top agent>: $A.AA, <2nd>: $B.BB, <3rd>: $C.CC  (or "—" if no .subagent-costs-*.jsonl files)
Tools (last 10): N success / M failure
Confidence     : <derived from last 5 tool history entries — same formula as confidence-gate>
Memory         : <bytes> bytes, last modified <relative time>
Lessons        : <count> recorded
  - <most recent lesson, truncated to 80 chars>
  - <2nd most recent>
  - <3rd most recent>

Disabled hooks : <list from .disabled-hooks, or "none">
Last compact   : <relative time from .memory-restored mtime, or "this session">

Recent blocks  : <last 3 from learn-from-blocks log if available>
```

To compute the Subagents line: read every `~/.claude/supercharger/scope/.subagent-costs-*.jsonl` (one per session), aggregate `cost_usd` by `agent_name`, count total entries, sort by aggregate cost descending. If no files exist or every cost is 0, render `—` instead of a zero list. This is a CROSS-SESSION rollup (all sessions on this machine, not just the current one — label it "Subagents (all sessions)") and mirrors Claude Code's `/usage` per-subagent breakdown.

Compute confidence score using the same formula as `hooks/confidence-gate.sh`:
- start at 1.0
- subtract 0.20 per failure in last 5 tool-history entries
- subtract 0.30 if the current would-be Edit target is unread (skip this term — there's no current target)
- subtract 0.20 if `.repetition-flag-*` exists for current session
- clamp [0.0, 1.0]
- format to 2 decimals

If a file doesn't exist, write `—` for that field. Don't fabricate values. Don't pad with marketing language.

If `$ARGUMENTS` contains `--watch`, suggest the user run the supercharger statusline component instead — `/sc-status` is a one-shot snapshot.
