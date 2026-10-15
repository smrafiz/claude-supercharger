---
description: "Show the current Supercharger session state: economy, guards, cost, memory."
allowed-tools: Bash(python3 ~/.claude/supercharger/tools/command-context.py:*)
---
Render the current Claude Supercharger session state. Arguments: $ARGUMENTS

Live context, gathered when this command loaded (read-only; `—` = not available):

```
!`python3 ~/.claude/supercharger/tools/command-context.py status`
```

Build the dashboard from that block. Do not re-read the files it came from. `session_cost` is summed from this session's transcript (ground truth); `subagents_all_sessions` is deduped by agent id across every session on this machine; `block:` lines are the last 3 entries of the block log — show their reason, not the raw command. If the block says `context unavailable`, fall back to reading `~/.claude/supercharger/scope/` yourself.

Output format (no other text before/after):

```
=== Claude Supercharger — Session Status ===

Project        : <cwd basename>
Role           : <from .supercharger.json or current rules>
Tier           : <minimal|lean|standard>
MCP profile    : <light|dev|research|full>
Hook profile   : <standard|fast|minimal>
Input budget   : <verbatim output of `bash ~/.claude/supercharger/tools/input-budget.sh --line` run from the project dir; "—" if the tool is missing>

Cost (session) : $X.XX / $Y.YY budget (Z% used)   [computed from the transcript — ground truth; budget from .supercharger.json]
Subagents (all sessions): <N runs> | <top agent>: $A.AA, <2nd>: $B.BB, <3rd>: $C.CC  (or "—" if no .subagent-costs-*.jsonl files)
Tools (last 10): N success / M failure
Confidence     : <derived from last 5 tool history entries — same formula as confidence-gate>
Memory         : <N> entries, updated <relative time>   [Claude file-memory]
Lessons        : <count> recorded
  - <most recent lesson, truncated to 80 chars>
  - <2nd most recent>
  - <3rd most recent>

Disabled hooks : <list from .disabled-hooks, or "none">
Last compact   : <relative time from .memory-restored mtime, or "this session">

Unscanned      : <unscanned_payloads: count of outputs a scanner timed out on and never checked, with the last hook; "0" when none. If above 0, say so plainly: those outputs were NOT checked for secrets or injection>
Recent blocks  : <last 3 lines of scope/.blocked-commands — show the category/reason, not the raw command; or "—" if the file is absent>
```



If a file doesn't exist, write `—` for that field. Don't fabricate values. Don't pad with marketing language.

If `$ARGUMENTS` contains `--watch`, suggest the user run the supercharger statusline component instead — `/sc-status` is a one-shot snapshot.
