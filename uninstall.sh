#!/usr/bin/env bash
set -euo pipefail
umask 077

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║   Claude Supercharger v1.0 Uninstaller    ║"
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

# Remove hooks from settings.json
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c "
import json, os

settings_file = os.path.expanduser('$HOME/.claude/settings.json')
tag = '#supercharger'

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' in settings:
    for event in list(settings['hooks'].keys()):
        settings['hooks'][event] = [
            h for h in settings['hooks'][event]
            if tag not in h.get('command', '')
        ]
        if not settings['hooks'][event]:
            del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks removed from settings.json"
fi

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
for f in supercharger.md guardrails.md developer.md writer.md student.md data.md pm.md; do
  rm -f "$HOME/.claude/rules/$f"
done
echo -e "  ${GREEN}✓${NC} Rule files removed"

# Remove shared assets
rm -f "$HOME/.claude/shared/anti-patterns.yml"
rm -f "$HOME/.claude/shared/guardrails-template.yml"
echo -e "  ${GREEN}✓${NC} Shared assets removed"

# Remove hook scripts
rm -rf "$HOME/.claude/supercharger"
echo -e "  ${GREEN}✓${NC} Hook scripts removed"

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
