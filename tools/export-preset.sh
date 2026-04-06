#!/usr/bin/env bash
# Claude Supercharger — Export Preset
# Exports current config as a .supercharger file for team sharing.
# Usage: bash tools/export-preset.sh [output-file]

set -euo pipefail

RULES_DIR="$HOME/.claude/rules"
ALL_ROLES=("developer" "writer" "student" "data" "pm" "designer" "devops" "researcher")

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OUTPUT="${1:-team.supercharger}"

# Detect current roles
ROLES=()
for role in "${ALL_ROLES[@]}"; do
  if [ -f "$RULES_DIR/${role}.md" ]; then
    ROLES+=("$role")
  fi
done

if [ ${#ROLES[@]} -eq 0 ]; then
  echo -e "${RED}No roles found. Is Supercharger installed?${NC}" >&2
  exit 1
fi

# Detect economy tier
ECONOMY="lean"
if [ -f "$RULES_DIR/economy.md" ]; then
  ECONOMY=$(ECONOMY_FILE="$RULES_DIR/economy.md" python3 -c "
import re, os
with open(os.environ['ECONOMY_FILE']) as f:
    content = f.read()
for tier in ['minimal', 'lean', 'standard']:
    if tier.upper() in content[:500] or ('Active tier' in content and tier in content.lower()):
        print(tier)
        break
else:
    print('lean')
" 2>/dev/null || echo "lean")
fi

# Detect mode from hook count
MODE="safe"
if [ -f "$HOME/.claude/settings.json" ]; then
  MODE=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS_PATH']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command',''))
if count >= 8:
    print('full')
elif count >= 5:
    print('standard')
else:
    print('safe')
" 2>/dev/null || echo "safe")
fi

# Build preset
ROLES_JSON=$(printf '%s\n' "${ROLES[@]}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))")

OUTPUT_FILE="$OUTPUT" PRESET_MODE="$MODE" PRESET_ECONOMY="$ECONOMY" python3 -c "
import json, os

preset = {
    'version': '1.9.0',
    'mode': os.environ['PRESET_MODE'],
    'roles': $ROLES_JSON,
    'economy': os.environ['PRESET_ECONOMY']
}

with open(os.environ['OUTPUT_FILE'], 'w') as f:
    json.dump(preset, f, indent=2)
"

echo -e "${GREEN}Preset exported to ${BOLD}${OUTPUT}${NC}"
echo -e "  Mode: ${BOLD}${MODE}${NC}"
echo -e "  Roles: ${BOLD}$(IFS=', '; echo "${ROLES[*]}")${NC}"
echo -e "  Economy: ${BOLD}${ECONOMY}${NC}"
echo ""
echo -e "Share this file with your team. They import with:"
echo -e "  ${CYAN}bash tools/import-preset.sh ${OUTPUT}${NC}"
