#!/usr/bin/env bash
set -euo pipefail

# Resolve source directory (tools/ → repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/economy.sh"

ECONOMY_FILE="$HOME/.claude/rules/economy.md"
ECONOMY_DIR="$HOME/.claude/supercharger/economy"
ROLES_DIR="$HOME/.claude/rules"

show_usage() {
  echo "Usage: economy-switch.sh [standard|lean|minimal]"
  echo ""
  echo "Switches the active token economy tier."
  echo "Takes effect on next Claude Code session."
  exit 0
}

# Get currently active roles from rules/
get_active_roles() {
  local roles=""
  for role in developer writer student data pm; do
    if [ -f "$ROLES_DIR/${role}.md" ]; then
      if [ -n "$roles" ]; then
        roles="$roles,$role"
      else
        roles="$role"
      fi
    fi
  done
  echo "$roles"
}

# --- Main ---
if [ $# -eq 0 ] || [[ "$1" == "--help" ]]; then
  show_usage
fi

TIER=$(echo "$1" | tr '[:upper:]' '[:lower:]')

# Validate tier name
if [[ "$TIER" != "standard" && "$TIER" != "lean" && "$TIER" != "minimal" ]]; then
  error "Unknown tier: $TIER"
  echo "  Valid tiers: standard, lean, minimal"
  exit 1
fi

# Check economy.md exists
if [ ! -f "$ECONOMY_FILE" ]; then
  error "economy.md not found at $ECONOMY_FILE"
  echo "  Run install.sh first."
  exit 1
fi

# Check tier template exists
TIER_FILE="$ECONOMY_DIR/${TIER}.md"
if [ ! -f "$TIER_FILE" ]; then
  error "Tier template not found: $TIER_FILE"
  echo "  Re-run install.sh to restore economy files."
  exit 1
fi

# Validate against active roles
ACTIVE_ROLES=$(get_active_roles)
if [ -n "$ACTIVE_ROLES" ]; then
  VALIDATED_TIER=$(validate_tier_for_roles "$TIER" "$ACTIVE_ROLES")
else
  VALIDATED_TIER="$TIER"
fi

# Read new tier content
NEW_TIER_CONTENT=$(cat "$TIER_FILE")

# Replace active tier block in economy.md
python3 -c "
import re

with open('$ECONOMY_FILE', 'r') as f:
    content = f.read()

# Match from '### Active Tier:' to the next '##' heading or end of file
pattern = r'### Active Tier:.*?(?=\n## |\Z)'
replacement = '''$NEW_TIER_CONTENT'''

result = re.sub(pattern, replacement.strip(), content, count=1, flags=re.DOTALL)

with open('$ECONOMY_FILE', 'w') as f:
    f.write(result)
"

success "Economy tier switched to $(capitalize "$VALIDATED_TIER")"
info "Takes effect on next Claude Code session."
