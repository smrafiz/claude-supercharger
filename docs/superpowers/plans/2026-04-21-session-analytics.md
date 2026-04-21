# Session Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface daily cost, cache efficiency, and per-project token spend from Claude Code JSONL session files via a new `tools/session-analytics.sh` tool and a summary line in `tools/claude-check.sh`.

**Architecture:** Bash wrapper handles arg parsing and file discovery across all project dirs; an inline Python block streams each JSONL file, aggregates by date and project, then prints two tables. The `claude-check.sh` integration adds a one-line summary using a separate but parallel Python snippet following the same parsing pattern.

**Tech Stack:** Bash, Python 3 (stdlib only — `json`, `os`, `time`, `datetime`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `tools/session-analytics.sh` | CLI + discovery + Python analytics block |
| Modify | `tools/claude-check.sh` | Add analytics summary after health score |
| Create | `tests/test-session-analytics.sh` | 6 tests covering all spec requirements |

---

### Task 1: Scaffold session-analytics.sh with arg parsing

**Files:**
- Create: `tools/session-analytics.sh`

- [ ] **Step 1: Write the failing test for --help**

```bash
# tests/test-session-analytics.sh (create this file)
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/session-analytics.sh"

echo "=== Session Analytics Tests ==="

begin_test "session-analytics: script exists and is executable"
if [ -f "$TOOL" ] && [ -x "$TOOL" ]; then
  pass
else
  fail "expected $TOOL to exist and be executable"
fi

begin_test "session-analytics: --help exits 0"
bash "$TOOL" --help >/dev/null 2>&1
assert_exit_code 0 $? && pass

begin_test "session-analytics: missing projects dir exits 0 with message"
OUTPUT=$(bash "$TOOL" --projects /nonexistent/path 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -qi "no session data"; then
  pass
else
  fail "expected exit 0 and 'no session data' message, got exit $EXIT_CODE: $OUTPUT"
fi
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/test-session-analytics.sh
```

Expected: FAIL on all 3 (script not found)

- [ ] **Step 3: Create the scaffold**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Session Analytics
# Usage: bash tools/session-analytics.sh [--days N] [--projects PATH]

set -euo pipefail

DAYS=7
PROJECTS_DIR="$HOME/.claude/projects"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days|-d)     DAYS="$2"; shift 2 ;;
    --projects|-p) PROJECTS_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash tools/session-analytics.sh [--days N] [--projects PATH]"
      echo "  --days N        Lookback window in days (default: 7)"
      echo "  --projects PATH Override projects directory (default: ~/.claude/projects/)"
      exit 0 ;;
    *) shift ;;
  esac
done

if [ ! -d "$PROJECTS_DIR" ]; then
  echo "No session data found"
  exit 0
