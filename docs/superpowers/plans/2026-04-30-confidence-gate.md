# Confidence Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compute a runtime confidence score (0.0–1.0) from observable signals and gate Edit/Write/destructive-Bash tool calls before execution. Three-tier action: ≥0.7 allow, 0.4–0.7 warn+allow, <0.4 deny.

**Architecture:** New PostToolUse hook tracks tool history (success/failure per session). New PreToolUse hook reads last 5 entries, applies signal-based deductions, emits warn or deny via PreToolUse v2.1.119 schema. Repetition-detector extended to drop a per-session marker file consumable by gate.

**Tech Stack:** Bash 3.2, Python 3 (signal computation, JSON), jq for input parsing, JSONL for history.

**Spec:** `docs/superpowers/specs/2026-04-30-confidence-gate-design.md`

---

## File Map

**New files:**
- `hooks/tool-history-tracker.sh` — PostToolUse, async write to `.tool-history`
- `hooks/confidence-gate.sh` — PreToolUse `Edit,Write,Bash`, sync gate
- `tests/test-confidence-gate.sh` — gate test suite
- `tests/test-tool-history-tracker.sh` — tracker test suite

**Modified:**
- `hooks/repetition-detector.sh` — add marker file write on threshold trip
- `lib/hooks.sh` — register both new hooks in base mode
- `tests/test-install.sh` — bump hook counts (76→78 full, 14→16 safe)
- `docs/HOOKS.md` — auto-regenerated

**Runtime state (in `~/.claude/supercharger/scope/`):**
- `.tool-history` — JSONL, rolling 20 entries: `{session_id, tool, success, ts}`
- `.repetition-flag-<session_id>` — empty marker file, touched when repetition-detector trips
- `.read-history` — already maintained by repetition-detector; consumed for read-before-write check

---

## Task 1: Test scaffold for tool-history-tracker

**Files:**
- Create: `tests/test-tool-history-tracker.sh`

- [ ] **Step 1: Write scaffold**

Path: `tests/test-tool-history-tracker.sh`

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-history-tracker.sh"

echo "=== tool-history-tracker Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-history-tracker: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

report
```

- [ ] **Step 2: Make executable + run, verify failure**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
chmod +x tests/test-tool-history-tracker.sh
bash tests/test-tool-history-tracker.sh
```

Expected: FAIL.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-tool-history-tracker.sh
git commit -m "test(tool-history): scaffold test file"
```

---

## Task 2: tool-history-tracker.sh — append + trim

**Files:**
- Create: `hooks/tool-history-tracker.sh`
- Modify: `tests/test-tool-history-tracker.sh`

- [ ] **Step 1: Add append + trim test**

In `tests/test-tool-history-tracker.sh`, replace the `report` line with:

```bash
begin_test "tool-history-tracker: appends success entry"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
[ -s "$HISTORY" ] && pass || fail "history not written"
teardown_test_home

begin_test "tool-history-tracker: trims to 20 entries"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
for i in $(seq 1 25); do
  echo "{\"session_id\":\"old\",\"tool\":\"Read\",\"success\":true,\"ts\":$i}"
done > "$HISTORY"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
[ "$COUNT" -le 20 ] && pass || fail "expected ≤20 entries, got $COUNT"
teardown_test_home

report
```

- [ ] **Step 2: Run tests, confirm failures**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-tool-history-tracker.sh
```

Expected: FAILs (hook missing).

- [ ] **Step 3: Implement hook**

Path: `hooks/tool-history-tracker.sh`

