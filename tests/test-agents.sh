#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

AGENTS_DIR="$REPO_DIR/configs/agents"

echo "=== Agent File Tests ==="

EXPECTED_AGENTS=(
  "code-helper"
  "debugger"
  "writer"
  "reviewer"
  "researcher"
  "planner"
  "data-analyst"
  "general"
  "architect"
)

for agent in "${EXPECTED_AGENTS[@]}"; do
  begin_test "agents: $agent.md exists in configs/agents/"
  assert_file_exists "$AGENTS_DIR/$agent.md" && pass
done

echo ""
echo "=== Agent Frontmatter Tests ==="

for agent in "${EXPECTED_AGENTS[@]}"; do
  begin_test "agents: $agent has 'name' in frontmatter"
  grep -q "^name:" "$AGENTS_DIR/$agent.md" && pass || fail "missing 'name' field"

  begin_test "agents: $agent has 'description' in frontmatter"
  grep -q "^description:" "$AGENTS_DIR/$agent.md" && pass || fail "missing 'description' field"

  begin_test "agents: $agent has 'model' in frontmatter"
  grep -q "^model:" "$AGENTS_DIR/$agent.md" && pass || fail "missing 'model' field"

  begin_test "agents: $agent has non-empty body"
  BODY=$(awk '/^---/{n++; if(n==2){found=1; next}} found{print}' "$AGENTS_DIR/$agent.md")
  [ -n "$BODY" ] && pass || fail "agent body is empty"
done

echo ""
echo "=== Agent Model Assignment Tests ==="

begin_test "agents: general uses sonnet model"
grep -q "^model: claude-sonnet" "$AGENTS_DIR/general.md" && pass || fail "general should use sonnet"

begin_test "agents: code-helper uses sonnet model"
grep -q "^model: claude-sonnet" "$AGENTS_DIR/code-helper.md" && pass || fail "code-helper should use sonnet"

begin_test "agents: debugger uses sonnet model"
grep -q "^model: claude-sonnet" "$AGENTS_DIR/debugger.md" && pass || fail "debugger should use sonnet"

begin_test "agents: architect uses sonnet model"
grep -q "^model: claude-sonnet" "$AGENTS_DIR/architect.md" && pass || fail "architect should use sonnet"

echo ""
echo "=== Reviewer Severity Model Tests ==="

begin_test "agents: reviewer has MUST FIX severity level"
grep -q "MUST FIX" "$AGENTS_DIR/reviewer.md" && pass || fail "reviewer missing MUST FIX severity"

begin_test "agents: reviewer has failure-mode reasoning instruction"
grep -q "When.*fails.*resulting" "$AGENTS_DIR/reviewer.md" && pass || fail "reviewer missing failure-mode reasoning"

echo ""
echo "=== Debugger Evidence Threshold Tests ==="

begin_test "agents: debugger has evidence threshold rule"
grep -q "Evidence threshold\|evidence threshold" "$AGENTS_DIR/debugger.md" && pass || fail "debugger missing evidence threshold"

echo ""
echo "=== Command File Tests ==="

COMMANDS_DIR="$REPO_DIR/configs/commands"
EXPECTED_COMMANDS=("think" "challenge" "audit" "handoff" "security" "stuck" "scope" "pr" "interview" "devlog" "design")

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  begin_test "commands: $cmd.md exists in configs/commands/"
  assert_file_exists "$COMMANDS_DIR/$cmd.md" && pass
done

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  begin_test "commands: $cmd.md has non-empty content"
  CONTENT=$(cat "$COMMANDS_DIR/$cmd.md")
  [ -n "$CONTENT" ] && pass || fail "$cmd.md is empty"
done

echo ""
echo "=== Project Template Tests ==="

TEMPLATES_DIR="$REPO_DIR/configs/project-agent-templates"

begin_test "project-templates: architect.md exists"
assert_file_exists "$TEMPLATES_DIR/architect.md" && pass

begin_test "project-templates: architect has PROJECT_NAME placeholder"
grep -q "{{PROJECT_NAME}}" "$TEMPLATES_DIR/architect.md" && pass || fail "missing {{PROJECT_NAME}}"

begin_test "project-templates: architect has STACK placeholder"
grep -q "{{STACK}}" "$TEMPLATES_DIR/architect.md" && pass || fail "missing {{STACK}}"

begin_test "project-templates: code-reviewer has MUST FIX severity"
grep -q "MUST FIX" "$TEMPLATES_DIR/code-reviewer.md" && pass || fail "code-reviewer missing MUST FIX"

begin_test "project-templates: debugger has evidence threshold rule"
grep -q "Evidence threshold\|evidence threshold" "$TEMPLATES_DIR/debugger.md" && pass || fail "project debugger missing evidence threshold"

report
