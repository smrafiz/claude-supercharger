#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/hooks/agent-router.sh"

# Test 1: Error prompt routes to Sherlock Holmes
begin_test "agent-router: error prompt routes to Sherlock Holmes"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception at line 42"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-classified-default" ] && \
   grep -q "Sherlock" "$HOME/.claude/supercharger/scope/.agent-classified-default"; then
  pass
else
  fail "agent route not set to Sherlock"
fi
teardown_test_home

# Test 2: Review prompt routes to Gordon Ramsay
begin_test "agent-router: review prompt routes to Gordon Ramsay"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"review this file for security issues"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-classified-default" ] && \
   grep -q "Gordon" "$HOME/.claude/supercharger/scope/.agent-classified-default"; then
  pass
else
  fail "agent route not set to Gordon"
fi
teardown_test_home

# Test 3: Implement prompt routes to Tony Stark
begin_test "agent-router: implement prompt routes to Tony Stark"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"implement a login function in auth.py"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-classified-default" ] && \
   grep -q "Tony" "$HOME/.claude/supercharger/scope/.agent-classified-default"; then
  pass
else
  fail "agent route not set to Tony"
fi
teardown_test_home

# Test 4: Write prompt routes to Ernest Hemingway
begin_test "agent-router: write prompt routes to Ernest Hemingway"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"write a README for this project"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-classified-default" ] && \
   grep -q "Ernest" "$HOME/.claude/supercharger/scope/.agent-classified-default"; then
  pass
else
  fail "agent route not set to Ernest"
fi
teardown_test_home

# Test 5: Ambiguous prompt falls back to Generalist
begin_test "agent-router: ambiguous prompt routes to Steve Jobs (Generalist)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"help me"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-classified-default" ] && \
   grep -q "Steve Jobs" "$HOME/.claude/supercharger/scope/.agent-classified-default"; then
  pass
else
  fail "expected Generalist fallback"
fi
teardown_test_home

# Test 6: Second call re-classifies (per-prompt routing)
begin_test "agent-router: re-classifies on each prompt"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"debug this stack trace"}' | bash "$ROUTER" >/dev/null 2>&1
FIRST=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
echo '{"prompt":"write a blog post"}' | bash "$ROUTER" >/dev/null 2>&1
SECOND=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
if [ "$FIRST" != "$SECOND" ] && echo "$FIRST" | grep -q "Sherlock" && echo "$SECOND" | grep -q "Ernest"; then
  pass
else
  fail "re-classify failed: first='$FIRST' second='$SECOND'"
fi
teardown_test_home

# Test 7: stdout is valid JSON containing [CTX] (format depends on debug flag)
begin_test "agent-router: stdout contains valid JSON with [CTX] context"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"debug this error"}' | bash "$ROUTER" 2>/dev/null)
if echo "$OUTPUT" | grep -q '\[CTX\]' && \
   (echo "$OUTPUT" | grep -q '"hookSpecificOutput"' || echo "$OUTPUT" | grep -q '"systemMessage"'); then
  pass
else
  fail "stdout missing expected JSON structure or [CTX] text: $OUTPUT"
fi
teardown_test_home

# 2.18.3: the fork-free output JSON (edit 3) must be valid parseable JSON.
begin_test "agent-router: fork-free output JSON parses (2.18.3)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"design the auth system","session_id":"j1"}' | bash "$ROUTER" 2>/dev/null)
if printf '%s' "$OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert "[CTX]" in d["hookSpecificOutput"]["additionalContext"]' 2>/dev/null; then pass
else fail "fork-free JSON not parseable / missing [CTX]: $OUTPUT"; fi
teardown_test_home

# 2.18.3: string-compare dedup (edit 2) — identical prompt twice in a session, 2nd is silent.
begin_test "agent-router: dedup skips identical injection within TTL (2.18.3)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PAY='{"prompt":"fix the bug","session_id":"jd"}'
A=$(printf '%s' "$PAY" | bash "$ROUTER" 2>/dev/null)
B=$(printf '%s' "$PAY" | bash "$ROUTER" 2>/dev/null)
{ [ -n "$A" ] && [ -z "$B" ]; } && pass || fail "dedup broken: first=[${A:+set}] second=[${B:+set}] (want set,empty)"
teardown_test_home

# Test 8: .agent-classified-default contains exact agent name with no extra whitespace
begin_test "agent-router: .agent-classified-default contains exact agent name"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception"}' | bash "$ROUTER" >/dev/null 2>&1
CONTENT=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
if [ "$CONTENT" = "Sherlock Holmes (Detective)" ]; then
  pass
else
  fail "agent name mismatch: expected 'Sherlock Holmes (Detective)', got '$CONTENT'"
fi
teardown_test_home

# Test 9: "write a function" routes to Tony Stark (not Ernest Hemingway)
begin_test "agent-router: write-a-function prompt routes to Tony Stark not Hemingway"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"write a function to parse JSON"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Tony"; then pass
else fail ".agent-classified-default wrong: $ROUTE (expected Tony Stark)"; fi
teardown_test_home

# Test 10: "where is X" routes to Ferdinand Magellan (code exploration)
begin_test "agent-router: where-is prompt routes to Ferdinand Magellan"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"where is the rate-limiting logic in this codebase"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Magellan"; then pass
else fail ".agent-classified-default wrong: $ROUTE (expected Ferdinand Magellan)"; fi
teardown_test_home

# Test 11: "find every caller of" routes to Ferdinand Magellan (not the engineer catch-all)
begin_test "agent-router: find-callers prompt routes to Ferdinand Magellan"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"find every caller of the legacy AuthClient"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-classified-default" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Magellan"; then pass
else fail ".agent-classified-default wrong: $ROUTE (expected Ferdinand Magellan)"; fi
teardown_test_home

report
