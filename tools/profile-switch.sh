#!/usr/bin/env bash
# Claude Supercharger — Profile Switch Tool
# Usage:
#   bash tools/profile-switch.sh <name>          — switch to a profile
#   bash tools/profile-switch.sh --list           — list available profiles
#   bash tools/profile-switch.sh --save <name>    — save current config as a profile
#   bash tools/profile-switch.sh --current        — show active profile
#   bash tools/profile-switch.sh --delete <name>  — delete a profile

set -euo pipefail

PROFILES_DIR="$HOME/.claude/supercharger/profiles"
ROLES_DIR="$HOME/.claude/supercharger/roles"
RULES_DIR="$HOME/.claude/rules"
ECONOMY_DIR="$HOME/.claude/supercharger/economy"
SETTINGS_FILE="$HOME/.claude/settings.json"
ACTIVE_FILE="$HOME/.claude/supercharger/.active-profile"

ALL_ROLES=("developer" "writer" "student" "data" "pm" "designer" "devops" "researcher")

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "  ${BLUE}ℹ${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1" >&2; }

mkdir -p "$PROFILES_DIR"

# --- Show usage ---
show_usage() {
  echo -e "${CYAN}Claude Supercharger — Profile Switch${NC}"
  echo ""
  echo "Usage:"
  echo "  bash tools/profile-switch.sh <name>          Switch to a profile"
  echo "  bash tools/profile-switch.sh --list           List available profiles"
  echo "  bash tools/profile-switch.sh --save <name>    Save current config as a profile"
  echo "  bash tools/profile-switch.sh --current        Show active profile"
  echo "  bash tools/profile-switch.sh --delete <name>  Delete a profile"
  echo ""
  echo "Built-in profiles: frontend-dev, backend-dev, data-analyst, tech-writer, team-lead"
  exit 0
}