```bash
#!/usr/bin/env bash
# Claude Supercharger — Tool History Tracker
# Event: PostToolUse | Matcher: (none, runs on every tool)
# Appends a JSONL entry per tool call to ~/.claude/supercharger/scope/.tool-history.
# Consumed by confidence-gate.sh. Auto-trimmed to last 20 entries.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

_INPUT=$(cat)
SCOPE_DIR="$HOME/.claude/supercharger/scope"
HISTORY="$SCOPE_DIR/.tool-history"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

ENTRY=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json, time
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = d.get('session_id', 'default')
tool = d.get('tool_name', '?')
resp = d.get('tool_response') or {}
exit_code = resp.get('exit_code')
err = resp.get('error') or d.get('error')
if exit_code is not None:
    success = exit_code == 0
elif err:
    success = False
else:
    success = True
print(json.dumps({'session_id': sid, 'tool': tool, 'success': success, 'ts': int(time.time())}))
" 2>/dev/null)

[ -z "$ENTRY" ] && exit 0

printf '%s\n' "$ENTRY" >> "$HISTORY"

if [ -f "$HISTORY" ]; then
  COUNT=$(wc -l < "$HISTORY" | tr -d ' ')
  if [ "$COUNT" -gt 20 ]; then
    tail -n 20 "$HISTORY" > "$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"
  fi
fi

exit 0
```

- [ ] **Step 4: Make executable + run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
chmod +x hooks/tool-history-tracker.sh
bash tests/test-tool-history-tracker.sh
```

Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/tool-history-tracker.sh tests/test-tool-history-tracker.sh
git commit -m "feat(confidence): add tool-history-tracker (PostToolUse)"
```

---

## Task 3: tool-history-tracker — failure detection test

**Files:**
- Modify: `tests/test-tool-history-tracker.sh`

- [ ] **Step 1: Add failure-detection test before `report`**

```bash
begin_test "tool-history-tracker: marks success=false when exit_code != 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_response":{"exit_code":1}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
grep -q '"success": false' "$HISTORY" && pass || fail "expected success:false in history"
teardown_test_home
```

- [ ] **Step 2: Run, verify pass**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-tool-history-tracker.sh
```

Expected: 4 PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-tool-history-tracker.sh
git commit -m "test(tool-history): verify exit_code drives success flag"
```

---

## Task 4: Test scaffold for confidence-gate

**Files:**
- Create: `tests/test-confidence-gate.sh`

- [ ] **Step 1: Write scaffold**

Path: `tests/test-confidence-gate.sh`

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/confidence-gate.sh"

echo "=== confidence-gate Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "confidence-gate: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

report
```

- [ ] **Step 2: Make executable + run**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
chmod +x tests/test-confidence-gate.sh
bash tests/test-confidence-gate.sh
```

Expected: FAIL.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-confidence-gate.sh
git commit -m "test(confidence): scaffold test file"
```

---

## Task 5: confidence-gate skeleton

**Files:**
- Create: `hooks/confidence-gate.sh`

- [ ] **Step 1: Write skeleton hook**

Path: `hooks/confidence-gate.sh`

```bash
#!/usr/bin/env bash
# Claude Supercharger — Confidence Gate
# Event: PreToolUse | Matcher: Edit,Write,Bash
# Computes confidence score from recent tool history + signal flags;
# allows, warns, or denies tool calls based on three-tier thresholds.
# Disable: SUPERCHARGER_CONFIDENCE=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "confidence-gate" && exit 0
hook_profile_skip "confidence-gate" && exit 0

exit 0
```

- [ ] **Step 2: Make executable + run scaffold test**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
chmod +x hooks/confidence-gate.sh
bash tests/test-confidence-gate.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/confidence-gate.sh
git commit -m "feat(confidence): add confidence-gate skeleton (PreToolUse)"
```

---

## Task 6: Score computation — failure deduction

**Files:**
- Modify: `tests/test-confidence-gate.sh`
- Modify: `hooks/confidence-gate.sh`

- [ ] **Step 1: Add high-score (silent allow) and low-score (warn) tests**

Replace the `report` line in `tests/test-confidence-gate.sh` with:

```bash
begin_test "confidence-gate: high score (no failures) emits no output"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
teardown_test_home

begin_test "confidence-gate: 3 recent failures triggers warn (systemMessage)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
{"session_id":"sess1","tool":"Bash","success":true,"ts":103}
{"session_id":"sess1","tool":"Bash","success":true,"ts":104}
EOF
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'confidence' && pass || fail "expected confidence warn output, got: $OUT"
teardown_test_home

begin_test "confidence-gate: 5 recent failures triggers deny (permissionDecision)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
{"session_id":"sess1","tool":"Bash","success":false,"ts":103}
{"session_id":"sess1","tool":"Bash","success":false,"ts":104}
EOF
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny, got: $OUT"
teardown_test_home

report
```

