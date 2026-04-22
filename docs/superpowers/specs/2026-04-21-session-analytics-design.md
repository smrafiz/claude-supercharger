# Session Analytics — Design Spec
_2026-04-21_

## Goal

Surface daily cost, cache efficiency, and per-project token spend from Claude Code's native JSONL session files. No external service. Pure Python + bash, consistent with existing tooling.

---

## Deliverables

| File | Purpose |
|---|---|
| `tools/session-analytics.sh` | New standalone tool |
| `tools/claude-check.sh` | Add 2-line analytics summary to existing diagnostic |
| `tests/test-session-analytics.sh` | New test file |

---

## Data Source

Claude Code writes one JSONL file per session to `~/.claude/projects/<slug>/`.

- Slug is the project path with `/` replaced by `-` (e.g. `-Users-foo-myproject`)
- Each assistant turn has a `usage` object: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`
- Session start time is taken from the first `timestamp` field in the file
- Project name is derived from the directory slug (reverse the `-` → `/` transform, take the last path component)

---

## session-analytics.sh

### CLI

```bash
bash tools/session-analytics.sh [--days N] [--projects PATH]
```

| Flag | Default | Description |
|---|---|---|
| `--days N` | 7 | Lookback window in days |
| `--projects PATH` | `~/.claude/projects/` | Override projects directory |
| `--help` | — | Usage text |

### Implementation

Bash wrapper handles:
1. Arg parsing
2. Discovering all project dirs under `~/.claude/projects/`
3. Finding JSONL files modified within `--days` window
4. Passing file list + metadata to inline Python block via env vars

Python inline block handles:
1. Parse each JSONL line by line (streaming, no full load)
2. Accumulate `input`, `cache_write`, `cache_read`, `output`, `turns` per session
3. Aggregate by date (from session start timestamp) and by project
4. Compute cost and cache hit rate
5. Print Section 1 (daily rollup) and Section 2 (per-project breakdown)

### Pricing (claude-sonnet-4-6, per 1M tokens)

| Token type | Price |
|---|---|
| Input | $3.00 |
| Cache write | $3.75 |
| Cache read | $0.30 |
| Output | $15.00 |

### Output — Section 1: Daily Rollup

```
  Daily Summary — last 7 days
  ─────────────────────────────────────────────────────
  Date         Sessions   Turns    Cost    Saved   Cache%
  ───────────  ────────   ─────   ──────  ──────   ──────
  2026-04-21        3      142    $4.21   $18.50     81%
  2026-04-20        5      287   $12.44   $61.20     83%
  ───────────  ────────   ─────   ──────  ──────   ──────
  TOTAL            18    1240   $48.33  $210.40     81%
```

### Output — Section 2: Per-Project Breakdown

```
  Per-Project — last 7 days
  ─────────────────────────────────────────────────────────────────
  Project                        Sessions   Turns    Cost    Cache%
  ─────────────────────────────  ────────   ─────   ──────   ──────
  claude-supercharger                  12     890   $32.10      84%
  easy-demo-importer                    6     350   $16.23      76%
  ─────────────────────────────  ────────   ─────   ──────   ──────
  TOTAL                                18    1240   $48.33      81%
```

---

## claude-check.sh Integration

Add a summary line in the existing diagnostic after the health score section:

```
  Analytics (7d): $48.33 across 18 sessions | cache 81% | saved $210.40
```

Implementation: inline Python block re-using the same parsing logic, scoped to all projects, last 7 days.

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `~/.claude/projects/` missing | Print "No session data found" and exit 0 |
| Project dir has no JSONL in window | Skip silently |
| Malformed JSONL line | Skip line, continue |
| Session with 0 turns | Excluded from all counts |
| `--days 0` | Show today only |
| Large files (10MB+) | Streamed line-by-line, no full load |

---

## Tests (`tests/test-session-analytics.sh`)

| Test | What it checks |
|---|---|
| Script exists and is executable | Existence + permissions |
| `--help` exits 0 | CLI contract |
| Missing projects dir exits cleanly | Graceful degradation |
| Synthetic JSONL fixture produces correct cost | Core parsing logic |
| Cache hit rate calculation | Math correctness |
| Zero-turn sessions excluded | Edge case |

---

## Out of Scope

- Model-specific pricing (all sessions priced at sonnet-4-6 rates — sufficient for relative comparisons)
- Subagent session tracking (subagent JSONL dirs skipped)
- Export to CSV/JSON (can be added later)
- Real-time / live session tracking
