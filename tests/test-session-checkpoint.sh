#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/session-checkpoint.sh"

echo "=== Session Checkpoint Hook Tests ==="

# Test 1: writes checkpoint after Write tool
begin_test "session-checkpoint: writes checkpoint after Write tool"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
INPUT="{\"session_id\":\"ckpt-test\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/src/app.ts\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
if [ -f "$SCOPE_DIR/.checkpoint-ckpt-test" ]; then
  pass
else
  fail "checkpoint file not created at $SCOPE_DIR/.checkpoint-ckpt-test"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 2: overwrites previous checkpoint
begin_test "session-checkpoint: overwrites previous checkpoint"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "old data" > "$SCOPE_DIR/.checkpoint-ckpt-overwrite"
INPUT="{\"session_id\":\"ckpt-overwrite\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJ/src/app.ts\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
CONTENT=$(cat "$SCOPE_DIR/.checkpoint-ckpt-overwrite" 2>/dev/null || echo "")
if echo "$CONTENT" | grep -q "^ckpt:"; then
  pass
else
  fail "expected content starting with 'ckpt:', got: $CONTENT"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 3: includes branch and files
begin_test "session-checkpoint: includes branch and files"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
# Create a staged file so it shows in modified files list
touch "$PROJ/changed.ts"
git -C "$PROJ" add "$PROJ/changed.ts" 2>/dev/null || true
# cwd travels as JSON content, which MSYS does not rewrite, so on Git Bash a raw
# mktemp path reaches the hook as /tmp/... . session-checkpoint then runs git -C
# on it FROM PYTHON, where no argument translation happens either, so git cannot
# resolve the repo and the branch/files fields come back empty.
PROJ_NATIVE=$(native_path "$PROJ")
INPUT="{\"session_id\":\"ckpt-fields\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/changed.ts\"},\"cwd\":\"$PROJ_NATIVE\"}"
(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
CONTENT=$(cat "$SCOPE_DIR/.checkpoint-ckpt-fields" 2>/dev/null || echo "")
if echo "$CONTENT" | grep -q "branch:" && echo "$CONTENT" | grep -q "files:"; then
  pass
else
  fail "expected 'branch:' and 'files:' in checkpoint, got: $CONTENT"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 4: capped at 500 chars
begin_test "session-checkpoint: capped at 500 chars"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
# Create 50 long-named files and stage them so they appear in the files list
for i in $(seq 1 50); do
  touch "$PROJ/very-long-filename-number-${i}-abcdefghijklmnopqrstuvwxyz.ts"
done
git -C "$PROJ" add . 2>/dev/null || true
INPUT="{\"session_id\":\"ckpt-cap\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
CKPT_FILE="$SCOPE_DIR/.checkpoint-ckpt-cap"
if [ -f "$CKPT_FILE" ]; then
  FILE_SIZE=$(wc -c < "$CKPT_FILE" | tr -d ' ')
  # +1 for the trailing newline added by printf '%s\n'
  if [ "$FILE_SIZE" -le 501 ]; then
    pass
  else
    fail "checkpoint file size $FILE_SIZE > 501 bytes (500 chars + newline)"
  fi
else
  fail "checkpoint file not created"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# v2.7.23: checkpoint cleanup (session-memory-write on Stop) must be SID-scoped —
# was a bare `.checkpoint-*` glob that deleted concurrent sessions' checkpoints.
begin_test "session-memory-write: checkpoint cleanup does not delete other sessions"
FAKE_HOME=$(mktemp -d); SD="$FAKE_HOME/.claude/supercharger/scope"; mkdir -p "$SD"
echo "ckA" > "$SD/.checkpoint-sessA"
echo "ckB" > "$SD/.checkpoint-sessB"
PROJ=$(mktemp -d)
printf '{"session_id":"sessA","cwd":"%s"}' "$PROJ" | HOME="$FAKE_HOME" bash "$REPO_DIR/hooks/session-memory-write.sh" >/dev/null 2>&1
[ -f "$SD/.checkpoint-sessB" ] && pass || fail "other session's checkpoint was deleted (cross-session glob bug)"
rm -rf "$PROJ" "$FAKE_HOME"

# ── Debounce Tests (v2.23.3) ─────────────────────────────────────────────────────
# The checkpoint is a full idempotent snapshot, so a debounced (skipped) write
# loses nothing — the next write captures fresh state and git holds the true files.

begin_test "session-checkpoint: debounced within window (no rewrite)"
PROJ=$(mktemp -d); FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m init -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
INPUT="{\"session_id\":\"dck\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/a.ts\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=10; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
BEFORE=$(cat "$SCOPE_DIR/.checkpoint-dck" 2>/dev/null)
echo "SENTINEL" > "$SCOPE_DIR/.checkpoint-dck"   # if the 2nd call walks, it overwrites this
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=10; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
AFTER=$(cat "$SCOPE_DIR/.checkpoint-dck" 2>/dev/null)
if [ -n "$BEFORE" ] && [ "$AFTER" = "SENTINEL" ]; then pass; else fail "2nd call was not debounced (checkpoint rewritten): '$AFTER'"; fi
rm -rf "$PROJ" "$FAKE_HOME"

begin_test "session-checkpoint: DEBOUNCE_SECS=0 writes every call"
PROJ=$(mktemp -d); FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m init -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
INPUT="{\"session_id\":\"dck0\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/a.ts\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=0; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
echo "SENTINEL" > "$SCOPE_DIR/.checkpoint-dck0"
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=0; printf '%s' "$INPUT" | bash "$HOOK") 2>/dev/null
AFTER=$(cat "$SCOPE_DIR/.checkpoint-dck0" 2>/dev/null)
echo "$AFTER" | grep -q "^ckpt:" && pass || fail "DEBOUNCE=0 should rewrite every call, got: $AFTER"
rm -rf "$PROJ" "$FAKE_HOME"

begin_test "session-checkpoint: debounce marker is per-session (no cross-suppress)"
PROJ=$(mktemp -d); FAKE_HOME=$(mktemp -d)
(cd "$PROJ" && git init -q && git commit --allow-empty -m init -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"; mkdir -p "$SCOPE_DIR"
IA="{\"session_id\":\"dcA\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/a.ts\"},\"cwd\":\"$PROJ\"}"
IB="{\"session_id\":\"dcB\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/a.ts\"},\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=10; printf '%s' "$IA" | bash "$HOOK") 2>/dev/null
(export HOME="$FAKE_HOME" SUPERCHARGER_CHECKPOINT_DEBOUNCE_SECS=10; printf '%s' "$IB" | bash "$HOOK") 2>/dev/null
if [ -f "$SCOPE_DIR/.checkpoint-dcA" ] && [ -f "$SCOPE_DIR/.checkpoint-dcB" ]; then pass; else fail "session B wrongly debounced by A's marker"; fi
rm -rf "$PROJ" "$FAKE_HOME"

report