- [ ] **Step 2: Run tests, confirm failures**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: silent-allow PASSes; warn and deny FAIL.

- [ ] **Step 3: Replace `exit 0` in `hooks/confidence-gate.sh` with scoring logic**

Replace `exit 0` at end of `hooks/confidence-gate.sh` with:

```bash
TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

case "$TOOL_NAME" in
  Edit|Write) ;;
  Bash) ;;
  *) exit 0 ;;
esac

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
TIER="${SUPERCHARGER_TIER:-standard}"
SCOPE_DIR="$HOME/.claude/supercharger/scope"
HISTORY="$SCOPE_DIR/.tool-history"
REPETITION_FLAG="$SCOPE_DIR/.repetition-flag-${SESSION_ID}"
READ_HISTORY="$SCOPE_DIR/.read-history"

TARGET_FILE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

REPETITION_FLAGGED=0
[ -f "$REPETITION_FLAG" ] && REPETITION_FLAGGED=1

READ_BEFORE_WRITE_VIOLATION=0
if [ "$TOOL_NAME" = "Edit" ] && [ -n "$TARGET_FILE" ]; then
  if [ -f "$READ_HISTORY" ]; then
    if ! grep -qF "${TARGET_FILE}	" "$READ_HISTORY" 2>/dev/null; then
      READ_BEFORE_WRITE_VIOLATION=1
    fi
  else
    READ_BEFORE_WRITE_VIOLATION=1
  fi
fi

FAILURES_LAST_5=0
if [ -f "$HISTORY" ]; then
  FAILURES_LAST_5=$(grep -F "\"session_id\": \"$SESSION_ID\"" "$HISTORY" 2>/dev/null | tail -5 | grep -c '"success": false' || echo 0)
fi

SCORE_RAW=$(python3 -c "
fail = int('$FAILURES_LAST_5')
rbw = int('$READ_BEFORE_WRITE_VIOLATION')
rep = int('$REPETITION_FLAGGED')
score = 1.0 - (0.20 * fail) - (0.30 * rbw) - (0.20 * rep)
if score < 0.0: score = 0.0
if score > 1.0: score = 1.0
print(f'{score:.2f}')
")

REASON_PARTS=()
[ "$FAILURES_LAST_5" -gt 0 ] && REASON_PARTS+=("$FAILURES_LAST_5 recent failures")
[ "$READ_BEFORE_WRITE_VIOLATION" = "1" ] && REASON_PARTS+=("read-before-write violation")
[ "$REPETITION_FLAGGED" = "1" ] && REASON_PARTS+=("repetition flagged")

REASON_STR=""
if [ "${#REASON_PARTS[@]}" -gt 0 ]; then
  REASON_STR=$(IFS=', '; echo "${REASON_PARTS[*]}")
fi

ABOVE_07=$(python3 -c "print(1 if float('$SCORE_RAW') >= 0.7 else 0")
ABOVE_04=$(python3 -c "print(1 if float('$SCORE_RAW') >= 0.4 else 0")

if [ "$ABOVE_07" = "1" ]; then
  exit 0
fi

case "$TIER" in
  minimal)
    if [ "$ABOVE_04" = "1" ]; then
      MSG="[conf:${SCORE_RAW}→warn]"
    else
      MSG="[conf:${SCORE_RAW}→deny]"
    fi
    ;;
  lean)
    MSG="confidence ${SCORE_RAW}: ${REASON_STR}"
    ;;
  *)
    if [ "$ABOVE_04" = "1" ]; then
      MSG="Confidence gate: ${SCORE_RAW} (warn)
  ${REASON_STR}
Proceed with caution."
    else
      MSG="Confidence gate denied $TOOL_NAME call (score ${SCORE_RAW}):
  ${REASON_STR}"
    fi
    ;;
esac

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

if [ "$ABOVE_04" = "1" ]; then
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$MSG_JSON"
fi
exit 0
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/confidence-gate.sh tests/test-confidence-gate.sh
git commit -m "feat(confidence): score computation, three-tier action"
```

