#!/usr/bin/env bash
# Claude Supercharger — Scored Installation Health Check
set -euo pipefail

HOOKS_DIR="$HOME/.claude/supercharger/hooks"
TOOLS_DIR="$HOME/.claude/supercharger/tools"
SETTINGS="$HOME/.claude/settings.json"
SCORE=0
ISSUES=()

# Checkmark symbols
PASS="✓"
FAIL="✗"

score_hooks() {
  local pts=0
  local marks=""

  # settings.json exists and has hooks key
  if [ -f "$SETTINGS" ] && python3 -c "
import json, sys
with open('$SETTINGS') as f: s = json.load(f)
sys.exit(0 if 'hooks' in s else 1)
" 2>/dev/null; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("settings.json missing or has no hooks key")
  fi

  # At least 10 hooks registered
  local hook_count=0
  if [ -f "$SETTINGS" ]; then
    hook_count=$(python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
total = sum(len(v) for v in s.get('hooks', {}).values())
print(total)
" 2>/dev/null || echo 0)
  fi
  if [ "$hook_count" -ge 10 ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("Fewer than 10 hooks registered (found ${hook_count})")
  fi

  # safety.sh is registered
  if [ -f "$SETTINGS" ] && grep -q "safety.sh" "$SETTINGS" 2>/dev/null; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("safety.sh not registered in settings.json")
  fi

  # git-safety.sh is registered
  if [ -f "$SETTINGS" ] && grep -q "git-safety.sh" "$SETTINGS" 2>/dev/null; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("git-safety.sh not registered in settings.json")
  fi

  SCORE=$((SCORE + pts))
  printf "  Hooks:     %2d/20  %s\n" "$pts" "$marks"
}

score_config() {
  local pts=0
  local marks=""

  if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q "Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("~/.claude/CLAUDE.md missing or does not contain 'Supercharger'")
  fi

  if [ -f "$HOME/.claude/rules/economy.md" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("~/.claude/rules/economy.md not found")
  fi

  if [ -f "$HOME/.claude/rules/supercharger.md" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("~/.claude/rules/supercharger.md not found")
  fi

  # At least 1 role file in ~/.claude/rules/
  local role_count=0
  for role in developer writer student data pm designer devops researcher; do
    [ -f "$HOME/.claude/rules/${role}.md" ] && role_count=$((role_count + 1))
  done
  if [ "$role_count" -ge 1 ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("No role files found in ~/.claude/rules/")
  fi

  SCORE=$((SCORE + pts))
  printf "  Config:    %2d/20  %s\n" "$pts" "$marks"
}

score_agents() {
  local pts=0
  local marks=""

  # agents/ exists and has .md files
  local agent_count=0
  if [ -d "$HOME/.claude/agents" ]; then
    agent_count=$(ls "$HOME/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$agent_count" -ge 1 ]; then
    pts=$((pts + 10)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("~/.claude/agents/ missing or contains no .md files")
  fi

  # At least 5 agent files
  if [ "$agent_count" -ge 5 ]; then
    pts=$((pts + 10)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("Fewer than 5 agent files found (found ${agent_count})")
  fi

  SCORE=$((SCORE + pts))
  printf "  Agents:    %2d/20  %s\n" "$pts" "$marks"
}

score_tools() {
  local pts=0
  local marks=""

  if [ -d "$TOOLS_DIR" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("~/.claude/supercharger/tools/ directory not found")
  fi

  if [ -f "$TOOLS_DIR/economy-switch.sh" ] && [ -x "$TOOLS_DIR/economy-switch.sh" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("economy-switch.sh not found or not executable in tools/")
  fi

  if [ -f "$TOOLS_DIR/update.sh" ] && [ -x "$TOOLS_DIR/update.sh" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("update.sh not found or not executable in tools/")
  fi

  if [ -f "$HOME/.claude/supercharger/lib/utils.sh" ]; then
    pts=$((pts + 5)); marks="${marks}${PASS}"
  else
    marks="${marks}${FAIL}"
    ISSUES+=("lib/utils.sh not deployed to ~/.claude/supercharger/lib/")
  fi

  SCORE=$((SCORE + pts))
  printf "  Tools:     %2d/20  %s\n" "$pts" "$marks"
}

score_security() {
  local pts=0
  local marks=""

  for hook in safety git-safety prompt-injection-scanner smart-approve; do
    if [ -f "$HOOKS_DIR/${hook}.sh" ]; then
      pts=$((pts + 5)); marks="${marks}${PASS}"
    else
      marks="${marks}${FAIL}"
      ISSUES+=("${hook}.sh not found in hooks directory")
    fi
  done

  SCORE=$((SCORE + pts))
  printf "  Security:  %2d/20  %s\n" "$pts" "$marks"
}

echo "Claude Supercharger Health Check"
echo "================================"
score_hooks
score_config
score_agents
score_tools
score_security
echo "  ─────────────────"
printf "  Total:     %d/100\n" "$SCORE"

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo ""
  echo "Issues:"
  for issue in "${ISSUES[@]}"; do
    echo "  ${FAIL} ${issue}"
  done
fi
