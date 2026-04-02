#!/usr/bin/env bash
# Claude Supercharger — Installation Health Check
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║    Claude Supercharger Health Check       ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

ERRORS=0

check_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    echo -e "  ${GREEN}✓${NC} $label"
  else
    echo -e "  ${RED}✗${NC} $label — ${RED}missing${NC}"
    ERRORS=$((ERRORS + 1))
  fi
}

# Config Files
echo -e "${BLUE}Config Files:${NC}"
check_file "$HOME/.claude/CLAUDE.md" "CLAUDE.md"
check_file "$HOME/.claude/rules/supercharger.md" "rules/supercharger.md — universal rules"
check_file "$HOME/.claude/rules/guardrails.md" "rules/guardrails.md — Four Laws + safety"

# Primary roles (active in rules/)
echo ""
echo -e "${BLUE}Primary Roles (active):${NC}"
ROLES_FOUND=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$HOME/.claude/rules/${role}.md" ]; then
    ROLE_LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    echo -e "  ${GREEN}✓${NC} ${ROLE_LABEL}"
    ROLES_FOUND="${ROLES_FOUND:+$ROLES_FOUND, }$ROLE_LABEL"
  fi
done
if [ -z "$ROLES_FOUND" ]; then
  echo -e "  ${YELLOW}○${NC} No primary roles found"
fi

echo ""
echo -e "${BLUE}Available Roles (mode switching):${NC}"
AVAILABLE_FOUND=""
for role in developer writer student data pm designer devops researcher; do
  if [ -f "$HOME/.claude/supercharger/roles/${role}.md" ]; then
    ROLE_LABEL="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    AVAILABLE_FOUND="${AVAILABLE_FOUND:+$AVAILABLE_FOUND, }$ROLE_LABEL"
  fi
done
if [ -n "$AVAILABLE_FOUND" ]; then
  echo -e "  ${GREEN}✓${NC} ${AVAILABLE_FOUND}"
else
  echo -e "  ${YELLOW}○${NC} No role files in supercharger/roles/"
fi

# Shared assets
echo ""
echo -e "${BLUE}Shared Assets:${NC}"
check_file "$HOME/.claude/rules/anti-patterns.yml" "rules/anti-patterns.yml"
if [ -f "$HOME/.claude/shared/guardrails-template.yml" ]; then
  echo -e "  ${GREEN}✓${NC} guardrails-template.yml (Full mode)"
else
  echo -e "  ${YELLOW}○${NC} guardrails-template.yml — not installed (Full mode)"
fi

# Hooks
echo ""
echo -e "${BLUE}Hooks:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  HOOK_COUNT=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for h in event if '#supercharger' in h.get('command',''))
print(count)
" 2>/dev/null || echo "0")
  echo -e "  ${GREEN}✓${NC} settings.json valid — ${HOOK_COUNT} Supercharger hook(s) registered"

  if [ -d "$HOME/.claude/supercharger/hooks" ]; then
    for hook in safety notify git-safety quality-gate enforce-pkg-manager audit-trail project-config prompt-validator compaction-backup; do
      if [ -f "$HOME/.claude/supercharger/hooks/${hook}.sh" ]; then
        if grep -q "${hook}.sh" "$HOME/.claude/settings.json" 2>/dev/null; then
          echo -e "    ${GREEN}✓${NC} ${hook} — active"
        else
          echo -e "    ${YELLOW}○${NC} ${hook} — installed but not active"
        fi
      fi
    done
  fi
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no hooks installed"
fi

# Statusline
echo ""
echo -e "${BLUE}Statusline:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  SL_CMD=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
cmd = s.get('statusLine', {}).get('command', '')
print(cmd)
" 2>/dev/null)
  if echo "$SL_CMD" | grep -q "#supercharger"; then
    echo -e "  ${GREEN}✓${NC} Enhanced statusline — active"
  elif [ -n "$SL_CMD" ]; then
    echo -e "  ${YELLOW}○${NC} Custom statusline configured (not Supercharger)"
  else
    echo -e "  ${YELLOW}○${NC} No statusline configured"
  fi
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no statusline"
fi

# MCP Servers
echo ""
echo -e "${BLUE}MCP Servers:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
servers = s.get('mcpServers', {})
sc = {k: v for k, v in servers.items() if '#supercharger' in k}
user = {k: v for k, v in servers.items() if '#supercharger' not in k}
if sc:
    for k in sorted(sc):
        name = k.replace(' #supercharger', '')
        print(f'  \033[0;32m✓\033[0m {name}')
else:
    print('  \033[1;33m○\033[0m No Supercharger MCP servers configured')
if user:
    for k in sorted(user):
        print(f'  \033[0;34m●\033[0m {k} (user-configured)')
core = ['context7', 'sequential-thinking', 'memory']
missing = [c for c in core if not any(c in k for k in sc)]
if missing:
    print(f'  \033[0;31m✗\033[0m Missing core: {\", \".join(missing)}')
" 2>/dev/null
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no MCP servers"
fi

