#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/hooks/agent-router.sh"

# Test 1: Error prompt routes to Sherlock Holmes
begin_test "agent-router: error prompt routes to Sherlock Holmes"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception at line 42"}' | bash "$ROUTER" >/dev/null 2>&1
if [ -f "$HOME/.claude/supercharger/scope/.agent-route" ] && \
   grep -q "Sherlock" "$HOME/.claude/supercharger/scope/.agent-route"; then
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
if [ -f "$HOME/.claude/supercharger/scope/.agent-route" ] && \
   grep -q "Gordon" "$HOME/.claude/supercharger/scope/.agent-route"; then
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
if [ -f "$HOME/.claude/supercharger/scope/.agent-route" ] && \
   grep -q "Tony" "$HOME/.claude/supercharger/scope/.agent-route"; then
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
if [ -f "$HOME/.claude/supercharger/scope/.agent-route" ] && \
   grep -q "Ernest" "$HOME/.claude/supercharger/scope/.agent-route"; then
  pass
else
  fail "agent route not set to Ernest"
fi
teardown_test_home

# Test 5: Ambiguous prompt writes nothing
begin_test "agent-router: ambiguous prompt does not write .agent-route"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"help me"}' | bash "$ROUTER" >/dev/null 2>&1
if [ ! -f "$HOME/.claude/supercharger/scope/.agent-route" ]; then
  pass
else
  fail ".agent-route was created for ambiguous prompt"
fi
teardown_test_home

# Test 6: Second call re-classifies (per-prompt routing)
begin_test "agent-router: re-classifies on each prompt"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"debug this stack trace"}' | bash "$ROUTER" >/dev/null 2>&1
FIRST=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
echo '{"prompt":"write a blog post"}' | bash "$ROUTER" >/dev/null 2>&1
SECOND=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if [ "$FIRST" != "$SECOND" ] && echo "$FIRST" | grep -q "Sherlock" && echo "$SECOND" | grep -q "Ernest"; then
  pass
else
  fail "re-classify failed: first='$FIRST' second='$SECOND'"
fi
teardown_test_home

# Test 7: stdout is valid JSON with additionalContext
begin_test "agent-router: stdout contains valid JSON with additionalContext"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"debug this error"}' | bash "$ROUTER" 2>/dev/null)
if echo "$OUTPUT" | grep -q '"hookSpecificOutput"' && \
   echo "$OUTPUT" | grep -q '"additionalContext"' && \
   echo "$OUTPUT" | grep -q 'SUPERCHARGER ROUTING'; then
  pass
else
  fail "stdout missing expected JSON structure or SUPERCHARGER ROUTING text: $OUTPUT"
fi
teardown_test_home

# Test 8: .agent-route contains exact agent name with no extra whitespace
begin_test "agent-router: .agent-route contains exact agent name"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception"}' | bash "$ROUTER" >/dev/null 2>&1
CONTENT=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
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
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Tony"; then pass
else fail ".agent-route wrong: $ROUTE (expected Tony Stark)"; fi
teardown_test_home

report
