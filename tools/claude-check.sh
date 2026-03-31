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
for role in developer writer student data pm; do
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
for role in developer writer student data pm; do
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
  HOOK_COUNT=$(python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for h in event if '#supercharger' in h.get('command',''))
print(count)
" 2>/dev/null || echo "0")
  echo -e "  ${GREEN}✓${NC} settings.json valid — ${HOOK_COUNT} Supercharger hook(s) registered"

  if [ -d "$HOME/.claude/supercharger/hooks" ]; then
    for hook in safety notify git-safety auto-format prompt-validator compaction-backup; do
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

# MCP Servers
echo ""
echo -e "${BLUE}MCP Servers:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
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

# Tools
echo ""
echo -e "${BLUE}Tools:${NC}"
if [ -f "$HOME/.claude/claude-check.sh" ]; then
  echo -e "  ${GREEN}✓${NC} claude-check — installed"
else
  echo -e "  ${YELLOW}○${NC} claude-check — not installed (Full mode)"
fi

# Summary
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
if [ -n "$ROLES_FOUND" ]; then
  echo -e "Roles: ${BOLD}$ROLES_FOUND${NC}"
fi
echo -e "Version: ${BOLD}1.0.0${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed ✓${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) found. Run install.sh to fix.${NC}"
fi