# Stack Detection
echo ""
echo -e "${BLUE}Detected Stack:${NC}"
DETECT_SCRIPT="$HOME/.claude/supercharger/hooks/detect-stack.sh"
if [ -f "$DETECT_SCRIPT" ]; then
  STACK_OUTPUT=$(bash "$DETECT_SCRIPT" 2>/dev/null || echo "detected=false")
  if echo "$STACK_OUTPUT" | grep -q "detected=true"; then
    LANG=$(echo "$STACK_OUTPUT" | grep '^language=' | cut -d= -f2-)
    FW=$(echo "$STACK_OUTPUT" | grep '^framework=' | cut -d= -f2-)
    PM=$(echo "$STACK_OUTPUT" | grep '^package_manager=' | cut -d= -f2-)
    TEST_FW=$(echo "$STACK_OUTPUT" | grep '^test_framework=' | cut -d= -f2-)
    BUILD=$(echo "$STACK_OUTPUT" | grep '^build_tool=' | cut -d= -f2-)
    [ -n "$LANG" ] && echo -e "  ${GREEN}✓${NC} Language: ${BOLD}${LANG}${NC}"
    [ -n "$FW" ] && echo -e "  ${GREEN}✓${NC} Framework: ${BOLD}${FW}${NC}"
    [ -n "$PM" ] && echo -e "  ${GREEN}✓${NC} Package manager: ${BOLD}${PM}${NC}"
    [ -n "$TEST_FW" ] && echo -e "  ${GREEN}✓${NC} Testing: ${BOLD}${TEST_FW}${NC}"
    [ -n "$BUILD" ] && echo -e "  ${GREEN}✓${NC} Build: ${BOLD}${BUILD}${NC}"
  else
    echo -e "  ${YELLOW}○${NC} No project files detected in current directory"
  fi
else
  echo -e "  ${YELLOW}○${NC} detect-stack not installed"
fi

# Session Summaries
echo ""
echo -e "${BLUE}Session Summaries:${NC}"
SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
if [ -d "$SUMMARIES_DIR" ] && [ -n "$(ls -A "$SUMMARIES_DIR" 2>/dev/null)" ]; then
  SUMMARY_COUNT=$(ls "$SUMMARIES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  LATEST=$(ls -t "$SUMMARIES_DIR"/*.md 2>/dev/null | head -1 | xargs basename 2>/dev/null)
  echo -e "  ${GREEN}✓${NC} ${SUMMARY_COUNT} summary file(s) — latest: ${LATEST}"
else
  echo -e "  ${YELLOW}○${NC} No session summaries yet — say 'session summary' in Claude Code"
fi

# Config Validation
echo ""
echo -e "${BLUE}Config Validation:${NC}"
LINT_ISSUES=0

# Check for empty rule files
for rule in "$HOME/.claude/rules/"*.md "$HOME/.claude/rules/"*.yml; do
  if [ -f "$rule" ] && [ ! -s "$rule" ]; then
    echo -e "  ${RED}✗${NC} Empty file: $(basename "$rule")"
    LINT_ISSUES=$((LINT_ISSUES + 1))
  fi
done

# Check CLAUDE.md size (warn if > 200 lines — wastes context)
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  LINE_COUNT=$(wc -l < "$HOME/.claude/CLAUDE.md" | tr -d ' ')
  if [ "$LINE_COUNT" -gt 200 ]; then
    echo -e "  ${YELLOW}⚠${NC} CLAUDE.md is ${LINE_COUNT} lines (>200) — may waste context tokens"
    LINT_ISSUES=$((LINT_ISSUES + 1))
  fi
fi

# Check hook scripts are executable
if [ -d "$HOME/.claude/supercharger/hooks" ]; then
  for hook_script in "$HOME/.claude/supercharger/hooks/"*.sh; do
    if [ -f "$hook_script" ] && [ ! -x "$hook_script" ]; then
      echo -e "  ${RED}✗${NC} Not executable: $(basename "$hook_script")"
      LINT_ISSUES=$((LINT_ISSUES + 1))
    fi
  done
fi

# Check for syntax errors in hook scripts
if [ -d "$HOME/.claude/supercharger/hooks" ]; then
  for hook_script in "$HOME/.claude/supercharger/hooks/"*.sh; do
    if [ -f "$hook_script" ]; then
      if ! bash -n "$hook_script" 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Syntax error: $(basename "$hook_script")"
        LINT_ISSUES=$((LINT_ISSUES + 1))
      fi
    fi
  done
fi

# Check settings.json is valid JSON
if [ -f "$HOME/.claude/settings.json" ]; then
  if ! SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "import json, os; json.load(open(os.environ['SETTINGS_PATH']))" 2>/dev/null; then
    echo -e "  ${RED}✗${NC} settings.json is malformed JSON"
    LINT_ISSUES=$((LINT_ISSUES + 1))
    ERRORS=$((ERRORS + 1))
  fi
fi

if [ "$LINT_ISSUES" -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} All config files valid"
fi

# Summary
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
if [ -n "$ROLES_FOUND" ]; then
  echo -e "Roles: ${BOLD}$ROLES_FOUND${NC}"
fi
ACTIVE_PROFILE="$HOME/.claude/supercharger/.active-profile"
if [ -f "$ACTIVE_PROFILE" ]; then
  echo -e "Profile: ${BOLD}$(cat "$ACTIVE_PROFILE")${NC}"
fi
if [ -f ".supercharger.json" ]; then
  echo -e "Project config: ${GREEN}.supercharger.json detected${NC}"
fi
echo -e "Version: ${BOLD}1.5.0${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed ✓${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) found. Run install.sh to fix.${NC}"
fi
