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
INPUT="{\"session_id\":\"ckpt-fields\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/changed.ts\"},\"cwd\":\"$PROJ\"}"
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

report
