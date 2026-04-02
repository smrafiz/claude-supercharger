#!/usr/bin/env bash
set -euo pipefail
umask 077

# Resolve source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/hooks.sh"
source "$SCRIPT_DIR/lib/mcp.sh"

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║  Claude Supercharger v${VERSION} Uninstaller   ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

read -rp "Are you sure you want to uninstall Claude Supercharger? (y/N): " -n 1
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Uninstall cancelled.${NC}"
  exit 0
fi

# Find most recent backup
BACKUP_DIR=""
if [ -d "$HOME/.claude/backups" ]; then
  for d in "$HOME/.claude/backups"/*/; do
    [ -d "$d" ] && BACKUP_DIR="$d"
  done
fi

RESTORE="false"
if [ -n "$BACKUP_DIR" ]; then
  echo -e "${BLUE}Found backup: $BACKUP_DIR${NC}"
  read -rp "Restore from this backup? (Y/n): " -n 1
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    RESTORE="true"
  fi
fi

echo ""
echo -e "${BLUE}Removing Supercharger...${NC}"

# Remove hooks from settings.json (uses lib/hooks.sh)
if [ -f "$HOME/.claude/settings.json" ]; then
  remove_supercharger_hooks 2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks removed from settings.json"
fi

# Remove MCP servers from both config files (uses lib/mcp.sh)
remove_supercharger_mcp 2>/dev/null && echo -e "  ${GREEN}✓${NC} MCP servers removed"

# Remove Supercharger block from CLAUDE.md
if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q "^# --- Claude Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  sed -i.bak '/^# --- Claude Supercharger/,$d' "$HOME/.claude/CLAUDE.md"
  rm -f "$HOME/.claude/CLAUDE.md.bak"
  # Remove trailing blank lines
  sed -i.bak -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HOME/.claude/CLAUDE.md"
  rm -f "$HOME/.claude/CLAUDE.md.bak"
  echo -e "  ${GREEN}✓${NC} Supercharger block removed from CLAUDE.md"
fi

# Remove Supercharger rule files
for f in supercharger.md guardrails.md economy.md developer.md writer.md student.md data.md pm.md anti-patterns.yml; do
  rm -f "$HOME/.claude/rules/$f"
done
echo -e "  ${GREEN}✓${NC} Rule files removed"

# Remove shared assets (current and legacy paths)
rm -f "$HOME/.claude/shared/anti-patterns.yml"
rm -f "$HOME/.claude/shared/guardrails-template.yml"
rmdir "$HOME/.claude/shared" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Shared assets removed"

# Remove hook scripts, roles, economy tiers, and summaries
rm -rf "$HOME/.claude/supercharger"
echo -e "  ${GREEN}✓${NC} Hook scripts, roles, economy tiers, and summaries removed"

# Remove agents installed by Supercharger (only known ones — preserve user-added agents)
for agent in code-helper debugger writer reviewer researcher planner data-analyst general architect; do
  rm -f "$HOME/.claude/agents/$agent.md"
done
rmdir "$HOME/.claude/agents" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Agents removed"

# Remove commands installed by Supercharger
for cmd in think refactor challenge audit; do
  rm -f "$HOME/.claude/commands/$cmd.md"
done
rmdir "$HOME/.claude/commands" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Commands removed"

# Remove claude-check
rm -f "$HOME/.claude/claude-check.sh"

# Restore backup if requested
if [[ "$RESTORE" == "true" ]]; then
  echo ""
  cp "${BACKUP_DIR}"*.md "$HOME/.claude/" 2>/dev/null || true
  if [ -d "${BACKUP_DIR}rules" ]; then
    cp -r "${BACKUP_DIR}rules" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -d "${BACKUP_DIR}shared" ]; then
    cp -r "${BACKUP_DIR}shared" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -f "${BACKUP_DIR}settings.json" ]; then
    cp "${BACKUP_DIR}settings.json" "$HOME/.claude/" 2>/dev/null || true
  fi
  echo -e "  ${GREEN}✓${NC} Backup restored"
fi

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo -e "${YELLOW}Note: Backup preserved at ${BACKUP_DIR:-'(no backup)'}${NC}"
echo ""
