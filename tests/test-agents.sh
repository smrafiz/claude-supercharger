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

report
