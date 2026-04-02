#!/usr/bin/env bash
# Claude Supercharger — Import Preset
# Applies a .supercharger preset file from a teammate.
# Usage: bash tools/import-preset.sh <preset-file>

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "${1:-}" ]; then
  echo "Usage: bash tools/import-preset.sh <preset-file>"
  echo ""
  echo "Example: bash tools/import-preset.sh team.supercharger"
  exit 1
fi

PRESET_FILE="$1"

if [ ! -f "$PRESET_FILE" ]; then
  echo -e "${RED}File not found: ${PRESET_FILE}${NC}" >&2
  exit 1
fi

# Parse preset
PARSED=$(PRESET_FILE="$PRESET_FILE" python3 -c "
import json, sys, os

try:
    with open(os.environ['PRESET_FILE']) as f:
        preset = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)

mode = preset.get('mode', 'standard')
roles = ','.join(preset.get('roles', ['developer']))
economy = preset.get('economy', 'lean')

print(f'{mode}|{roles}|{economy}')
" 2>/dev/null) || {
  echo -e "${RED}Invalid preset file.${NC}" >&2
  exit 1
}

IFS='|' read -r MODE ROLES ECONOMY <<< "$PARSED"

echo -e "${CYAN}Importing preset from ${BOLD}${PRESET_FILE}${NC}"
echo -e "  Mode: ${BOLD}${MODE}${NC}"
echo -e "  Roles: ${BOLD}${ROLES}${NC}"
echo -e "  Economy: ${BOLD}${ECONOMY}${NC}"
echo ""

# Find the install.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$SCRIPT_DIR/install.sh"

if [ ! -f "$INSTALLER" ]; then
  # Try the cloned repo location
  if [ -f "$HOME/.claude/supercharger/install.sh" ]; then
    INSTALLER="$HOME/.claude/supercharger/install.sh"
  else
    echo -e "${RED}Cannot find install.sh. Run from the Supercharger repo directory.${NC}" >&2
    exit 1
  fi
fi

# Run installer non-interactively with preset values
bash "$INSTALLER" --mode "$MODE" --roles "$ROLES" --economy "$ECONOMY" --config merge --settings merge

echo ""
echo -e "${GREEN}Preset applied successfully.${NC}"
