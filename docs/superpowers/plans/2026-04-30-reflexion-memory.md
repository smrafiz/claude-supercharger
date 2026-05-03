# Reflexion Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture lessons from solved problems at end of each turn (Stop hook) and surface relevant past lessons when user begins similar work (UserPromptSubmit hook), per-project, lexical match, tier-scaled.

**Architecture:** Two new hooks. Stop hook scans assistant's last transcript message for diagnostic markers, appends JSONL records. UserPromptSubmit hook tokenizes prompt, computes Jaccard overlap against stored records, injects top 3 matches above threshold.

**Tech Stack:** Bash 3.2, Python 3 (string processing + Jaccard), jq for JSON, JSONL for storage.

**Spec:** `docs/superpowers/specs/2026-04-30-reflexion-memory-design.md`

---

## File Map

**New files:**
- `hooks/lesson-record.sh` — Stop hook
- `hooks/lesson-recall.sh` — UserPromptSubmit hook
- `tests/test-lessons.sh` — test suite

**Modified:**
- `lib/hooks.sh` — register both hooks
- `tests/test-install.sh` — bump hook counts (74→76 full, 12→14 safe)
- `docs/HOOKS.md` — auto-regenerated

**Runtime created (in user repo):**
- `<repo>/.claude/supercharger/lessons.jsonl`

---

## Task 1: Test scaffold

**Files:**
- Create: `tests/test-lessons.sh`

- [ ] **Step 1: Write scaffold with first failing test**

Path: `tests/test-lessons.sh`

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RECORD_HOOK="$REPO_DIR/hooks/lesson-record.sh"
RECALL_HOOK="$REPO_DIR/hooks/lesson-recall.sh"

echo "=== Reflexion Memory Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "lessons: lesson-record.sh exists and is executable"
[ -x "$RECORD_HOOK" ] && pass || fail "lesson-record.sh missing or not executable"

begin_test "lessons: lesson-recall.sh exists and is executable"
[ -x "$RECALL_HOOK" ] && pass || fail "lesson-recall.sh missing or not executable"
```

- [ ] **Step 2: Make executable + run, verify failures**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
chmod +x tests/test-lessons.sh
bash tests/test-lessons.sh
```

