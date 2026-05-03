# Confidence Gate — Design

**Date:** 2026-04-30
**Status:** Spec / pre-implementation
**Owner:** smrafiz

## Goal

Compute a runtime confidence score (0.0–1.0) from observable signals already collected by supercharger, and gate risky tool calls before they execute. Three tiers: allow silently, allow with warning, or deny via PreToolUse permission decision.

## Motivation

Competitor research (SuperClaude `confidence-check` skill) showed pure prompt-engineering self-policing: Claude reads a markdown file telling it to self-assess, no runtime enforcement. claude-supercharger has hook events and per-session state — it can ship a real gate where SuperClaude can't. This is a differentiator. Real protection against thrashing, repeat failures, and Read-before-Write violations.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Hook-computed (no Claude self-assessment) | Eliminates gaming surface; reuses signals already collected |
| D2 | Gate Edit + Write + destructive Bash only | High-impact tools without blocking common ops; reuses `safety-detect.py` for destructive classification |
| D3 | Signals: recent failures + read-before-write + repetition | Highest-signal observables; all three already detected by existing hooks |
| D4 | Three-tier action: ≥0.7 allow, 0.4–0.7 warn+allow, <0.4 deny | Reduces false-positive friction; deny only at clear danger |
| D5 | Window: last 5 tool calls | Simple, bounded, recovers naturally as window slides; aligns with existing failure-tracker windowing |
| D6 | State in `~/.claude/supercharger/scope/.tool-history` (rolling 20) | Per-user, auto-pruned by existing scope-cleanup; per-session via `session_id` |
| D7 | Tier-scaled output (minimal/lean/standard) | Honors token economy |
| D8 | Disable via `SUPERCHARGER_CONFIDENCE=0` | Standard env-var pattern matching new hooks |

## Architecture

```
PostToolUse (any tool)
   │
   ▼
hooks/tool-history-tracker.sh
   │
   ├─ append { session_id, tool, success, ts } to scope/.tool-history
   └─ trim to last 20 entries

PreToolUse (Edit, Write, Bash[destructive])
   │
   ▼
hooks/confidence-gate.sh
   │
   ├─ matcher pre-filter: skip if tool not in gated set
   │  └─ for Bash: run safety-detect.py classification first; skip if non-destructive
   ├─ load last 5 history entries for current session_id
   ├─ compute deductions:
   │  ├─ failures_in_last_5 × 0.20
   │  ├─ read-before-write violation (check scope/.read-files for target path)
   │  └─ repetition flagged (check scope/.repetition-flag for current session)
   ├─ score = clamp(1.0 − Σ deductions, 0.0, 1.0)
   └─ tier action:
      ├─ ≥ 0.7 → exit 0 silently
      ├─ 0.4–0.7 → systemMessage with reason; allow
      └─ < 0.4 → permissionDecision: "deny" with reason
```

## Components

### `hooks/tool-history-tracker.sh` (new, PostToolUse)

Appends one JSON line per tool call to `~/.claude/supercharger/scope/.tool-history`:

```jsonl
{"session_id":"abc123","tool":"Edit","success":true,"ts":1730313600}
```

- `success`: derived from `tool_response.exit_code` (Bash) or absence of error key
- Trim to last 20 entries to bound disk size
- Async hook (write-only, non-blocking)

### `hooks/confidence-gate.sh` (new, PreToolUse, matcher: `Edit,Write,Bash`)

1. Read `tool_name` from input JSON
2. If `Edit` or `Write`: proceed to scoring
3. If `Bash`: invoke `safety-detect.py` classification; skip if non-destructive
4. Load last 5 entries from `.tool-history` matching current `session_id`
5. Compute deductions per formula
6. Apply tier action

Output for warn/deny tier follows v2.1.119 PreToolUse schema:
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
```
For warn tier: emit `systemMessage` only, no permission decision.

### Signal sources (reuse existing state files)

| Signal | Source | How |
|---|---|---|
| Recent failures | `scope/.tool-history` (this spec, new) | Count entries with `success: false` in last 5 for session |
| Read-before-write | `scope/.read-files` (already maintained by scope-guard) | Check whether target Edit/Write path appears in read-files |
| Repetition flagged | `scope/.repetition-flag-<session>` (extend repetition-detector) | One-line marker file dropped when repetition detected; cleared on success |

Repetition-detector currently logs to events.log but doesn't drop a per-session marker. Minor extension: add `touch` of marker when threshold tripped.

## Score Formula

```
score = 1.0
  − 0.20 × failures_in_last_5            # 0–5 → 0–1.0
  − 0.30 × read_before_write_violation   # 0 or 1 → 0 or 0.30
  − 0.20 × repetition_flagged            # 0 or 1 → 0 or 0.20
