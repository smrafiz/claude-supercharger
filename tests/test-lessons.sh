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

# v2.7.18: quality gate — reject parenthetical asides, fragments, and the
# assistant NARRATING about debugging; accept declarative findings.
_lesson_rec() {  # $1=assistant text -> echoes "recorded" or "skipped"
  local proj; proj=$(mktemp -d); mkdir -p "$proj/.claude/supercharger"
  local tr="$proj/.transcript.jsonl"
  python3 -c 'import json; print(json.dumps({"type":"user","message":{"content":"debug q"}}))' > "$tr"
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1" >> "$tr"
  printf '{"cwd":"%s","transcript_path":"%s"}' "$proj" "$tr" | bash "$RECORD_HOOK" >/dev/null 2>&1 || true
  [ -s "$proj/.claude/supercharger/lessons.jsonl" ] && echo recorded || echo skipped
  rm -rf "$proj"
}

begin_test "lessons: rejects parenthetical aside '(root cause)'"
setup_test_home
[ "$(_lesson_rec 'The offset drifted past EOF (root cause).')" = "skipped" ] && pass || fail "parenthetical aside should be skipped"
teardown_test_home

begin_test "lessons: rejects assistant narration (first-person)"
setup_test_home
[ "$(_lesson_rec "I cannot pin the root cause down from inside the live session without making it worse.")" = "skipped" ] && pass || fail "first-person narration should be skipped"
teardown_test_home

begin_test "lessons: records a declarative finding (full sentence)"
setup_test_home
[ "$(_lesson_rec 'Root cause: Claude Code sends the session cwd in workspace.current_dir, not cwd.')" = "recorded" ] && pass || fail "declarative finding should be recorded"
teardown_test_home

begin_test "lessons: does not false-reject sentences containing it/is/in"
setup_test_home
[ "$(_lesson_rec 'The problem was that it is reading the wrong field and the value is empty in every call.')" = "recorded" ] && pass || fail "case-sensitive I check must not catch it/is/in"
teardown_test_home

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

begin_test "lessons: recall injects matching lesson at standard tier"
setup_test_home
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude/supercharger"
cat > "$PROJ/.claude/supercharger/lessons.jsonl" <<'EOF'
{"sig":"npm test fails: missing module foo","fix":"added foo to package.json","files":["package.json"],"lesson":"STANDARD_MARKER new imports require explicit dep add","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=standard bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'STANDARD_MARKER' && pass || fail "no lesson in standard recall output: $OUT"
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
{"sig":"x","fix":"y","files":[],"lesson":"walkup_marker","recall":"npm test cannot find module foo","ts":"2026-04-30T00:00:00Z"}
EOF
INPUT=$(printf '{"cwd":"%s/sub/dir","prompt":"%s"}' "$PROJ" "npm test cannot find module foo")
OUT=$(SUPERCHARGER_TIER=lean bash -c "echo '$INPUT' | bash $RECALL_HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'walkup_marker' && pass || fail "walk-up didn't find lessons.jsonl: $OUT"
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

# v2.7.14: Stop re-fires (stop_hook_active) must NOT record a duplicate lesson
begin_test "lessons: stop_hook_active re-fire records nothing"
setup_test_home
PROJ=$(mktemp -d); mkdir -p "$PROJ/.claude/supercharger"
TR="$PROJ/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"The issue was a null pointer. Root cause: missing guard. Fixed by adding a check."}]}}' > "$TR"
printf '{"transcript_path":"%s","cwd":"%s","stop_hook_active":true}' "$TR" "$PROJ" | bash "$RECORD_HOOK" >/dev/null 2>&1
RC=$?
LF="$PROJ/.claude/supercharger/lessons.jsonl"
if [ "$RC" -eq 0 ] && [ ! -f "$LF" ]; then pass
else fail "re-fire should record nothing; rc=$RC lessons_exists=$([ -f "$LF" ] && echo yes || echo no)"; fi
rm -rf "$PROJ"
teardown_test_home

report