---

## Task 7: Read-before-write deduction test

**Files:**
- Modify: `tests/test-confidence-gate.sh`

- [ ] **Step 1: Add test before `report`**

```bash
begin_test "confidence-gate: Edit on unread file triggers read-before-write deduction"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
echo '' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/never-read.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'read-before-write' && pass || fail "expected read-before-write reason, got: $OUT"
teardown_test_home

begin_test "confidence-gate: Edit on previously-read file does NOT trigger violation"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
printf '/tmp/known.txt\t12345\n' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow on known file, got: $OUT"
teardown_test_home
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: 6 PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-confidence-gate.sh
git commit -m "test(confidence): read-before-write deduction"
```

---

## Task 8: Repetition marker — extend repetition-detector.sh

**Files:**
- Modify: `hooks/repetition-detector.sh:55-62` (loop detection block)

- [ ] **Step 1: Read current loop detection block**

```bash
sed -n '50,70p' /Users/radiustheme/GithubRepos/claude-supercharger/hooks/repetition-detector.sh
```

Locate the block that emits `[Supercharger] repetition-detector: loop '...' repeated Nx` (around line 59).

- [ ] **Step 2: Add marker file write next to the warning emission**

Use Edit tool to find:
```
      echo "[Supercharger] repetition-detector: loop '${SHORT}' repeated ${COUNT}x" >&2
```

And replace with:
```
      echo "[Supercharger] repetition-detector: loop '${SHORT}' repeated ${COUNT}x" >&2
      SESSION_ID_REP=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
      touch "$SCOPE_DIR/.repetition-flag-${SESSION_ID_REP}" 2>/dev/null || true
```

- [ ] **Step 3: Add test for marker write**

Append to `tests/test-confidence-gate.sh` before `report`:

```bash
begin_test "confidence-gate: repetition flag deducts from score"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
echo '' > "$HOME/.claude/supercharger/scope/.read-history"
touch "$HOME/.claude/supercharger/scope/.repetition-flag-sess1"
printf '/tmp/known.txt\t12345\n' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'repetition flagged' && pass || fail "expected repetition reason, got: $OUT"
teardown_test_home
```

Note: score with only repetition (1.0 − 0.20 = 0.80) is above 0.7 threshold and would silent-allow. Need to nudge into warn zone. Adjust test fixture to add 1 failure plus repetition: 1.0 − 0.20 (1 failure) − 0.20 (repetition) = 0.60 → warn.

Replace the test fixture above with:

```bash
begin_test "confidence-gate: repetition flag + 1 failure triggers warn"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
echo '{"session_id":"sess1","tool":"Bash","success":false,"ts":100}' > "$HISTORY"
printf '/tmp/known.txt\t12345\n' > "$HOME/.claude/supercharger/scope/.read-history"
touch "$HOME/.claude/supercharger/scope/.repetition-flag-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'repetition flagged' && pass || fail "expected repetition reason, got: $OUT"
teardown_test_home
```

- [ ] **Step 4: Run all tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: 7 PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/repetition-detector.sh tests/test-confidence-gate.sh
git commit -m "feat(confidence): repetition-detector drops session marker; gate consumes it"
```

---

## Task 9: Bash non-destructive bypass

**Files:**
- Modify: `hooks/confidence-gate.sh`
- Modify: `tests/test-confidence-gate.sh`

- [ ] **Step 1: Add bypass test**

Append to `tests/test-confidence-gate.sh` before `report`:

```bash
begin_test "confidence-gate: non-destructive Bash bypasses gate"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
{"session_id":"sess1","tool":"Bash","success":false,"ts":103}
{"session_id":"sess1","tool":"Bash","success":false,"ts":104}
EOF
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow for ls, got: $OUT"
teardown_test_home

begin_test "confidence-gate: destructive Bash gates with low score"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
EOF
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'confidence' && pass || fail "expected gate output for rm, got: $OUT"
teardown_test_home
```

- [ ] **Step 2: Update Bash classification in `hooks/confidence-gate.sh`**

Find the case block:

```bash
case "$TOOL_NAME" in
  Edit|Write) ;;
  Bash) ;;
  *) exit 0 ;;
