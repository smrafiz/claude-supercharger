#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/session-memory-inject.sh"

echo "=== Session Resume v2 Tests ==="

# Test 1: recovers from checkpoint when no memory file
begin_test "session-memory-inject: recovers from checkpoint when no memory file"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$PROJ/.claude"
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "branch:main files:src/app.ts" > "$SCOPE_DIR/.checkpoint-test-session-1"
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "RECOVERY"; then
  pass
else
  fail "expected 'RECOVERY' in output, got: $OUTPUT"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 2: prefers memory file over checkpoint
begin_test "session-memory-inject: prefers memory file over checkpoint"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$PROJ/.claude"
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
# Write a memory file with open work on same branch
BRANCH=$(git -C "$PROJ" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
echo "mem:2026-04-22T10:00Z branch:${BRANCH} open:src/app.ts commits:abc1234:init corrections:none" > "$PROJ/.claude/supercharger-memory.md"
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "branch:main files:src/app.ts" > "$SCOPE_DIR/.checkpoint-test-session-2"
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "RECOVERY"; then
  fail "should not contain 'RECOVERY' when memory file exists, got: $OUTPUT"
else
  pass
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 3: deletes stale checkpoints (>24h)
begin_test "session-memory-inject: deletes stale checkpoints (>24h)"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$PROJ/.claude"
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
SCOPE_DIR="$FAKE_HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
CKPT_FILE="$SCOPE_DIR/.checkpoint-stale-session"
echo "branch:main files:src/app.ts" > "$CKPT_FILE"
# Backdate to >24h ago
touch -t 202604200000 "$CKPT_FILE"
INPUT="{\"cwd\":\"$PROJ\"}"
(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if [ ! -f "$CKPT_FILE" ]; then
  pass
else
  fail "stale checkpoint file should have been deleted: $CKPT_FILE"
fi
rm -rf "$PROJ" "$FAKE_HOME"

# Test 4: enrichment includes diff when changes exist
begin_test "session-memory-inject: enrichment includes diff when changes exist"
PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$PROJ/.claude"
(cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q)
# Create and commit a file, then modify it so diff --stat shows changes
echo "original" > "$PROJ/main.ts"
git -C "$PROJ" add "$PROJ/main.ts"
git -C "$PROJ" commit -q -m "add main.ts"
echo "modified" > "$PROJ/main.ts"
# Write memory with open work on same branch
BRANCH=$(git -C "$PROJ" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
echo "mem:2026-04-22T10:00Z branch:${BRANCH} open:main.ts commits:abc1234:init corrections:none" > "$PROJ/.claude/supercharger-memory.md"
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$OUTPUT" | grep -q "diff:"; then
  pass
else
  fail "expected 'diff:' in output, got: $OUTPUT"
fi
rm -rf "$PROJ" "$FAKE_HOME"

report
