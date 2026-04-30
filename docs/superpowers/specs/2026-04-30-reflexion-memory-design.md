# Reflexion Memory — Design

**Date:** 2026-04-30
**Status:** Spec / pre-implementation
**Owner:** smrafiz

## Goal

Capture lessons from solved problems (root cause + fix) at end of each turn, then surface relevant past lessons when the user begins similar work in future turns. Per-project, lexical match, tier-scaled.

## Motivation

Competitor diff (SuperClaude) showed `reflexion_memory.py` — JSONL append-only error→solution log with Jaccard recall. Supercharger already captures failures (`failure-tracker.sh`, `event-logger.sh`) but does not extract lessons or surface them in future turns. Same mistakes repeat across sessions.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Capture trigger: Stop hook scans transcript | End-of-turn = full reasoning available. Lowest friction. |
| D2 | Schema: signature + fix + files + lesson + recall key + timestamp | Compact; supports both narrative context and matching |
| D3 | Storage: per-project `<repo>/.claude/supercharger/lessons.jsonl` | Lessons codebase-tied; cross-project leakage avoided |
| D4 | Recall trigger: UserPromptSubmit hook | Preventive; surfaces lessons before work starts |
| D5 | Match: Jaccard word overlap, threshold 0.5 | Zero deps; proven in SuperClaude; tunable |
| D6 | Extraction: pattern match in assistant's last message | Simple v1; 80% of value |
| D7 | Cap: max 3 lessons injected per recall | Prevents runaway token cost on common keywords |
| D8 | Tier-scaled output | Honors token economy |

## Architecture

```
Stop event
   │
   ▼
hooks/lesson-record.sh
   │
   ├─ read transcript_path from input JSON
   ├─ extract assistant's last message
   ├─ scan for markers (the issue was, root cause, fixed by, ...)
   ├─ if matched: build record (sig, fix, files, lesson, recall key)
   └─ append JSONL to <repo>/.claude/supercharger/lessons.jsonl

UserPromptSubmit event
   │
   ▼
hooks/lesson-recall.sh
   │
   ├─ tokenize user prompt
   ├─ load lessons.jsonl (per-project)
   ├─ compute Jaccard overlap vs each lesson's recall key
   ├─ keep matches ≥ 0.5, top 3 by score
   └─ emit additionalContext block (tier-scaled)
```

## Components

### `hooks/lesson-record.sh` (new, Stop hook)

Reads `transcript_path` from Stop input JSON. Loads transcript (JSONL of conversation messages). Extracts the last assistant message text.

Pattern markers (case-insensitive):
- `the issue was`
- `root cause`
- `fixed by`
- `the problem was`
- `turns out`
- `it failed because`

If any marker present, extracts:
- `sig`: 1-line description before the marker (or first 100 chars of last user message)
- `fix`: text after the marker, up to 200 chars
- `files`: list of files referenced in assistant's message (regex: paths)
- `lesson`: 1-line takeaway (heuristic: first sentence of post-marker text)
- `recall`: lowercase tokens from sig + fix, deduplicated, joined by space (used for Jaccard)
- `ts`: ISO timestamp

Append JSON line to `<repo>/.claude/supercharger/lessons.jsonl` (creates dir/file if missing).

Skip if `SUPERCHARGER_LESSONS=0` or `lessons.jsonl` would exceed 1000 entries (rotate).

### `hooks/lesson-recall.sh` (new, UserPromptSubmit hook)

Reads user prompt from input JSON.

1. Locate `<repo>/.claude/supercharger/lessons.jsonl` (walk up from `cwd`)
2. Tokenize prompt to lowercase word set
3. For each lesson: compute Jaccard against its `recall` token set
4. Keep matches with score ≥ 0.5
5. Sort by score descending, take top 3
6. Emit per active tier:
   - `minimal`: `[lessons: 2 matched]` (no detail)
   - `lean`: one line per lesson — `- {lesson}`
   - `standard`: per lesson — `- {lesson}\n  fix: {fix}\n  files: {files}`

Output via `additionalContext` JSON field. Suppressed by `SUPERCHARGER_LESSONS=0`.