esac
```

Replace with:

```bash
case "$TOOL_NAME" in
  Edit|Write) ;;
  Bash)
    BASH_CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$BASH_CMD" ] && exit 0
    DESTRUCTIVE=$(printf '%s' "$BASH_CMD" | python3 -c "
import sys, re
cmd = sys.stdin.read()
patterns = [
    r'\\brm\\s+(-[a-zA-Z]*r[a-zA-Z]*\\s|--recursive\\s)',
    r'\\bgit\\s+push\\s+.*--force\\b',
    r'\\bgit\\s+reset\\s+--hard\\b',
    r'\\bgit\\s+clean\\s+-[a-zA-Z]*f',
    r'\\bdrop\\s+(table|database|schema)\\b',
    r'\\bterraform\\s+destroy\\b',
    r'\\bdocker\\s+system\\s+prune\\b',
    r'\\bnpm\\s+publish\\b',
    r'\\b(aws|gcloud)\\s+.*delete\\b',
]
for p in patterns:
    if re.search(p, cmd, re.IGNORECASE):
        print('1')
        sys.exit(0)
print('0')
" 2>/dev/null)
    [ "$DESTRUCTIVE" = "0" ] && exit 0
    ;;
  *) exit 0 ;;
esac
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: 9 PASS.

- [ ] **Step 4: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add hooks/confidence-gate.sh tests/test-confidence-gate.sh
git commit -m "feat(confidence): destructive-bash classifier; non-destructive bypass"
```

---

## Task 10: Disable flag + tier output tests

**Files:**
- Modify: `tests/test-confidence-gate.sh`

- [ ] **Step 1: Add disable + tier tests**

Append before `report`:

```bash
begin_test "confidence-gate: SUPERCHARGER_CONFIDENCE=0 disables gate"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
{"session_id":"sess1","tool":"Bash","success":false,"ts":103}
{"session_id":"sess1","tool":"Bash","success":false,"ts":104}
EOF
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(SUPERCHARGER_CONFIDENCE=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"
teardown_test_home

begin_test "confidence-gate: minimal tier emits short tag"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id":"sess1","tool":"Bash","success":false,"ts":100}
{"session_id":"sess1","tool":"Bash","success":false,"ts":101}
{"session_id":"sess1","tool":"Bash","success":false,"ts":102}
EOF
echo '' > "$HOME/.claude/supercharger/scope/.read-history"
printf '/tmp/known.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(SUPERCHARGER_TIER=minimal bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'conf:' && pass || fail "minimal tag missing: $OUT"
teardown_test_home
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-confidence-gate.sh
```

Expected: 11 PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-confidence-gate.sh
git commit -m "test(confidence): disable flag and minimal-tier output"
```

---

## Task 11: Register both hooks in lib/hooks.sh

**Files:**
- Modify: `lib/hooks.sh:31-35` (base mode SessionStart/PreToolUse area)

- [ ] **Step 1: Read context around base hooks**

```bash
sed -n '24,36p' /Users/radiustheme/GithubRepos/claude-supercharger/lib/hooks.sh
```

- [ ] **Step 2: Insert two new hook lines after Stop|*|lesson-record line**

Find:
```
  hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
  hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
```

Replace with:
```
  hooks+=("Stop|*|${hooks_dir}/lesson-record.sh|async")
  hooks+=("UserPromptSubmit||${hooks_dir}/lesson-recall.sh|")
  hooks+=("PostToolUse||${hooks_dir}/tool-history-tracker.sh|async")
  hooks+=("PreToolUse|Edit,Write,Bash|${hooks_dir}/confidence-gate.sh|")
```

- [ ] **Step 3: Verify**

```bash
grep -n 'confidence-gate\|tool-history-tracker' lib/hooks.sh
```

Expected: 2 matches in base section.

- [ ] **Step 4: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add lib/hooks.sh
git commit -m "feat(confidence): register confidence-gate and tool-history-tracker hooks"
```

---

## Task 12: Bump test-install hook counts

**Files:**
- Modify: `tests/test-install.sh:71,144,177`

- [ ] **Step 1: Bump full mode count (76 → 78)**

```bash
sed -i.bak 's/-eq 76/-eq 78/g; s/expected 76 hooks/expected 78 hooks/g; s/= 76 hooks/= 78 hooks/g; s/-eq 14/-eq 16/g; s/expected 14 hooks/expected 16 hooks/g' tests/test-install.sh && rm tests/test-install.sh.bak
```

- [ ] **Step 2: Run install tests**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-install.sh
```

Expected: 11 PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add tests/test-install.sh
git commit -m "test(install): bump hook counts for confidence gate (76→78 full, 14→16 safe)"
```

---

## Task 13: Regenerate HOOKS.md

**Files:**
- Modify: `docs/HOOKS.md` (auto-regenerated)

- [ ] **Step 1: Regenerate**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tools/list-hooks.sh > docs/HOOKS.md
```

- [ ] **Step 2: Verify**

```bash
grep -c 'confidence-gate\|tool-history-tracker' /Users/radiustheme/GithubRepos/claude-supercharger/docs/HOOKS.md
```

Expected: 2.

- [ ] **Step 3: Commit**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
git add docs/HOOKS.md
git commit -m "docs: regenerate HOOKS.md to include confidence hooks"
```

---

## Task 14: Full sweep + release decision

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/run.sh 2>&1 | tail -3
```

Expected: `Total: 778+ passed, 0 failed` (763 baseline + 4 history tracker + 11 confidence gate).

- [ ] **Step 2: If failures, fix before release**

Most likely failure modes:
- Edit-tool input shape mismatch (`tool_input.file_path` vs other paths)
- jq parsing of history JSONL with unusual session_id values
- repetition-detector marker not written when expected

Fix the underlying issue. Don't skip tests.

- [ ] **Step 3: Optional release v2.3.53**

If user wants release: bump version in `lib/utils.sh`, `tools/supercharger.sh`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`. Add changelog entry. Commit `chore: release v2.3.53` and tag.

If user defers release: stop after Step 1.

---

## Self-Review Notes

**Spec coverage check:**
- D1 hook-computed → Tasks 2, 6 (no Claude self-assessment surface)
- D2 gate Edit + Write + destructive Bash → Task 6 (Edit/Write), Task 9 (Bash classifier)
- D3 signals: failures + read-before-write + repetition → Task 6, 7, 8
- D4 three-tier action → Task 6 (full tier branching)
- D5 window: last 5 tool calls → Task 6 (`tail -5` then count)
- D6 state in `~/.claude/supercharger/scope/.tool-history` → Task 2 (creation/trim)
- D7 tier-scaled output → Task 6 (default standard) + Task 10 (minimal tier verified)
- D8 disable flag → Task 10
- Repetition-detector marker write → Task 8
- Hook registration → Task 11
- HOOKS.md regen → Task 13

**Performance acceptance criterion** "<50ms p95" — not separately tested; existing `tests/test-hook-perf.sh` covers it on next CI run.

**Type/name consistency:**
- Field names in `.tool-history`: `session_id`, `tool`, `success`, `ts` — used identically in tracker (Task 2) and gate (Task 6) ✓
- Env vars: `SUPERCHARGER_CONFIDENCE`, `SUPERCHARGER_TIER`, `SUPERCHARGER_NO_DEDUP` consistent ✓
- File paths: `~/.claude/supercharger/scope/.tool-history`, `.repetition-flag-<session_id>`, `.read-history` consistent throughout ✓
- Hook names: `confidence-gate.sh`, `tool-history-tracker.sh` consistent ✓
- Score formula constants (0.20, 0.30, 0.20) match spec ✓

**Known gap:** the score-formula `python3 -c` invocation in Task 6 has unbalanced parentheses in the `print(1 if float('$SCORE_RAW') >= 0.7 else 0` lines (missing closing paren). The implementer should write `print(1 if float('$SCORE_RAW') >= 0.7 else 0)` — note the closing paren before the `"`. Same for the 0.4 line.
