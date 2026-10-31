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
  "explorer"
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

# v2.7.56: model tiered by task. Read-only REASONING agents (produce plans /
# root-causes / designs / reviews where reasoning quality is the deliverable) run
# on Opus; EXECUTION/throughput agents run on Sonnet (fast + cheaper). Extends the
# original reviewer=Opus intent consistently to the other reasoning agents.
for agent in architect debugger planner researcher reviewer; do
  begin_test "agents: $agent (reasoning) uses opus model"
  grep -qx "model: opus" "$AGENTS_DIR/$agent.md" && pass || fail "$agent should use opus (reasoning-critical)"
done

for agent in general code-helper writer data-analyst; do
  begin_test "agents: $agent (execution) uses sonnet model"
  grep -qx "model: sonnet" "$AGENTS_DIR/$agent.md" && pass || fail "$agent should use sonnet (throughput)"
done

# 2026-10-31: read-only search is the cheapest work there is (Provost runs it on
# Haiku). Aliases, not pinned IDs: the pins had drifted to legacy models.
begin_test "agents: explorer (read-only search) uses haiku model"
grep -qx "model: haiku" "$AGENTS_DIR/explorer.md" && pass || fail "explorer should use haiku"

begin_test "agents: no agent pins a dated model ID (aliases track the current model)"
! grep -l "^model: claude-" "$AGENTS_DIR"/*.md >/dev/null 2>&1 && pass || fail "pinned: $(grep -l '^model: claude-' "$AGENTS_DIR"/*.md)"

begin_test "agents: no project agent template pins a dated model ID"
_tpl="$REPO_DIR/configs/project-agent-templates"
! grep -l "^model: claude-" "$_tpl"/*.md >/dev/null 2>&1 && pass || fail "pinned: $(grep -l '^model: claude-' "$_tpl"/*.md)"

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
echo "=== Writer De-slop Wiring Tests ==="

# The writer's self-edit runs sc-de-ai through the Skill tool. Without Skill in its
# tools, or with a name that resolves to no command, the step silently does nothing.
begin_test "agents: writer has the Skill tool"
grep -qE '^tools:.*\bSkill\b' "$AGENTS_DIR/writer.md" && pass || fail "writer cannot invoke sc-de-ai without Skill"

begin_test "agents: writer's de-slop command names resolve (install and plugin)"
MISSING=""
grep -q '`sc-de-ai`' "$AGENTS_DIR/writer.md" || MISSING="$MISSING writer-does-not-name-sc-de-ai"
grep -q '`supercharger:de-ai`' "$AGENTS_DIR/writer.md" || MISSING="$MISSING writer-does-not-name-supercharger:de-ai"
[ -f "$REPO_DIR/configs/commands/sc-de-ai.md" ] || MISSING="$MISSING configs/commands/sc-de-ai.md"
[ -f "$REPO_DIR/commands/de-ai.md" ] || MISSING="$MISSING commands/de-ai.md"
[ -z "$MISSING" ] && pass || fail "unresolved:$MISSING"

begin_test "commands: sc-de-ai credits its MIT source in NOTICE"
grep -q 'petergyang/no-ai-slop' "$REPO_DIR/NOTICE" && grep -q 'Copyright (c) 2026 Peter Yang' "$REPO_DIR/NOTICE" \
  && pass || fail "NOTICE lacks the no-ai-slop copyright + licence"

echo ""
echo "=== Command File Tests ==="

COMMANDS_DIR="$REPO_DIR/configs/commands"
EXPECTED_COMMANDS=("think" "challenge" "audit" "handoff" "security" "stuck" "scope" "pr" "interview" "devlog" "design" "design-review" "multi-review" "reflect")

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  begin_test "commands: sc-$cmd.md exists in configs/commands/"
  assert_file_exists "$COMMANDS_DIR/sc-$cmd.md" && pass
done

for cmd in "${EXPECTED_COMMANDS[@]}"; do
  begin_test "commands: sc-$cmd.md has non-empty content"
  CONTENT=$(cat "$COMMANDS_DIR/sc-$cmd.md")
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
