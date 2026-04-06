#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GATE="$REPO_DIR/hooks/agent-gate.sh"

# Test 1: No .agent-route → learns from first dispatch, exits 0, writes file
begin_test "agent-gate: no .agent-route learns from first dispatch"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if [ $EXIT_CODE -eq 0 ] && [ "$ROUTE" = "Tony Stark (Engineer)" ]; then pass
else fail "expected exit 0 + route written, got exit=$EXIT_CODE route='$ROUTE'"; fi
teardown_test_home

# Test 2: Correct agent dispatched → exits 0
begin_test "agent-gate: correct agent dispatched → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock Holmes (Detective)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 3: Wrong agent dispatched → exits 2
begin_test "agent-gate: wrong agent dispatched → exits 2"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then pass
else fail "expected exit code 2, got $EXIT_CODE"; fi
teardown_test_home

# Test 4: Case-insensitive match works → exits 0
begin_test "agent-gate: case-insensitive match → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Tony Stark (Engineer)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"tony stark (engineer)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 5: Partial match on first word → exits 0
begin_test "agent-gate: partial match on first word → exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit code 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 6: After learn-from-dispatch, second wrong dispatch is blocked
begin_test "agent-gate: enforces latched route after learning from first dispatch"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
# First dispatch — no file, gate learns Tony Stark
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' | bash "$GATE" >/dev/null 2>&1
# Second dispatch — wrong agent, should be blocked
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock Holmes (Detective)"}}' | bash "$GATE" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then pass
else fail "expected exit code 2 after latch, got $EXIT_CODE"; fi
teardown_test_home

report