### Storage: `<repo>/.claude/supercharger/lessons.jsonl`

JSONL. One record per line:

```json
{"sig":"npm test fails: cannot find module foo","fix":"add foo to package.json deps","files":["package.json"],"lesson":"new imports require explicit dep add","recall":"npm test cannot find module foo add package json deps","ts":"2026-04-30T12:00:00Z"}
```

- Per-project (in repo root, gitignored optional)
- Append-only
- Cap at 1000 entries (oldest pruned via tools/scope-cleanup.sh integration)

## Tier Output

| Tier | Capture | Recall |
|---|---|---|
| minimal | active | `[lessons: N matched]` |
| lean | active | one-line per match |
| standard | active | full lesson+fix+files |

Capture is always-on regardless of tier (cheap; no model output).

## Disable Path

`SUPERCHARGER_LESSONS=0` — disables both record and recall hooks.

## File Layout

```
claude-supercharger/
├── hooks/
│   ├── lesson-record.sh         ← new (Stop)
│   └── lesson-recall.sh         ← new (UserPromptSubmit)
├── tests/
│   └── test-lessons.sh          ← new
└── tools/
    └── scope-cleanup.sh         ← extend with lessons.jsonl rotation
```

Storage created in user repo at runtime:
```
<user-repo>/.claude/supercharger/lessons.jsonl
```

## Configuration

Hook registration in `lib/hooks.sh` base mode:
```
hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
```

Note: lesson-record runs async (non-blocking, write-only). lesson-recall runs sync because output must reach Claude before processing the prompt.

## Performance

- Capture: post-Stop, async, ~50ms (regex on last message)
- Recall: pre-prompt, sync, target <80ms
  - Read JSONL: ~5ms for <1000 lines
  - Tokenize prompt: ~1ms
  - Jaccard 1000 records: ~20ms
- File I/O dominates; mitigation: cap at 1000 entries

## Testing

- `tests/test-lessons.sh` covers:
  - Stop hook: marker present → record appended
  - Stop hook: no marker → no record
  - Stop hook: `SUPERCHARGER_LESSONS=0` → no record
  - Recall: prompt overlaps lesson → injection happens
  - Recall: no overlap → no injection
  - Recall: tier=minimal → `[lessons: N matched]` format
  - Recall: tier=lean → 1-line format
  - Recall: tier=standard → full format
  - Recall: cap at 3 matches
  - Recall: `SUPERCHARGER_LESSONS=0` → no output
  - Storage: per-project, walks up from cwd to find `.claude/supercharger/lessons.jsonl`

## Out of Scope (v2)

- PostToolUseFailure recall ("seen this error before")
- Embeddings-based match
- Cross-project lesson sharing
- Lesson editing UI / dedup tooling
- Failed→passed test detection as capture signal
- Auto-summarization of lessons via second model call

## Risks

| Risk | Mitigation |
|---|---|
| False-positive lesson recording (Claude says "the issue was X" speculatively) | Marker list curated; v2 adds test-state check |
| Recall noise: common words match too many lessons | Threshold 0.5 + top-3 cap; tune in production |
| Lessons.jsonl grows unbounded | 1000-entry cap, scope-cleanup integration |
| Privacy: lessons may contain code paths/error details | Per-project storage; user can `.gitignore` |
| Disk write on every Stop event | Async hook; write-only; <5KB per record |

## Acceptance Criteria

- [ ] `hooks/lesson-record.sh` registered as Stop hook (async)
- [ ] `hooks/lesson-recall.sh` registered as UserPromptSubmit hook (sync)
- [ ] Lessons append correctly when markers present
- [ ] No record without markers
- [ ] Recall injects top 3 matches at threshold 0.5
- [ ] Tier-scaled output verified at minimal/lean/standard
- [ ] `SUPERCHARGER_LESSONS=0` disables both hooks
- [ ] Test suite passes (10+ new tests)
- [ ] Performance: recall <80ms p95 on 1000-entry corpus
- [ ] `docs/HOOKS.md` includes new hooks