# --- List profiles ---
list_profiles() {
  echo -e "${CYAN}Available Profiles:${NC}"
  echo ""

  # Built-in
  echo -e "  ${BOLD}Built-in:${NC}"
  echo -e "    frontend-dev    — Developer+Designer, Lean, Playwright+Magic UI"
  echo -e "    backend-dev     — Developer+DevOps, Lean, Playwright"
  echo -e "    data-analyst    — Data+Researcher, Standard, DuckDuckGo"
  echo -e "    tech-writer     — Writer+Researcher, Standard, DuckDuckGo"
  echo -e "    team-lead       — Developer+PM, Lean, Playwright+Magic UI"

  # User profiles
  local user_count=0
  if [ -d "$PROFILES_DIR" ]; then
    for f in "$PROFILES_DIR"/*.json; do
      [ -f "$f" ] || continue
      user_count=$((user_count + 1))
      if [ "$user_count" -eq 1 ]; then
        echo ""
        echo -e "  ${BOLD}Custom:${NC}"
      fi
      local name
      name=$(basename "$f" .json)
      local roles economy
      roles=$(PROFILE_FILE="$f" python3 -c "import json, os; print(', '.join(json.load(open(os.environ['PROFILE_FILE'])).get('roles',[])))" 2>/dev/null || echo "?")
      economy=$(PROFILE_FILE="$f" python3 -c "import json, os; print(json.load(open(os.environ['PROFILE_FILE'])).get('economy','?'))" 2>/dev/null || echo "?")
      echo -e "    ${name}    — ${roles}, ${economy}"
    done
  fi

  if [ "$user_count" -eq 0 ]; then
    echo ""
    echo -e "  ${BOLD}Custom:${NC} (none — use --save to create)"
  fi

  # Active
  echo ""
  if [ -f "$ACTIVE_FILE" ]; then
    echo -e "  Active: ${GREEN}$(cat "$ACTIVE_FILE")${NC}"
  else
    echo -e "  Active: ${YELLOW}(default install)${NC}"
  fi
}

# --- Get built-in profile ---
get_builtin_profile() {
  local name="$1"
  case "$name" in
    frontend-dev)  echo '{"roles":["developer","designer"],"economy":"lean"}' ;;
    backend-dev)   echo '{"roles":["developer","devops"],"economy":"lean"}' ;;
    data-analyst)  echo '{"roles":["data","researcher"],"economy":"standard"}' ;;
    tech-writer)   echo '{"roles":["writer","researcher"],"economy":"standard"}' ;;
    team-lead)     echo '{"roles":["developer","pm"],"economy":"lean"}' ;;
    *) echo "" ;;
  esac
}

# --- Read profile (built-in or custom) ---
read_profile() {
  local name="$1"
  local profile=""

  # Try built-in first
  profile=$(get_builtin_profile "$name")
  if [ -n "$profile" ]; then
    echo "$profile"
    return 0
  fi

  # Try custom
  local custom_file="$PROFILES_DIR/${name}.json"
  if [ -f "$custom_file" ]; then
    cat "$custom_file"
    return 0
  fi

  return 1
}

# --- Save current config as profile ---
save_profile() {
  local name="$1"

  # Validate profile name — prevent path traversal
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Profile name must contain only letters, numbers, hyphens, underscores"
    exit 1
  fi

  # Detect current roles from rules/
  local roles=()
  for role in "${ALL_ROLES[@]}"; do
    if [ -f "$RULES_DIR/${role}.md" ]; then
      roles+=("$role")
    fi
  done

  if [ ${#roles[@]} -eq 0 ]; then
    error "No roles found in $RULES_DIR"
    exit 1
  fi

  # Detect current economy tier
  local economy="lean"
  if [ -f "$RULES_DIR/economy.md" ]; then
    economy=$(ECONOMY_FILE="$RULES_DIR/economy.md" python3 -c "
import re, os
with open(os.environ['ECONOMY_FILE']) as f:
    content = f.read()
m = re.search(r'Active tier:\s*(\w+)', content, re.IGNORECASE)
if m:
    print(m.group(1).lower())
else:
    for tier in ['minimal', 'lean', 'standard']:
        if tier.upper() in content[:500]:
            print(tier)
            break
    else:
        print('lean')
" 2>/dev/null || echo "lean")
  fi

  # Build JSON
  PROFILE_NAME="$name" PROFILE_ROLES="$(IFS=,; echo "${roles[*]}")" PROFILE_ECONOMY="$economy" python3 -c "
import json, os

roles = os.environ['PROFILE_ROLES'].split(',')
economy = os.environ['PROFILE_ECONOMY']
name = os.environ['PROFILE_NAME']

profile = {
    'name': name,
    'roles': roles,
    'economy': economy
}

profiles_dir = os.path.expanduser('~/.claude/supercharger/profiles')
os.makedirs(profiles_dir, exist_ok=True)

with open(os.path.join(profiles_dir, name + '.json'), 'w') as f:
    json.dump(profile, f, indent=2)
"

  success "Profile '${name}' saved to $PROFILES_DIR/${name}.json"
  echo -e "    Roles: ${BOLD}$(IFS=', '; echo "${roles[*]}")${NC}"
  echo -e "    Economy: ${BOLD}${economy}${NC}"
}

# --- Apply profile ---
apply_profile() {
  local name="$1"

  # Validate profile name — prevent path traversal
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Profile name must contain only letters, numbers, hyphens, underscores"
    exit 1
  fi

  local profile_json

  profile_json=$(read_profile "$name") || {
    error "Profile '${name}' not found."
    echo ""
    echo "Available: frontend-dev, backend-dev, data-analyst, tech-writer, team-lead"
    echo "Or custom profiles in $PROFILES_DIR/"
    exit 1
  }

  # Parse profile
  local roles_csv economy
  roles_csv=$(echo "$profile_json" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin)['roles']))")
  economy=$(echo "$profile_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('economy','lean'))")

  echo -e "${CYAN}Switching to profile: ${BOLD}${name}${NC}"
  echo ""

  # 1. Remove old role files from rules/
  for role in "${ALL_ROLES[@]}"; do
    rm -f "$RULES_DIR/${role}.md"
  done

  # 2. Deploy new roles from supercharger/roles/
  IFS=',' read -ra role_arr <<< "$roles_csv"
  for role in "${role_arr[@]}"; do
    local src="$ROLES_DIR/${role}.md"
    if [ -f "$src" ]; then
      cp "$src" "$RULES_DIR/${role}.md"
      success "Role: ${role}"
    else
      warn "Role file not found: ${role}.md"
    fi
  done

  # 3. Re-deploy economy tier
  local economy_src="$ECONOMY_DIR/${economy}.md"
  local economy_template="$ECONOMY_DIR/../economy-template.md"

  # Try to rebuild economy.md from template
  if [ -f "$RULES_DIR/economy.md" ] && [ -f "$economy_src" ]; then
    local tier_content
    tier_content=$(cat "$economy_src")
    TIER_CONTENT="$tier_content" python3 -c "
import os

economy_file = os.path.expanduser('~/.claude/rules/economy.md')
with open(economy_file, 'r') as f:
    content = f.read()

# Replace the active tier section (between markers if they exist)
# Simple approach: find the tier-specific section and replace
tier_content = os.environ['TIER_CONTENT']

# Look for tier header patterns and replace
import re
# Replace content between '## Active Tier' and the next '##' or end
pattern = r'(## Active Tier[^\n]*\n).*?(?=\n## |\Z)'
if re.search(pattern, content, re.DOTALL):
    content = re.sub(pattern, r'\1' + tier_content, content, flags=re.DOTALL)
else:
    # Fallback: append
    content += '\n\n## Active Tier\n' + tier_content

with open(economy_file, 'w') as f:
    f.write(content)
" 2>/dev/null
    success "Economy: ${economy}"
  elif [ -f "$economy_src" ]; then
    cp "$economy_src" "$RULES_DIR/economy.md"
    success "Economy: ${economy} (basic deploy)"
  fi

  # 4. Re-merge MCP servers for new roles
  if [ -f "$SETTINGS_FILE" ]; then
    # Source MCP library to re-merge
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$SCRIPT_DIR/lib/mcp.sh" ]; then
      source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || true
      source "$SCRIPT_DIR/lib/mcp.sh"
      if merge_mcp_into_settings "$roles_csv" 2>/dev/null; then
        local mcp_count
        mcp_count=$(count_mcp_servers "$roles_csv")
        success "MCP servers: ${mcp_count} configured"
      fi
    fi
  fi

  # 5. Save active profile marker
  echo "$name" > "$ACTIVE_FILE"

  echo ""
  echo -e "${GREEN}Profile '${name}' active.${NC}"
}

# --- Delete profile ---
delete_profile() {
  local name="$1"

  # Validate profile name — prevent path traversal
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Profile name must contain only letters, numbers, hyphens, underscores"
    exit 1
  fi

  # Don't allow deleting built-ins
  if [ -n "$(get_builtin_profile "$name")" ]; then
    error "Cannot delete built-in profile '${name}'."
    exit 1
  fi

  local file="$PROFILES_DIR/${name}.json"
  if [ -f "$file" ]; then
    rm "$file"
    success "Profile '${name}' deleted."
    # Clear active marker if this was the active profile
    if [ -f "$ACTIVE_FILE" ] && [ "$(cat "$ACTIVE_FILE")" = "$name" ]; then
      rm "$ACTIVE_FILE"
    fi
  else
    error "Profile '${name}' not found."
    exit 1
  fi
}

# --- Show current ---
show_current() {
  if [ -f "$ACTIVE_FILE" ]; then
    echo -e "Active profile: ${GREEN}$(cat "$ACTIVE_FILE")${NC}"
  else
    echo -e "Active profile: ${YELLOW}(default install)${NC}"
  fi

  echo ""
  echo -e "${BOLD}Current roles:${NC}"
  for role in "${ALL_ROLES[@]}"; do
    if [ -f "$RULES_DIR/${role}.md" ]; then
      echo -e "  ${GREEN}✓${NC} ${role}"
    fi
  done
}

# --- Main ---
if [ $# -eq 0 ]; then
  show_usage
fi

case "$1" in
  --help|-h)     show_usage ;;
  --list|-l)     list_profiles ;;
  --current|-c)  show_current ;;
  --save|-s)
    if [ -z "${2:-}" ]; then
      error "Usage: profile-switch.sh --save <name>"
      exit 1
    fi
    save_profile "$2"
    ;;
  --delete|-d)
    if [ -z "${2:-}" ]; then
      error "Usage: profile-switch.sh --delete <name>"
      exit 1
    fi
    delete_profile "$2"
    ;;
  -*)
    error "Unknown option: $1"
    show_usage
    ;;
  *)
    apply_profile "$1"
    ;;
esac