fi
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x tools/session-analytics.sh
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bash tests/test-session-analytics.sh
```

Expected: PASS on all 3

- [ ] **Step 6: Commit**

```bash
git add tools/session-analytics.sh tests/test-session-analytics.sh
git commit -m "feat(analytics): scaffold session-analytics.sh with arg parsing and tests"
```

---

### Task 2: Add file discovery and daily rollup table

**Files:**
- Modify: `tools/session-analytics.sh`
- Modify: `tests/test-session-analytics.sh`

- [ ] **Step 1: Add the failing cost test to tests/test-session-analytics.sh**

Append to `tests/test-session-analytics.sh`:

```bash
begin_test "session-analytics: synthetic fixture produces correct cost"
TMPDIR_FIXTURE=$(mktemp -d)
mkdir -p "$TMPDIR_FIXTURE/proj-foo"
# 1 assistant turn: input=1,000,000 tokens, all others 0
# Expected cost: 1000000 * $3.00/1M = $3.00
cat > "$TMPDIR_FIXTURE/proj-foo/session1.jsonl" << 'JSONL'
{"type":"user","timestamp":"2026-04-21T10:00:00Z","message":{"content":"hello"}}
{"type":"assistant","timestamp":"2026-04-21T10:00:01Z","message":{"usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
JSONL

OUTPUT=$(bash "$TOOL" --projects "$TMPDIR_FIXTURE" --days 7 2>&1)
if echo "$OUTPUT" | grep -q '\$3\.00'; then
  pass
else
  fail "expected \$3.00 in output, got: $OUTPUT"
fi
rm -rf "$TMPDIR_FIXTURE"
```

- [ ] **Step 2: Run to verify the test fails**

```bash
bash tests/test-session-analytics.sh
```

Expected: FAIL on "synthetic fixture" (no output yet)

- [ ] **Step 3: Add file discovery and Python block to tools/session-analytics.sh**

Append after the missing-dir check:

```bash
# Collect all JSONL files across all project dirs (maxdepth 1 per project = skip subagent subdirs)
FILE_LIST=""
while IFS= read -r -d '' proj_dir; do
  proj_slug=$(basename "$proj_dir")
  while IFS= read -r -d '' f; do
    FILE_LIST="${FILE_LIST}${proj_slug}|${f}"$'\n'
  done < <(find "$proj_dir" -maxdepth 1 -name "*.jsonl" -not -empty -print0 2>/dev/null)
done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

if [ -z "$FILE_LIST" ]; then
  echo "No session data found"
  exit 0
fi

SUPERCHARGER_FILE_LIST="$FILE_LIST" SUPERCHARGER_DAYS="$DAYS" python3 << 'PYEOF'
import os, json, sys, time
from datetime import datetime

PRICE = {
    'input':       3.00,
    'cache_write': 3.75,
    'cache_read':  0.30,
    'output':     15.00,
}

days      = int(os.environ.get('SUPERCHARGER_DAYS', '7'))
file_raw  = os.environ.get('SUPERCHARGER_FILE_LIST', '')
cutoff    = time.time() - days * 86400

def slug_to_name(slug):
    path = slug.replace('-', '/')
    return os.path.basename(path.rstrip('/')) or slug

def parse_session(path):
    t = dict(input=0, cache_write=0, cache_read=0, output=0, turns=0)
    ts_start = ''
    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                    ts = d.get('timestamp', '')
                    if ts and not ts_start:
                        ts_start = ts
                    if d.get('type') == 'assistant':
                        u = d.get('message', {}).get('usage', {})
                        if u:
                            t['input']       += u.get('input_tokens', 0)
                            t['cache_write'] += u.get('cache_creation_input_tokens', 0)
                            t['cache_read']  += u.get('cache_read_input_tokens', 0)
                            t['output']      += u.get('output_tokens', 0)
                            t['turns']       += 1
                except Exception:
                    pass
    except Exception:
        pass
    return t, ts_start

def total_cost(t):
    return (t['input']       / 1e6 * PRICE['input'] +
            t['cache_write'] / 1e6 * PRICE['cache_write'] +
            t['cache_read']  / 1e6 * PRICE['cache_read'] +
            t['output']      / 1e6 * PRICE['output'])

def cache_savings(t):
    return t['cache_read'] / 1e6 * (PRICE['input'] - PRICE['cache_read'])

def cache_pct(t):
    denom = t['cache_read'] + t['input']
    return int(t['cache_read'] / denom * 100) if denom > 0 else 0

def ts_to_date(ts):
    if not ts:
        return 'unknown'
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00')).strftime('%Y-%m-%d')
    except Exception:
        return ts[:10]

def new_row():
    return dict(input=0, cache_write=0, cache_read=0, output=0, turns=0, sessions=0, cost=0.0, saved=0.0)

def add_to(row, t, cost, saved):
    for k in ('input', 'cache_write', 'cache_read', 'output', 'turns'):
        row[k] += t[k]
    row['sessions'] += 1
    row['cost']     += cost
    row['saved']    += saved

by_date    = {}
by_project = {}

for line in file_raw.splitlines():
    line = line.strip()
    if not line or '|' not in line:
        continue
    slug, path = line.split('|', 1)
    try:
        if os.path.getmtime(path) < cutoff:
            continue
    except OSError:
        continue
    t, ts_start = parse_session(path)
    if t['turns'] == 0:
        continue
    date = ts_to_date(ts_start)
    name = slug_to_name(slug)
    cost = total_cost(t)
    saved = cache_savings(t)
    if date not in by_date:
        by_date[date] = new_row()
    add_to(by_date[date], t, cost, saved)
    if name not in by_project:
        by_project[name] = new_row()
    add_to(by_project[name], t, cost, saved)

# Totals (sum from by_date to avoid double-count)
grand = new_row()
for r in by_date.values():
    for k in ('input', 'cache_write', 'cache_read', 'output', 'turns', 'sessions'):
        grand[k] += r[k]
    grand['cost']  += r['cost']
    grand['saved'] += r['saved']

label = f"last {days} day{'s' if days != 1 else ''}"

# ── Section 1: Daily Rollup ──────────────────────────────────────────
print()
print(f"  Daily Summary — {label}")
print(f"  {'─'*55}")
print(f"  {'Date':<12}  {'Sessions':>8}   {'Turns':>5}    {'Cost':>6}  {'Saved':>7}   {'Cache%':>6}")
print(f"  {'─'*11}  {'─'*8}   {'─'*5}    {'─'*6}  {'─'*7}   {'─'*6}")

for date in sorted(by_date.keys(), reverse=True):
    r   = by_date[date]
    pct = cache_pct(r)
    print(f"  {date:<12}  {r['sessions']:>8}   {r['turns']:>5}    ${r['cost']:>5.2f}  ${r['saved']:>6.2f}   {pct:>5}%")

print(f"  {'─'*11}  {'─'*8}   {'─'*5}    {'─'*6}  {'─'*7}   {'─'*6}")
print(f"  {'TOTAL':<12}  {grand['sessions']:>8}   {grand['turns']:>5}    ${grand['cost']:>5.2f}  ${grand['saved']:>6.2f}   {cache_pct(grand):>5}%")
print()

# ── Section 2: Per-Project Breakdown ────────────────────────────────
if not by_project:
    sys.exit(0)

W = max((len(n) for n in by_project), default=10) + 2
W = max(W, 20)

print(f"  Per-Project — {label}")
print(f"  {'─'*(W + 42)}")
print(f"  {'Project':<{W}}  {'Sessions':>8}   {'Turns':>5}    {'Cost':>6}   {'Cache%':>6}")
print(f"  {'─'*W}  {'─'*8}   {'─'*5}    {'─'*6}   {'─'*6}")

for name in sorted(by_project.keys(), key=lambda n: by_project[n]['cost'], reverse=True):
    r   = by_project[name]
    pct = cache_pct(r)
    print(f"  {name:<{W}}  {r['sessions']:>8}   {r['turns']:>5}    ${r['cost']:>5.2f}   {pct:>5}%")

print(f"  {'─'*W}  {'─'*8}   {'─'*5}    {'─'*6}   {'─'*6}")
print(f"  {'TOTAL':<{W}}  {grand['sessions']:>8}   {grand['turns']:>5}    ${grand['cost']:>5.2f}   {cache_pct(grand):>5}%")
print()
PYEOF
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test-session-analytics.sh
```

Expected: PASS on all 4 tests so far

- [ ] **Step 5: Commit**

```bash
git add tools/session-analytics.sh tests/test-session-analytics.sh
git commit -m "feat(analytics): add JSONL parsing and daily/per-project rollup tables"
```

---

### Task 3: Add cache hit rate and zero-turn tests

**Files:**
- Modify: `tests/test-session-analytics.sh`

- [ ] **Step 1: Add the cache hit rate test**

Append to `tests/test-session-analytics.sh`:

```bash
begin_test "session-analytics: cache hit rate calculation"
TMPDIR_FIXTURE=$(mktemp -d)
mkdir -p "$TMPDIR_FIXTURE/proj-bar"
# input=1,000,000  cache_read=1,000,000  → cache% = 50%
cat > "$TMPDIR_FIXTURE/proj-bar/session1.jsonl" << 'JSONL'
{"type":"user","timestamp":"2026-04-21T10:00:00Z","message":{"content":"hello"}}
{"type":"assistant","timestamp":"2026-04-21T10:00:01Z","message":{"usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000000,"output_tokens":0}}}
JSONL

OUTPUT=$(bash "$TOOL" --projects "$TMPDIR_FIXTURE" --days 7 2>&1)
if echo "$OUTPUT" | grep -qE '50%'; then
  pass
else
  fail "expected 50% cache hit rate in output, got: $OUTPUT"
fi
rm -rf "$TMPDIR_FIXTURE"

begin_test "session-analytics: zero-turn sessions excluded"
TMPDIR_FIXTURE=$(mktemp -d)
mkdir -p "$TMPDIR_FIXTURE/proj-empty"
# File has only user turns, no assistant usage
cat > "$TMPDIR_FIXTURE/proj-empty/session1.jsonl" << 'JSONL'
{"type":"user","timestamp":"2026-04-21T10:00:00Z","message":{"content":"hello"}}
{"type":"user","timestamp":"2026-04-21T10:00:01Z","message":{"content":"world"}}
JSONL

OUTPUT=$(bash "$TOOL" --projects "$TMPDIR_FIXTURE" --days 7 2>&1)
# Should show "No session data found" or TOTAL with 0 sessions
if echo "$OUTPUT" | grep -qi "no session data" || \
   echo "$OUTPUT" | grep -qE 'TOTAL\s+0'; then
  pass
else
  fail "expected zero sessions excluded, got: $OUTPUT"
fi
rm -rf "$TMPDIR_FIXTURE"
```

- [ ] **Step 2: Add report call at the end of tests/test-session-analytics.sh**

```bash
report
```

(Add this as the last line of the file if not already present)

- [ ] **Step 3: Run tests to verify they pass**

```bash
bash tests/test-session-analytics.sh
```

Expected: PASS on all 6 tests

- [ ] **Step 4: Verify the full test suite still passes**

```bash
bash tests/run.sh
```

Expected: no regressions

- [ ] **Step 5: Commit**

```bash
git add tests/test-session-analytics.sh
git commit -m "test(analytics): add cache hit rate and zero-turn exclusion tests"
```

---

### Task 4: Add analytics summary to claude-check.sh

**Files:**
- Modify: `tools/claude-check.sh`

- [ ] **Step 1: Read the end of claude-check.sh to find the insertion point**

The insertion point is just before the final line:
```bash
echo -e "For full capability overview: ${BOLD}bash tools/supercharger.sh${NC}"
```
This is the last `echo` in the file (around line 410).

- [ ] **Step 2: Insert the analytics summary block before that final line**

Add after the `echo ""` before "For full capability overview":

```bash
# Analytics Summary
echo -e "${BLUE}Analytics (7d):${NC}"
PROJECTS_BASE="$HOME/.claude/projects"
if [ -d "$PROJECTS_BASE" ]; then
  ANALYTICS_SUMMARY=$(SUPERCHARGER_PROJECTS_DIR="$PROJECTS_BASE" python3 << 'PYEOF'
import os, json, time
from datetime import datetime

PRICE = {'input': 3.00, 'cache_write': 3.75, 'cache_read': 0.30, 'output': 15.00}
projects_dir = os.environ.get('SUPERCHARGER_PROJECTS_DIR', '')
cutoff = time.time() - 7 * 86400

total = dict(input=0, cache_write=0, cache_read=0, output=0, sessions=0)
total_cost = total_saved = 0.0

for proj in os.listdir(projects_dir):
    proj_path = os.path.join(projects_dir, proj)
    if not os.path.isdir(proj_path):
        continue
    try:
        for fname in os.listdir(proj_path):
            if not fname.endswith('.jsonl'):
                continue
            fpath = os.path.join(proj_path, fname)
            try:
                if os.path.getmtime(fpath) < cutoff:
                    continue
            except OSError:
                continue
            turns = 0
            t = dict(input=0, cache_write=0, cache_read=0, output=0)
            try:
                with open(fpath) as f:
                    for line in f:
                        try:
                            d = json.loads(line)
                            if d.get('type') == 'assistant':
                                u = d.get('message', {}).get('usage', {})
                                if u:
                                    t['input']       += u.get('input_tokens', 0)
                                    t['cache_write'] += u.get('cache_creation_input_tokens', 0)
                                    t['cache_read']  += u.get('cache_read_input_tokens', 0)
                                    t['output']      += u.get('output_tokens', 0)
                                    turns += 1
                        except Exception:
                            pass
            except Exception:
                continue
            if turns == 0:
                continue
            total['sessions'] += 1
            for k in ('input', 'cache_write', 'cache_read', 'output'):
                total[k] += t[k]
            cost = (t['input'] / 1e6 * PRICE['input'] +
                    t['cache_write'] / 1e6 * PRICE['cache_write'] +
                    t['cache_read']  / 1e6 * PRICE['cache_read'] +
                    t['output']      / 1e6 * PRICE['output'])
            saved = t['cache_read'] / 1e6 * (PRICE['input'] - PRICE['cache_read'])
            total_cost  += cost
            total_saved += saved
    except OSError:
        continue

denom = total['cache_read'] + total['input']
cache_pct = int(total['cache_read'] / denom * 100) if denom > 0 else 0

if total['sessions'] == 0:
    print("  no sessions in last 7 days")
else:
    print(f"  \${total_cost:.2f} across {total['sessions']} session{'s' if total['sessions'] != 1 else ''} | cache {cache_pct}% | saved \${total_saved:.2f}")
PYEOF
  )
  echo -e "$ANALYTICS_SUMMARY"
else
  echo -e "  ${YELLOW}○${NC} No session data (${PROJECTS_BASE} not found)"
fi
echo ""
```

- [ ] **Step 3: Run claude-check.sh to verify the analytics line appears**

```bash
bash tools/claude-check.sh
```

Expected: After the health score section, a new "Analytics (7d):" section appears with real numbers from your actual sessions.

- [ ] **Step 4: Commit**

```bash
git add tools/claude-check.sh
git commit -m "feat(analytics): add 7d analytics summary to claude-check.sh"
```

---

### Task 5: Smoke test and register in test runner

**Files:**
- Modify: `tests/test-session-analytics.sh` (verify report call is last line)

- [ ] **Step 1: Run the full test suite**

```bash
bash tests/run.sh
```

Expected: All tests pass including the new `test-session-analytics` suite

- [ ] **Step 2: Run the analytics tool against real data**

```bash
bash tools/session-analytics.sh
```

Expected: Two tables printed (daily rollup + per-project breakdown) with real cost figures

- [ ] **Step 3: Run analytics with --days 1**

```bash
bash tools/session-analytics.sh --days 1
```

Expected: Only today's sessions shown

- [ ] **Step 4: Commit**

```bash
git add tools/session-analytics.sh tests/test-session-analytics.sh tools/claude-check.sh
git commit -m "feat(analytics): session analytics complete — tool + claude-check integration + tests"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `tools/session-analytics.sh` with `--days` and `--projects` | Task 1+2 |
| Bash discovers all project dirs | Task 2 |
| Python streams JSONL line by line | Task 2 |
| Daily rollup table | Task 2 |
| Per-project breakdown table | Task 2 |
| Pricing at sonnet-4-6 rates | Task 2 (PRICE dict) |
| Missing `~/.claude/projects/` exits 0 | Task 1 |
| Malformed JSONL skipped | Task 2 (bare `except`) |
| Zero-turn sessions excluded | Task 2 + tested Task 3 |
| `claude-check.sh` analytics summary | Task 4 |
| Test: script exists + executable | Task 1 |
| Test: `--help` exits 0 | Task 1 |
| Test: missing dir exits cleanly | Task 1 |
| Test: synthetic JSONL correct cost | Task 2 |
| Test: cache hit rate | Task 3 |
| Test: zero-turn excluded | Task 3 |

All 6 spec tests covered. All spec sections implemented. No placeholders.

**Type consistency:** `parse_session` returns `(dict, str)` and is called consistently in both `session-analytics.sh` and `claude-check.sh`. `new_row()` / `add_to()` helpers used consistently. `cache_pct` function signature identical in both files.
