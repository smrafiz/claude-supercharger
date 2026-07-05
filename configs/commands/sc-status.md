Render the current Claude Supercharger session state. Arguments: $ARGUMENTS

Read these files (silently — do not show their raw content) and produce a dashboard:

**STEP 0 — determine the CURRENT session id (do this first; everything per-session depends on it).**
Do NOT guess by "newest file" — under concurrent sessions that grabs another project's session (the exact bug this step fixes). Derive it from the current working directory's own transcript directory:
```bash
ENC="-$(pwd | sed 's|/|-|g; s|^-||')"                 # cwd → CC's project-dir encoding
SID=$(ls -t "$HOME/.claude/projects/$ENC"/*.jsonl 2>/dev/null | head -1 | xargs -r basename | sed 's/\.jsonl$//')
```
`$SID` is THIS session. Use it for every per-session read below (`.main-tokens-$SID`, `.tool-history-$SID`, `.memory-restored-$SID`, `.repetition-flag-$SID`). If `$SID` is empty (no transcript yet), fall back to the globally-newest `.main-tokens-*` and note it.

**Session cost — compute from the TRANSCRIPT, do NOT trust `.main-tokens-$SID.cost_usd`.** That accumulator only counts from when v2.7.63 deployed, so a session spanning the upgrade is badly under-reported (observed: $22.83 vs a real $2343.54). A one-shot command can afford to re-sum the transcript for ground truth:
```bash
python3 - "$HOME/.claude/projects/$ENC/$SID.jsonl" <<'PY'
import json,sys
P={'opus':(5.0,6.25,0.5,25.0),'sonnet':(3.0,3.75,0.3,15.0),'haiku':(0.8,1.0,0.08,4.0)}
t=0.0
try:
    for ln in open(sys.argv[1]):
        try: d=json.loads(ln)
        except: continue
        if d.get('type')!='assistant': continue
        u=(d.get('message') or {}).get('usage') or {}
        if not u: continue
        m=((d.get('message') or {}).get('model') or '').lower()
        k='opus' if 'opus' in m else 'haiku' if 'haiku' in m else 'sonnet'
        ip,cw,cr,op=P[k]
        t+=(u.get('input_tokens',0)*ip+u.get('cache_creation_input_tokens',0)*cw+u.get('cache_read_input_tokens',0)*cr+u.get('output_tokens',0)*op)/1e6
except Exception: pass
print(f'{t:.2f}')
PY
```
Use that value for `Cost (session)`. (The budget cap still uses the accumulator, which is accurate for sessions that start after v2.7.63.)

**Files to read (skip any that don't exist):**
- `~/.claude/supercharger/scope/.economy-tier`
- `~/.claude/supercharger/scope/.disabled-hooks`
- `~/.claude/supercharger/scope/.tool-history-$SID` (last 10 entries)
- `~/.claude/supercharger/scope/.repetition-flag-$SID`
- `~/.claude/supercharger/scope/.memory-restored-$SID` (per-session; mtime → "compaction X min ago"). The bare `.memory-restored` (no suffix) is a DEPRECATED global flag not written since v2.7.47 — do NOT use it; if `.memory-restored-$SID` is absent, this session hasn't compacted → "this session".
- `.claude/supercharger/lessons.jsonl` (count + 3 most recent `lesson` fields)
- `.claude/supercharger-memory.md` (size + last modified)
- `.supercharger.json` (role, economy, profile, budget, hints)
- `~/.claude/supercharger/audit/$(date -u +%Y-%m-%d).jsonl` (count of today's events)
- `~/.claude/supercharger/scope/.subagent-costs-*.jsonl` (per-subagent cost rollup — aggregate by `agent_name`, show top 3 by `cost_usd`)
- `~/.claude/supercharger/scope/.blocked-commands` (the block log; last 3 lines for "Recent blocks" — format: `[ts] category — reason — command`)

Output format (no other text before/after):

```
=== Claude Supercharger — Session Status ===

Project        : <cwd basename>
Role           : <from .supercharger.json or current rules>
Tier           : <minimal|lean|standard>
MCP profile    : <light|dev|research|full>
Hook profile   : <standard|fast|minimal>

Cost (session) : $X.XX / $Y.YY budget (Z% used)   [computed from the transcript — ground truth; budget from .supercharger.json]
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

Recent blocks  : <last 3 lines of scope/.blocked-commands — show the category/reason, not the raw command; or "—" if the file is absent>
```

To compute the Subagents line: read every `~/.claude/supercharger/scope/.subagent-costs-*.jsonl` (one per session). **DEDUP by `agent_id` first** — SubagentStop can write several entries per agent, so the raw entry count over-reports runs (observed: 135 raw entries for 49 real agents). Keep the max `cost_usd` per `agent_id` (same as the statusline), then: run count = number of unique `agent_id`s; aggregate the deduped costs by `agent_name`; sort descending; show top 3. If no files exist or every cost is 0, render `—` instead of a zero list. This is a CROSS-SESSION rollup (all sessions on this machine, not just the current one — label it "Subagents (all sessions)") and mirrors Claude Code's `/usage` per-subagent breakdown.

Compute confidence score using the same formula as `hooks/confidence-gate.sh`:
- start at 1.0
- subtract 0.20 per failure in last 5 tool-history entries
- subtract 0.30 if the current would-be Edit target is unread (skip this term — there's no current target)
- subtract 0.20 if `.repetition-flag-$SID` exists (current session only)
- clamp [0.0, 1.0]
- format to 2 decimals

If a file doesn't exist, write `—` for that field. Don't fabricate values. Don't pad with marketing language.

If `$ARGUMENTS` contains `--watch`, suggest the user run the supercharger statusline component instead — `/sc-status` is a one-shot snapshot.
