#!/usr/bin/env bash
set -euo pipefail

# Claude Supercharger v1.0.0 Installer
# One-command installation for Claude Code configuration

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Supercharger v1.0.0 Installer ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# Check if ~/.claude directory exists
if [ ! -d ~/.claude ]; then
    echo -e "${YELLOW}⚠️  ~/.claude directory not found. Creating...${NC}"
    mkdir -p ~/.claude
fi

# Backup existing configuration
BACKUP_DIR=~/.claude/backups/$(date +%Y%m%d-%H%M%S)
if [ -f ~/.claude/CLAUDE.md ] || [ -f ~/.claude/RULES.md ]; then
    echo -e "${BLUE}📦 Creating backup at $BACKUP_DIR${NC}"
    mkdir -p "$BACKUP_DIR"
    cp ~/.claude/*.md "$BACKUP_DIR/" 2>/dev/null || true
    cp -r ~/.claude/shared "$BACKUP_DIR/" 2>/dev/null || true
    echo -e "${GREEN}✓ Backup created${NC}"
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install core files
echo -e "${BLUE}📥 Installing core files...${NC}"
cp "$SCRIPT_DIR/core/CLAUDE.md" ~/.claude/
cp "$SCRIPT_DIR/core/RULES.md" ~/.claude/
cp "$SCRIPT_DIR/core/MCP.md" ~/.claude/
cp "$SCRIPT_DIR/core/PERSONAS.md" ~/.claude/
echo -e "${GREEN}✓ Core files installed${NC}"

# Install shared resources
echo -e "${BLUE}📥 Installing shared resources...${NC}"
mkdir -p ~/.claude/shared
cp "$SCRIPT_DIR/shared/anti-patterns.yml" ~/.claude/shared/
echo -e "${GREEN}✓ Shared resources installed${NC}"

# Verify installation
echo ""
echo -e "${BLUE}🔍 Verifying installation...${NC}"

if grep -q "Claude Supercharger v1.0.0" ~/.claude/RULES.md 2>/dev/null; then
    echo -e "${GREEN}✓ RULES.md Claude Supercharger v1.0.0 verified${NC}"
else
    echo -e "${RED}✗ RULES.md verification failed${NC}"
    exit 1
fi

if grep -q "Claude Supercharger v1.0.0" ~/.claude/MCP.md 2>/dev/null; then
    echo -e "${GREEN}✓ MCP.md Claude Supercharger v1.0.0 verified${NC}"
else
    echo -e "${RED}✗ MCP.md verification failed${NC}"
    exit 1
fi

if [ -f ~/.claude/shared/anti-patterns.yml ]; then
    echo -e "${GREEN}✓ anti-patterns.yml verified${NC}"
else
    echo -e "${RED}✗ anti-patterns.yml verification failed${NC}"
    exit 1
fi

# Success message
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✓ Installation Successful!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Claude Supercharger v1.0.0 is now active (config: Claude Supercharger v1.0.0).${NC}"
echo ""
echo -e "${YELLOW}What's new:${NC}"
echo "  • 35 Anti-Pattern Detection"
echo "  • 9-Dimensional Intent Extraction"
echo "  • Tool-Specific Optimization (10+ models)"
echo "  • 10-Point Verification Gate"
echo "  • Memory Block System"
echo "  • Output Lock Discipline"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Restart Claude Code (if running)"
echo "  2. Try: 'fix the login bug' → See anti-pattern detection"
echo "  3. Try: '/persona:architect' → Activate system design mode"
echo "  4. Read docs: $SCRIPT_DIR/docs/"
echo ""
echo -e "${YELLOW}Backup location: $BACKUP_DIR${NC}"
echo -e "${YELLOW}Uninstall: bash $SCRIPT_DIR/uninstall.sh${NC}"
echo ""
