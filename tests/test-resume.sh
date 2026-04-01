#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- Test: resume.sh with no summaries ---
begin_test "resume: no summaries shows helpful message"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"

OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" 2>&1)
echo "$OUTPUT" | grep -q "No session summaries found" && pass || fail "expected 'No session summaries found'"
teardown_test_home

# --- Test: resume.sh --list with no summaries ---
begin_test "resume: --list with no summaries"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"

OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" --list 2>&1)
echo "$OUTPUT" | grep -q "No session summaries found" && pass || fail "expected 'No session summaries found'"
teardown_test_home

# --- Test: resume.sh --list shows summaries ---
begin_test "resume: --list shows saved summaries"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/summaries"
echo "## Session Summary — 2026-04-01" > "$HOME/.claude/supercharger/summaries/2026-04-01-120000.md"
echo "**Working on:** Test feature" >> "$HOME/.claude/supercharger/summaries/2026-04-01-120000.md"

OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" --list 2>&1)
echo "$OUTPUT" | grep -q "2026-04-01-120000.md" && pass || fail "expected summary filename in output"
teardown_test_home

# --- Test: resume.sh shows latest summary ---
begin_test "resume: default shows latest summary"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/summaries"
cat > "$HOME/.claude/supercharger/summaries/2026-04-01-120000.md" << 'EOF'
## Session Summary — 2026-04-01
**Working on:** Token economy v2
**Resume with:** Continue implementing Task 8 of the token economy plan.
EOF

OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" 2>&1)
echo "$OUTPUT" | grep -q "Token economy v2" && pass || fail "expected summary content"
teardown_test_home

# --- Test: resume.sh --show displays specific summary ---
begin_test "resume: --show displays specific file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/summaries"
echo "## Test Summary" > "$HOME/.claude/supercharger/summaries/test.md"

OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" --show test.md 2>&1)
echo "$OUTPUT" | grep -q "Test Summary" && pass || fail "expected specific summary content"
teardown_test_home

# --- Test: resume.sh --show with missing file ---
begin_test "resume: --show with missing file shows error"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/summaries"

bash "$REPO_DIR/tools/resume.sh" --show nonexistent.md >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass
else
  fail "expected non-zero exit code for missing file"
fi
teardown_test_home

# --- Test: resume.sh --help shows usage ---
begin_test "resume: --help shows usage"
OUTPUT=$(bash "$REPO_DIR/tools/resume.sh" --help 2>&1)
echo "$OUTPUT" | grep -q "Usage:" && pass || fail "expected usage output"

report