clamp to [0.0, 1.0]
```

Maximum total deduction: 1.0 + 0.30 + 0.20 = 1.50 (clamped to 1.0).

Worst case (5 failures + read-before-write + repetition): score = 0.0 → deny.
Typical case (1 failure, no other flags): score = 0.80 → allow silently.
Borderline (3 failures): score = 0.40 → warn boundary.

## Tier Output (warn/deny only)

### minimal
```
[conf:0.42→warn]
```

### lean
```
confidence 0.42: 2 failures + repetition
```

### standard
```
Confidence gate: 0.42 (warn)
  - 2 recent tool failures (-0.40)
  - repetition pattern flagged (-0.20)
Proceed with caution.
```

For deny tier, prefix with explicit denial: `Confidence gate denied <Tool> call (score 0.30):`.

## File Layout

```
claude-supercharger/
├── hooks/
│   ├── confidence-gate.sh           ← new (PreToolUse)
│   └── tool-history-tracker.sh      ← new (PostToolUse)
├── tests/
│   └── test-confidence-gate.sh      ← new
└── lib/
    └── hooks.sh                     ← register both
```

Runtime state:
```
~/.claude/supercharger/scope/.tool-history
~/.claude/supercharger/scope/.repetition-flag-<session_id>
~/.claude/supercharger/scope/.read-files (existing)
```

## Configuration

`lib/hooks.sh` registration in base mode:
```bash
hooks+=("PostToolUse||${hooks_dir}/tool-history-tracker.sh|async")
hooks+=("PreToolUse|Edit,Write,Bash|${hooks_dir}/confidence-gate.sh|")
```

Note: tool-history-tracker is async (write-only). confidence-gate is sync (must complete before tool runs).

## Performance

- tool-history-tracker: ~5ms per call (single line append + tail trim)
- confidence-gate: target <50ms p95
  - Read .tool-history: ~5ms
  - safety-detect.py invocation (Bash only): ~30ms
  - Score compute: ~1ms
  - Total worst-case: ~40ms

## Testing

`tests/test-confidence-gate.sh` covers:
- High score → silent allow (no output)
- Mid score (warn tier) → systemMessage emitted
- Low score (deny tier) → permissionDecision: deny
- Edit on unread file → read-before-write deduction applied
- 3+ failures in last 5 → mid tier triggered
- Repetition marker present → deduction applied
- Bash with non-destructive command → no gate (skipped via safety-detect)
- Bash with destructive command (rm -rf) → gated
- `SUPERCHARGER_CONFIDENCE=0` → disabled
- Tier-scaled output verified at minimal/lean/standard

`tests/test-tool-history-tracker.sh` covers:
- Append on success
- Append on failure
- Trim to last 20 entries
- Per-session_id segregation

## Out of Scope (v2)

- Hybrid scoring (Claude proposes, hook validates)
- Time-based windowing (currently tool-call-count only)
- Project-specific thresholds (`.supercharger/confidence.toml`)
- Slash command `/confidence` to inspect current score
- Whitelist patterns (always-allow specific tool calls)
- Verification signal (no test run since last code change)

## Risks

| Risk | Mitigation |
|---|---|
| False-positive denials block legitimate work | Three-tier model; warn-zone covers edge cases; env-var disable available |
| Disk write on every PostToolUse | Async hook, append-only, capped at 20 entries (~5KB) |
| Read-before-write detection misses files read via Bash `cat` | scope-guard already handles Read tool; Bash file reads not gated by Read law in supercharger today — out of scope |
| Race conditions in concurrent tool calls (parallel agents) | session_id segregation; trim atomic via `mv` |
| safety-detect.py overhead on every Bash call | Already runs for safety; result is cacheable but not cached today — accepted ~30ms |

## Acceptance Criteria

- [ ] `hooks/confidence-gate.sh` registered as PreToolUse with `Edit,Write,Bash` matcher
- [ ] `hooks/tool-history-tracker.sh` registered as PostToolUse async
- [ ] Score formula matches spec exactly
- [ ] Three-tier output (allow silent / warn+allow / deny) verified
- [ ] Read-before-write deduction triggers correctly
- [ ] Repetition deduction triggers correctly
- [ ] Failures-in-last-5 deduction triggers correctly
- [ ] Bash non-destructive commands not gated
- [ ] `SUPERCHARGER_CONFIDENCE=0` disables both hooks
- [ ] Test suite passes (10+ new tests)
- [ ] Performance: <50ms p95 on PreToolUse path
- [ ] `docs/HOOKS.md` regenerated
