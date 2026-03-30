#!/usr/bin/env bash
set -euo pipefail

# Claude Supercharger v1.0.0 Uninstaller

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}╔═══════════════════════════════════════════╗${NC}"
echo -e "${RED}║  Claude Supercharger v1.0.0 Uninstaller ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════╝${NC}"
echo ""

# Confirm uninstall
read -p "Are you sure you want to uninstall Claude Supercharger? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Uninstall cancelled.${NC}"
    exit 0
fi

# Find most recent backup
BACKUP_DIR=$(ls -dt ~/.claude/backups/*/ 2>/dev/null | head -1)

if [ -n "$BACKUP_DIR" ]; then
    echo -e "${BLUE}📦 Found backup: $BACKUP_DIR${NC}"
    read -p "Restore from this backup? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}🔄 Restoring backup...${NC}"
        cp "$BACKUP_DIR"/*.md ~/.claude/ 2>/dev/null || true
        if [ -d "$BACKUP_DIR/shared" ]; then
            cp -r "$BACKUP_DIR/shared" ~/.claude/ 2>/dev/null || true
        fi
        echo -e "${GREEN}✓ Backup restored${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  No backup found. Removing Claude Supercharger files only.${NC}"
fi

# Remove Claude Supercharger-specific files
echo -e "${BLUE}🗑️  Removing Claude Supercharger files...${NC}"
rm -f ~/.claude/shared/anti-patterns.yml

echo -e "${GREEN}✓ Uninstall complete${NC}"
echo ""
echo -e "${YELLOW}Note: Core files (CLAUDE.md, RULES.md, MCP.md, PERSONAS.md) were${NC}"
echo -e "${YELLOW}restored from backup if available. If no backup existed, they remain unchanged.${NC}"
echo ""
