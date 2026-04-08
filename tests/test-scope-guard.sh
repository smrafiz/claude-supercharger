#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SCOPE_GUARD="$REPO_DIR/hooks/scope-guard.sh"

# Test 1: snapshot creates file
begin_test "scope-guard: snapshot creates .snapshot file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
TMPDIR=$(mktemp -d)
cd "$TMPDIR" && git init -q && git commit --allow-empty -m "init" -q
bash "$SCOPE_GUARD" snapshot "$TMPDIR"
if [ -f "$HOME/.claude/supercharger/scope/.snapshot" ]; then pass
else fail "snapshot file not created"; fi
rm -rf "$TMPDIR"; teardown_test_home

# Test 2: contract extracts single-file-scope
begin_test "scope-guard: contract detects single-file intent"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"fix the typo in Header.tsx only"}' | bash "$SCOPE_GUARD" contract
CONTRACT=$(cat "$HOME/.claude/supercharger/scope/.contract" 2>/dev/null || echo "")
if echo "$CONTRACT" | grep -q "single-file-scope"; then pass
else fail "single-file-scope not detected: $CONTRACT"; fi
teardown_test_home

# Test 3: contract extracts file path
begin_test "scope-guard: contract extracts file path"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"update the login function in src/auth.py"}' | bash "$SCOPE_GUARD" contract
CONTRACT=$(cat "$HOME/.claude/supercharger/scope/.contract" 2>/dev/null || echo "")
if echo "$CONTRACT" | grep -q "auth.py"; then pass
else fail "file path not extracted: $CONTRACT"; fi
teardown_test_home

# Test 4: clear removes state files including agent scope files
begin_test "scope-guard: clear removes snapshot, contract, and agent scope files"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "scope:general" > "$HOME/.claude/supercharger/scope/.contract"
echo "commit:abc" > "$HOME/.claude/supercharger/scope/.snapshot"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-classified"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-dispatched"
bash "$SCOPE_GUARD" clear
if [ ! -f "$HOME/.claude/supercharger/scope/.snapshot" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.contract" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.agent-classified" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.agent-dispatched" ]; then pass
else fail "files not cleared"; fi
teardown_test_home

# Test 5: contract is idempotent (second call doesn't overwrite)
begin_test "scope-guard: contract not overwritten on second call"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"fix Header.tsx only"}' | bash "$SCOPE_GUARD" contract
FIRST=$(cat "$HOME/.claude/supercharger/scope/.contract")
echo '{"prompt":"rewrite everything"}' | bash "$SCOPE_GUARD" contract
SECOND=$(cat "$HOME/.claude/supercharger/scope/.contract")
if [ "$FIRST" = "$SECOND" ]; then pass
else fail "contract was overwritten: first=$FIRST second=$SECOND"; fi
teardown_test_home

report