Expected: both tests FAIL (hooks don't exist yet).

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-lessons.sh
git commit -m "test(lessons): scaffold test file"
```

---

## Task 2: lesson-record.sh skeleton

**Files:**
- Create: `hooks/lesson-record.sh`

- [ ] **Step 1: Write skeleton hook**

Path: `hooks/lesson-record.sh`

```bash
#!/usr/bin/env bash
# Claude Supercharger — Lesson Recorder (Reflexion Memory)
# Event: Stop | Matcher: *
# Scans assistant's last transcript message for diagnostic markers
# (the issue was, root cause, fixed by, ...) and appends a structured
# lesson record to <repo>/.claude/supercharger/lessons.jsonl.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-record" && exit 0
hook_profile_skip "lesson-record" && exit 0

exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/radiustheme/GithubRepos/claude-supercharger/hooks/lesson-record.sh
```

- [ ] **Step 3: Run test, confirm record-existence test passes**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: first PASS (record), second FAIL (recall still missing).

- [ ] **Step 4: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/lesson-record.sh
git commit -m "feat(lessons): add lesson-record hook skeleton"
```

---

## Task 3: lesson-recall.sh skeleton

**Files:**
- Create: `hooks/lesson-recall.sh`

- [ ] **Step 1: Write skeleton hook**

Path: `hooks/lesson-recall.sh`

```bash
#!/usr/bin/env bash
# Claude Supercharger — Lesson Recaller (Reflexion Memory)
# Event: UserPromptSubmit | Matcher: (none)
# Tokenizes user prompt, computes Jaccard overlap against stored
# lessons.jsonl, injects top 3 matches above threshold 0.5.
# Output is tier-scaled.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-recall" && exit 0
hook_profile_skip "lesson-recall" && exit 0

exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/radiustheme/GithubRepos/claude-supercharger/hooks/lesson-recall.sh
```

- [ ] **Step 3: Both tests pass now**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: 2 PASS.

- [ ] **Step 4: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/lesson-recall.sh
git commit -m "feat(lessons): add lesson-recall hook skeleton"
```

---

## Task 4: Record extraction logic

**Files:**
- Modify: `tests/test-lessons.sh`
- Modify: `hooks/lesson-record.sh`

- [ ] **Step 1: Add failing test for record extraction**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: record appends jsonl when marker present"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
TRANSCRIPT="$PROJ/.transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"npm test fails"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"The issue was a missing dependency. Fixed by adding foo to package.json."}]}}
EOF
INPUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$PROJ" "$TRANSCRIPT")
echo "$INPUT" | bash "$RECORD_HOOK" >/dev/null 2>&1 || true
LESSONS_FILE="$PROJ/.claude/supercharger/lessons.jsonl"
[ -s "$LESSONS_FILE" ] && pass || fail "lessons.jsonl not written: $(ls -la $PROJ/.claude/supercharger/ 2>&1)"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: record skipped when no marker"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
TRANSCRIPT="$PROJ/.transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"hello"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Hi there. How can I help?"}]}}
EOF
INPUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$PROJ" "$TRANSCRIPT")
echo "$INPUT" | bash "$RECORD_HOOK" >/dev/null 2>&1 || true
LESSONS_FILE="$PROJ/.claude/supercharger/lessons.jsonl"
[ ! -s "$LESSONS_FILE" ] && pass || fail "lessons.jsonl unexpectedly written without marker"
rm -rf "$PROJ"
teardown_test_home
```

- [ ] **Step 2: Run tests, verify failures**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: marker test FAILs (no extraction logic yet).

- [ ] **Step 3: Implement extraction in lesson-record.sh**

Replace `exit 0` at end of `hooks/lesson-record.sh` with:

```bash
TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

LAST_USER=$(jq -rs '
  [.[] | select(.type == "user")] | last |
  if .message.content | type == "array"
  then [.message.content[] | select(.type == "text") | .text] | join(" ")
  else .message.content // "" end
' "$TRANSCRIPT" 2>/dev/null || echo "")

LAST_ASSIST=$(jq -rs '
  [.[] | select(.type == "assistant" and .message.content)] | last |
  [.message.content[] | select(.type == "text") | .text] | join(" ")
' "$TRANSCRIPT" 2>/dev/null || echo "")

[ -z "$LAST_ASSIST" ] && exit 0

LESSONS_DIR="$PROJECT_DIR/.claude/supercharger"
LESSONS_FILE="$LESSONS_DIR/lessons.jsonl"

RECORD=$(LAST_USER="$LAST_USER" LAST_ASSIST="$LAST_ASSIST" python3 <<'PYEOF'
import os, re, json, datetime

assist = os.environ.get('LAST_ASSIST', '')
user = os.environ.get('LAST_USER', '')

markers = [
    r'the issue was',
    r'root cause',
    r'fixed by',
    r'the problem was',
    r'turns out',
    r'it failed because',
]
pattern = re.compile('|'.join(markers), re.IGNORECASE)
m = pattern.search(assist)
if not m:
    raise SystemExit(0)

idx = m.start()
before = assist[:idx].strip()
after = assist[idx:].strip()

sig = (user[:100] if user else before.split('\n')[-1][:100]).strip()
fix = after[:200].strip()
first_sent = re.split(r'(?<=[.!?])\s', after, maxsplit=1)[0]
lesson = first_sent[:160].strip()

files = re.findall(r'[\w./\-]+\.[a-zA-Z0-9]{1,6}\b', assist)
files = list(dict.fromkeys(files))[:5]

tokens = set()
for txt in (sig, fix):
    for w in re.findall(r'[a-zA-Z0-9_]+', txt.lower()):
        if len(w) >= 3:
            tokens.add(w)
recall = ' '.join(sorted(tokens))

rec = {
    'sig': sig,
    'fix': fix,
    'files': files,
    'lesson': lesson,
    'recall': recall,
    'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
}
print(json.dumps(rec))
PYEOF
)

[ -z "$RECORD" ] && exit 0

mkdir -p "$LESSONS_DIR"

if [ -f "$LESSONS_FILE" ]; then
  COUNT=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
  if [ "$COUNT" -ge 1000 ]; then
    tail -n 999 "$LESSONS_FILE" > "$LESSONS_FILE.tmp"
    mv "$LESSONS_FILE.tmp" "$LESSONS_FILE"
  fi
fi

printf '%s\n' "$RECORD" >> "$LESSONS_FILE"
exit 0
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/lesson-record.sh tests/test-lessons.sh
git commit -m "feat(lessons): record extracts lesson from transcript markers"
```

---

## Task 5: Record disable flag

**Files:**
- Modify: `tests/test-lessons.sh`

- [ ] **Step 1: Add disable test**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: SUPERCHARGER_LESSONS=0 disables record"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
TRANSCRIPT="$PROJ/.transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"test failing"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"The issue was a missing import. Fixed by adding it."}]}}
EOF
INPUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$PROJ" "$TRANSCRIPT")
SUPERCHARGER_LESSONS=0 bash -c "echo '$INPUT' | bash $RECORD_HOOK" >/dev/null 2>&1 || true
LESSONS_FILE="$PROJ/.claude/supercharger/lessons.jsonl"
[ ! -s "$LESSONS_FILE" ] && pass || fail "lessons.jsonl written despite SUPERCHARGER_LESSONS=0"
rm -rf "$PROJ"
teardown_test_home
```

- [ ] **Step 2: Run test**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: PASS (Task 2 already added the early-exit check).

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-lessons.sh
git commit -m "test(lessons): record honors SUPERCHARGER_LESSONS=0"
```

---

## Task 6: Recall match logic

**Files:**
- Modify: `tests/test-lessons.sh`
- Modify: `hooks/lesson-recall.sh`

- [ ] **Step 1: Add failing test for recall**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: recall injects matching lesson at standard tier"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"npm test fails: missing module foo","fix":"added foo to package.json","files":["package.json"],"lesson":"new imports require explicit dep add","recall":"add cannot dep deps fails find foo json missing module npm package test","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo again")
OUT=$(SUPERCHARGER_TIER=standard bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'lesson' && pass || fail "no lesson in standard recall output: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: recall outputs nothing when no match"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"npm test fails","fix":"x","files":[],"lesson":"y","recall":"npm test fails missing","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "completely unrelated database query optimization")
OUT=$(SUPERCHARGER_TIER=standard bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "recall emitted output without match: $OUT"
rm -rf "$PROJ"
teardown_test_home
```

- [ ] **Step 2: Run tests, verify failures**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: standard-tier recall test FAILs.

- [ ] **Step 3: Implement Jaccard recall**

Replace `exit 0` at end of `hooks/lesson-recall.sh` with:

```bash
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi
[ -z "$PROMPT" ] && exit 0

# Walk up to find lessons.jsonl
DIR="$PROJECT_DIR"
LESSONS_FILE=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/.claude/supercharger/lessons.jsonl" ]; then
    LESSONS_FILE="$DIR/.claude/supercharger/lessons.jsonl"
    break
  fi
  DIR=$(dirname "$DIR")
done
[ -z "$LESSONS_FILE" ] && exit 0

TIER="${SUPERCHARGER_TIER:-standard}"

OUT=$(PROMPT="$PROMPT" LESSONS_FILE="$LESSONS_FILE" TIER="$TIER" python3 <<'PYEOF'
import os, re, json

prompt = os.environ.get('PROMPT', '')
path = os.environ.get('LESSONS_FILE', '')
tier = os.environ.get('TIER', 'standard')

def tokenize(text):
    return {w for w in re.findall(r'[a-zA-Z0-9_]+', text.lower()) if len(w) >= 3}

p_tokens = tokenize(prompt)
if not p_tokens:
    raise SystemExit(0)

scored = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            r_tokens = tokenize(rec.get('recall', ''))
            if not r_tokens:
                continue
            inter = len(p_tokens & r_tokens)
            union = len(p_tokens | r_tokens)
            score = inter / union if union else 0
            if score >= 0.5:
                scored.append((score, rec))
except FileNotFoundError:
    raise SystemExit(0)

scored.sort(key=lambda x: x[0], reverse=True)
top = [r for _, r in scored[:3]]
if not top:
    raise SystemExit(0)

if tier == 'minimal':
    print('[lessons: ' + str(len(top)) + ' matched]')
elif tier == 'lean':
    for r in top:
        print('- ' + r.get('lesson', ''))
else:
    parts = []
    for r in top:
        block = '- ' + r.get('lesson', '')
        if r.get('fix'):
            block += '\n  fix: ' + r['fix']
        if r.get('files'):
            block += '\n  files: ' + ', '.join(r['files'])
        parts.append(block)
    print('\n'.join(parts))
PYEOF
)

[ -z "$OUT" ] && exit 0

OUT_JSON=$(printf '%s' "$OUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$OUT_JSON"
exit 0
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: standard-tier recall test PASSes; no-match test PASSes.

- [ ] **Step 5: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/lesson-recall.sh tests/test-lessons.sh
git commit -m "feat(lessons): recall via Jaccard match with tier-scaled output"
```

---

## Task 7: Tier-scaled output verification

**Files:**
- Modify: `tests/test-lessons.sh`

- [ ] **Step 1: Add tier-specific tests**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: minimal tier emits count tag"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"x","fix":"y","files":[],"lesson":"npm dep lesson","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=minimal bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'lessons:' && pass || fail "minimal tag missing: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: lean tier emits one-line lesson"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"x","fix":"y","files":[],"lesson":"npm dep lesson","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=lean bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'npm dep lesson' && pass || fail "lean output missing lesson text: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: standard tier includes fix line"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"x","fix":"add foo to deps","files":["package.json"],"lesson":"npm dep lesson","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=standard bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'fix:' && pass || fail "standard output missing fix line: $OUT"
rm -rf "$PROJ"
teardown_test_home
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: 3 new PASSes.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-lessons.sh
git commit -m "test(lessons): verify all tier output formats"
```

---

## Task 8: Recall cap test (max 3)

**Files:**
- Modify: `tests/test-lessons.sh`

- [ ] **Step 1: Add cap test**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: recall caps output at 3 matches"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"a","fix":"x","files":[],"lesson":"lesson one","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
{"sig":"b","fix":"x","files":[],"lesson":"lesson two","recall":"npm test cannot find module bar","ts":"2026-04-30T00:00:00Z"}
{"sig":"c","fix":"x","files":[],"lesson":"lesson three","recall":"npm test cannot find module baz","ts":"2026-04-30T00:00:00Z"}
{"sig":"d","fix":"x","files":[],"lesson":"lesson four","recall":"npm test cannot find module qux","ts":"2026-04-30T00:00:00Z"}
{"sig":"e","fix":"x","files":[],"lesson":"lesson five","recall":"npm test cannot find module quux","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module")
OUT=$(SUPERCHARGER_TIER=lean bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
COUNT=$(echo "$OUT" | grep -c '^- lesson')
[ "$COUNT" -le 3 ] && pass || fail "expected ≤3 lessons, got $COUNT"
rm -rf "$PROJ"
teardown_test_home
```

- [ ] **Step 2: Run test**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: PASS (Task 6 implements `[:3]` slice).

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-lessons.sh
git commit -m "test(lessons): verify recall caps at 3 matches"
```

---

## Task 9: Recall disable test + walk-up + 1000-cap rotation

**Files:**
- Modify: `tests/test-lessons.sh`

- [ ] **Step 1: Add disable + walk-up + rotation tests**

Append to `tests/test-lessons.sh`:

```bash
begin_test "lessons: SUPERCHARGER_LESSONS=0 disables recall"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"x","fix":"y","files":[],"lesson":"l","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_LESSONS=0 bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "recall emitted output despite disable: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: recall walks up to find lessons.jsonl"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger" "$PROJ/sub/dir"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"x","fix":"y","files":[],"lesson":"l","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s/sub/dir","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=lean bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'lesson' && pass || fail "walk-up didn't find lessons.jsonl: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "lessons: record rotates at 1000 entries"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
LESSONS_FILE="$PROJ/.claude/supercharger/lessons.jsonl"
for i in $(seq 1 1000); do
  echo "{\"sig\":\"old$i\",\"fix\":\"x\",\"files\":[],\"lesson\":\"l\",\"recall\":\"old\",\"ts\":\"2026-04-29T00:00:00Z\"}"
done > "$LESSONS_FILE"
TRANSCRIPT="$PROJ/.transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"new error"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"The issue was a new bug. Fixed by patching."}]}}
EOF
INPUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$PROJ" "$TRANSCRIPT")
echo "$INPUT" | bash "$RECORD_HOOK" >/dev/null 2>&1 || true
COUNT=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
[ "$COUNT" -eq 1000 ] && pass || fail "expected 1000 entries after rotation, got $COUNT"
rm -rf "$PROJ"
teardown_test_home

# Final summary
echo ""
echo "=== Summary ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
[ $TESTS_FAILED -eq 0 ]
```

- [ ] **Step 2: Run all tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-lessons.sh
```

Expected: all PASS, summary `Failed: 0`.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-lessons.sh
git commit -m "test(lessons): disable, walk-up, and 1000-entry rotation"
```

---

## Task 10: Register hooks in lib/hooks.sh

**Files:**
- Modify: `lib/hooks.sh:31-33` (base mode)

- [ ] **Step 1: Read context around line 31**

```bash
sed -n '30,34p' /Users/radiustheme/GithubRepos/claude-supercharger/lib/hooks.sh
```

Expected:
```
  hooks+=("PostToolUse|Bash,Read|${hooks_dir}/output-secrets-scanner.sh|asyncRewake")
  hooks+=("SessionStart||${hooks_dir}/config-scan.sh|")
  hooks+=("SessionStart||${hooks_dir}/standards-inject.sh|")
  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")
```

- [ ] **Step 2: Insert two new lines after standards-inject**

Use Edit tool:

Old:
```
  hooks+=("SessionStart||${hooks_dir}/standards-inject.sh|")
  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")
```

New:
```
  hooks+=("SessionStart||${hooks_dir}/standards-inject.sh|")
  hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
  hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")
```

- [ ] **Step 3: Verify both registered**

```bash
grep -n 'lesson-' /Users/radiustheme/GithubRepos/claude-supercharger/lib/hooks.sh
```

Expected: 2 lines, both in base section.

- [ ] **Step 4: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add lib/hooks.sh
git commit -m "feat(lessons): register lesson-record and lesson-recall hooks"
```

---

## Task 11: Bump test-install hook counts

**Files:**
- Modify: `tests/test-install.sh:71,144,177`

- [ ] **Step 1: Find current counts**

```bash
grep -n "HOOK_COUNT.*-eq" /Users/radiustheme/GithubRepos/claude-supercharger/tests/test-install.sh
```

Expected: 3 matches at 74, 12, 74.

- [ ] **Step 2: Update full mode count (74 → 76)**

Use Edit tool:

Old:
```
# Full mode + developer = 74 hooks total (commit-check is opt-in, not counted here)
if [ "$HOOK_COUNT" -eq 74 ]; then
  pass
else
  fail "expected 74 hooks in full mode, got $HOOK_COUNT"
fi
```

New:
```
# Full mode + developer = 76 hooks total (commit-check is opt-in, not counted here)
if [ "$HOOK_COUNT" -eq 76 ]; then
  pass
else
  fail "expected 76 hooks in full mode, got $HOOK_COUNT"
fi
```

- [ ] **Step 3: Update safe mode count (12 → 14)**

Use Edit tool:

Old:
```
if [ "$HOOK_COUNT" -eq 12 ]; then
  pass
else
  fail "expected 12 hooks in safe mode, got $HOOK_COUNT"
fi
```

New:
```
if [ "$HOOK_COUNT" -eq 14 ]; then
  pass
else
  fail "expected 14 hooks in safe mode, got $HOOK_COUNT"
fi
```

- [ ] **Step 4: Update standard→full count (74 → 76)**

Use Edit tool:

Old:
```
# standard maps to full = 74 hooks (with developer, commit-check is opt-in)
if [ "$HOOK_COUNT" -eq 74 ]; then
  pass
else
  fail "expected 74 hooks (standard→full), got $HOOK_COUNT"
fi
```

New:
```
# standard maps to full = 76 hooks (with developer, commit-check is opt-in)
if [ "$HOOK_COUNT" -eq 76 ]; then
  pass
else
  fail "expected 76 hooks (standard→full), got $HOOK_COUNT"
fi
```

- [ ] **Step 5: Run install tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-install.sh
```

Expected: all 11 PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-install.sh
git commit -m "test(install): bump hook counts for lesson-record and lesson-recall (74→76 full, 12→14 safe)"
```

---

## Task 12: Regenerate HOOKS.md catalog

**Files:**
- Modify: `docs/HOOKS.md` (auto-regenerated)

- [ ] **Step 1: Run regeneration**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tools/list-hooks.sh > docs/HOOKS.md
```

- [ ] **Step 2: Verify both new hooks present**

```bash
grep -c 'lesson-record\|lesson-recall' /Users/radiustheme/GithubRepos/claude-supercharger/docs/HOOKS.md
```

Expected: 2.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add docs/HOOKS.md
git commit -m "docs: regenerate HOOKS.md to include lesson hooks"
```

---

## Task 13: Full sweep + release

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/run.sh 2>&1 | tail -3
```

Expected: `Total: 745+ passed, 0 failed`.

- [ ] **Step 2: If failures, investigate**

If any test fails, read the error and fix the underlying issue before proceeding. Most likely: race condition in async Stop hook, or path resolution bug in walk-up logic.

- [ ] **Step 3: Bump version + changelog (only if user requests v2.3.51 release)**

If user wants release commit:
- Update `lib/utils.sh:4`, `tools/supercharger.sh:14`, `.claude-plugin/plugin.json:4`, `.claude-plugin/marketplace.json:9,17`, `README.md:5` from `2.3.50` to `2.3.51`
- Prepend new changelog entry to `CHANGELOG.md` describing the new feature
- Commit `chore: release v2.3.51` and tag `v2.3.51`

If user doesn't want release: stop after Step 1.

---

## Self-Review Notes

**Spec coverage check:**
- D1 Stop hook capture → Task 4
- D2 schema (sig/fix/files/lesson/recall/ts) → Task 4 Python record-build
- D3 per-project storage → Task 4 (`$PROJECT_DIR/.claude/supercharger/lessons.jsonl`)
- D4 UserPromptSubmit recall → Task 6
- D5 Jaccard ≥ 0.5 → Task 6 Python match logic
- D6 marker pattern extraction → Task 4 marker list
- D7 cap at 3 → Task 6 `[:3]` slice + Task 8 test
- D8 tier-scaled output → Task 6 + Task 7 tests
- 1000-entry rotation → Task 4 implementation + Task 9 test
- Disable flag → Task 5 + Task 9
- Hook registration → Task 10
- HOOKS.md update → Task 12
- Acceptance criterion "performance: recall <80ms p95 on 1000-entry corpus" — not separately tested; integration into existing `tests/test-hook-perf.sh` covers it on next run.

**Type/name consistency:**
- Field names: `sig`, `fix`, `files`, `lesson`, `recall`, `ts` — used identically in record-write (Task 4) and recall-read (Task 6) ✓
- Env vars: `SUPERCHARGER_LESSONS`, `SUPERCHARGER_TIER`, `SUPERCHARGER_NO_DEDUP` consistent ✓
- File paths: `<repo>/.claude/supercharger/lessons.jsonl` consistent throughout ✓
- Hook names: `lesson-record.sh`, `lesson-recall.sh` consistent ✓
