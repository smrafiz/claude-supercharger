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
[ -s "$LESSONS_FILE" ] && pass || fail "lessons.jsonl not written"
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
