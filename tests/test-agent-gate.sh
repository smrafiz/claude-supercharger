#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GATE="$REPO_DIR/hooks/agent-gate.sh"

# Test 1: No .agent-classified → dispatches, exits 0, writes .agent-dispatched
begin_test "agent-gate: dispatch writes .agent-dispatched"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
DISPATCHED=$(cat "$HOME/.claude/supercharger/scope/.agent-dispatched" 2>/dev/null || echo "")
if [ $EXIT_CODE -eq 0 ] && [ "$DISPATCHED" = "Tony Stark (Engineer)" ]; then pass
else fail "expected exit 0 + .agent-dispatched written, got exit=$EXIT_CODE dispatched='$DISPATCHED'"; fi
teardown_test_home

# Test 2: Correct agent dispatched → exits 0
begin_test "agent-gate: correct agent dispatched → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-classified"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock Holmes (Detective)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 3: Wrong agent dispatched → warns but allows (exit 0)
begin_test "agent-gate: wrong agent dispatched → warns but allows (exit 0)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-classified"
STDERR=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' | bash "$GATE" 2>&1 >/dev/null)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && echo "$STDERR" | grep -q "Agent routing"; then pass
else fail "expected exit 0 + warning on stderr, got exit=$EXIT_CODE"; fi
teardown_test_home

# Test 4: Case-insensitive match works → exits 0
begin_test "agent-gate: case-insensitive match → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Tony Stark (Engineer)" > "$HOME/.claude/supercharger/scope/.agent-classified"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"tony stark (engineer)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 5: Partial match on first word → exits 0
begin_test "agent-gate: partial match on first word → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-classified"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 6: Classified file present, different agent dispatched → warns but allows
begin_test "agent-gate: warns on mismatch after learning from first dispatch"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
# Router classified Tony Stark
echo "Tony Stark (Engineer)" > "$HOME/.claude/supercharger/scope/.agent-classified"
# But Claude dispatches Sherlock Holmes — should warn but allow
STDERR=$(echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock Holmes (Detective)"}}' | bash "$GATE" 2>&1 >/dev/null)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ] && echo "$STDERR" | grep -q "Agent routing"; then pass
else fail "expected exit 0 + warning after latch, got exit=$EXIT_CODE"; fi
teardown_test_home

report
