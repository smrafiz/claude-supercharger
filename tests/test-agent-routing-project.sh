#!/usr/bin/env bash
# Smoke tests for project agent priority routing (v2.0.6/v2.0.7)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/hooks/agent-router.sh"

# Helper: write a minimal agent .md file
write_agent() {
  local dir="$1" name="$2" desc="$3"
  mkdir -p "$dir"
  cat > "$dir/$(echo "$name" | tr '[:upper:] ' '[:lower:]-').md" <<EOF
---
name: $name
description: $desc
tools: Read, Write, Edit, Bash
model: claude-sonnet-4-6
---

Agent body.
EOF
}

# Test A: Project agents injected into additionalContext
begin_test "agent-routing: project agents injected when .claude/agents/ exists"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PROJECT_DIR=$(mktemp -d)
write_agent "$PROJECT_DIR/.claude/agents" "Deploy Expert" "Handles deployment tasks for this project."
OUTPUT=$(printf '{"prompt":"deploy the app","workspace":{"current_dir":"%s"}}' "$PROJECT_DIR" | bash "$ROUTER" 2>/dev/null)
rm -rf "$PROJECT_DIR"
if printf '%s\n' "$OUTPUT" | grep -q "Deploy Expert" && \
   printf '%s\n' "$OUTPUT" | grep -qi "project agents\|take precedence"; then pass
else fail "project agent not injected — output: $OUTPUT"; fi
teardown_test_home

# Test B: No .claude/agents/ → no project agent injection
begin_test "agent-routing: no project agents dir → global-only context"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PROJECT_DIR=$(mktemp -d)
OUTPUT=$(printf '{"prompt":"deploy the app","workspace":{"current_dir":"%s"}}' "$PROJECT_DIR" | bash "$ROUTER" 2>/dev/null)
rm -rf "$PROJECT_DIR"
if printf '%s\n' "$OUTPUT" | grep -q "SUPERCHARGER ROUTING" && \
   ! printf '%s\n' "$OUTPUT" | grep -qi "project agents"; then pass
else fail "unexpected project agent injection with no agents dir — output: $OUTPUT"; fi
teardown_test_home

# Test C: Agent file missing name field is skipped
begin_test "agent-routing: agent file without name field is skipped"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PROJECT_DIR=$(mktemp -d)
write_agent "$PROJECT_DIR/.claude/agents" "Valid Agent" "Does valid things."
# Write a nameless agent file
cat > "$PROJECT_DIR/.claude/agents/nameless.md" <<'EOF'
---
description: This agent has no name field.
tools: Read
---
EOF
OUTPUT=$(printf '{"prompt":"help me","workspace":{"current_dir":"%s"}}' "$PROJECT_DIR" | bash "$ROUTER" 2>/dev/null)
rm -rf "$PROJECT_DIR"
if printf '%s\n' "$OUTPUT" | grep -q "Valid Agent" && \
   ! printf '%s\n' "$OUTPUT" | grep -q "nameless"; then pass
else fail "nameless agent leaked or valid agent missing — output: $OUTPUT"; fi
teardown_test_home

# Test D: workspace.current_dir used over $PWD
begin_test "agent-routing: workspace.current_dir takes priority over PWD"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PROJECT_DIR=$(mktemp -d)
write_agent "$PROJECT_DIR/.claude/agents" "Remote Expert" "Handles remote tasks."
# $PWD has no agents; payload points to PROJECT_DIR which does
OUTPUT=$(printf '{"prompt":"do something","workspace":{"current_dir":"%s"}}' "$PROJECT_DIR" | bash "$ROUTER" 2>/dev/null)
rm -rf "$PROJECT_DIR"
if printf '%s\n' "$OUTPUT" | grep -q "Remote Expert"; then pass
else fail "workspace.current_dir not used — output: $OUTPUT"; fi
teardown_test_home

# Test E: Description truncated and JSON output is valid
begin_test "agent-routing: description truncated and output is valid JSON"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
PROJECT_DIR=$(mktemp -d)
write_agent "$PROJECT_DIR/.claude/agents" "Test Agent" 'Handles "complex" tasks. Secondary sentence here. More stuff.'
OUTPUT=$(printf '{"prompt":"do something","workspace":{"current_dir":"%s"}}' "$PROJECT_DIR" | bash "$ROUTER" 2>/dev/null)
rm -rf "$PROJECT_DIR"
# Validate JSON
VALID_JSON=$(printf '%s\n' "$OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin); print('ok')" 2>/dev/null || echo "invalid")
# Check secondary sentence not present
NO_SECONDARY=true
printf '%s\n' "$OUTPUT" | grep -q "Secondary sentence" && NO_SECONDARY=false
AGENT_DETECTED=$(printf '%s\n' "$OUTPUT" | grep -c "Test Agent" || true)
if [ "$VALID_JSON" = "ok" ] && [ "$NO_SECONDARY" = "true" ] && [ "$AGENT_DETECTED" -gt 0 ]; then pass
else fail "JSON invalid, description not truncated, or agent not detected — valid=$VALID_JSON secondary_absent=$NO_SECONDARY detected=$AGENT_DETECTED"; fi
teardown_test_home

report
