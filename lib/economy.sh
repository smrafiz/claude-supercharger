#!/usr/bin/env bash
# Claude Supercharger — Economy Tier Selection & Deployment

AVAILABLE_TIERS=("standard" "lean" "minimal")
TIER_LABELS=(
  "Standard  — concise, natural English (~30% reduction)"
  "Lean      — every word earns its place (~45% reduction)"
  "Minimal   — telegraphic, bare output (~60% reduction)"
)
DEFAULT_TIER="lean"
SELECTED_TIER=""

# Role constraints: role|default|floor|ceiling
# Empty floor/ceiling = unrestricted
ROLE_CONSTRAINTS=(
  "developer|lean||"
  "student|standard|standard|lean"
  "writer|standard|standard|"
  "data|lean||"
  "pm|lean||"
)

# Map tier name to numeric rank for comparison
tier_rank() {
  case "$1" in
    standard) echo 1 ;;
    lean)     echo 2 ;;
    minimal)  echo 3 ;;
    *)        echo 0 ;;
  esac
}

# Map numeric rank back to tier name
rank_to_tier() {
  case "$1" in
    1) echo "standard" ;;
    2) echo "lean" ;;
    3) echo "minimal" ;;
    *) echo "lean" ;;
  esac
}

# Get the default tier for selected roles (most restrictive default)
get_default_tier_for_roles() {
  local roles="$1"
  local most_restrictive_rank=3  # start at minimal (least restrictive)

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      local rank
      rank=$(tier_rank "$default")
      if [ "$rank" -lt "$most_restrictive_rank" ]; then
        most_restrictive_rank=$rank
      fi
    fi
  done

  rank_to_tier "$most_restrictive_rank"
}

# Get the floor for selected roles (most restrictive floor)
get_floor_for_roles() {
  local roles="$1"
  local highest_floor=0  # no floor

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      if [ -n "$floor" ]; then
        local rank
        rank=$(tier_rank "$floor")
        if [ "$rank" -gt "$highest_floor" ]; then
          highest_floor=$rank
        fi
      fi
    fi
  done

  if [ "$highest_floor" -eq 0 ]; then
    echo ""
  else
    rank_to_tier "$highest_floor"
  fi
}

# Get the ceiling for selected roles (most restrictive ceiling)
get_ceiling_for_roles() {
  local roles="$1"
  local lowest_ceiling=4  # no ceiling (above minimal)

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      if [ -n "$ceiling" ]; then
        local rank
        rank=$(tier_rank "$ceiling")
        if [ "$rank" -lt "$lowest_ceiling" ]; then
          lowest_ceiling=$rank
        fi
      fi
    fi
  done

  if [ "$lowest_ceiling" -eq 4 ]; then
    echo ""
  else
    rank_to_tier "$lowest_ceiling"
  fi
}

# Validate tier against role constraints, return corrected tier
validate_tier_for_roles() {
  local tier="$1"
  local roles="$2"
  local tier_r
  tier_r=$(tier_rank "$tier")

  local floor
  floor=$(get_floor_for_roles "$roles")
  if [ -n "$floor" ]; then
    local floor_r
    floor_r=$(tier_rank "$floor")
    if [ "$tier_r" -gt "$floor_r" ]; then
      # tier is more aggressive than floor allows
      warn "$(capitalize "$tier") is below the floor for your roles. Setting to $(capitalize "$floor")."
      echo "$floor"
      return
    fi
  fi

  local ceiling
  ceiling=$(get_ceiling_for_roles "$roles")
  if [ -n "$ceiling" ]; then
    local ceiling_r
    ceiling_r=$(tier_rank "$ceiling")
    if [ "$tier_r" -lt "$ceiling_r" ]; then
      warn "$(capitalize "$tier") exceeds the ceiling for your roles. Setting to $(capitalize "$ceiling")."
      echo "$ceiling"
      return
    fi
  fi

  echo "$tier"
}

capitalize() {
  echo "$(echo "${1:0:1}" | tr '[:lower:]' '[:upper:]')${1:1}"
}

# Interactive tier selection
select_economy_tier() {
  local roles="$1"

  local default_for_roles
  default_for_roles=$(get_default_tier_for_roles "$roles")

  echo ""
  info "Select token economy tier:"
  echo ""
  for i in "${!AVAILABLE_TIERS[@]}"; do
    local marker=""
    if [[ "${AVAILABLE_TIERS[$i]}" == "$default_for_roles" ]]; then
      marker=" [default]"
    fi
    echo -e "  ${BOLD}$((i+1)))${NC} ${TIER_LABELS[$i]}${marker}"
  done
  echo ""

  local input
  read -rp "> " input

  if [ -z "$input" ]; then
    SELECTED_TIER="$default_for_roles"
  elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 3 ]; then
    SELECTED_TIER="${AVAILABLE_TIERS[$((input-1))]}"
  else
    warn "Invalid selection. Defaulting to $(capitalize "$default_for_roles")."
    SELECTED_TIER="$default_for_roles"
  fi

  # Validate against role constraints
  SELECTED_TIER=$(validate_tier_for_roles "$SELECTED_TIER" "$roles")
}

# Deploy economy.md with the selected tier baked in
deploy_economy() {
  local source_dir="$1"
  local tier="$2"
  local rules_dir="$HOME/.claude/rules"
  local economy_dir="$HOME/.claude/supercharger/economy"
  mkdir -p "$rules_dir"
  mkdir -p "$economy_dir"

  # Copy all tier templates to supercharger/economy/ (for switching)
  for t in "${AVAILABLE_TIERS[@]}"; do
    local tier_file="$source_dir/configs/economy/${t}.md"
    if [ -f "$tier_file" ]; then
      cp "$tier_file" "$economy_dir/${t}.md"
    fi
  done

  # Read the selected tier content
  local tier_content=""
  local tier_file="$source_dir/configs/economy/${tier}.md"
  if [ -f "$tier_file" ]; then
    tier_content=$(cat "$tier_file")
  else
    warn "Tier file not found: ${tier}.md. Falling back to lean."
    tier_content=$(cat "$source_dir/configs/economy/lean.md")
  fi

  # Build economy.md with active tier injected
  local economy_template="$source_dir/configs/universal/economy.md"
  if [ -f "$economy_template" ]; then
    # Replace {{ACTIVE_TIER}} placeholder with tier content
    python3 -c "
import sys

with open('$economy_template', 'r') as f:
    template = f.read()

tier_content = '''$tier_content'''

result = template.replace('{{ACTIVE_TIER}}', tier_content)

with open('$rules_dir/economy.md', 'w') as f:
    f.write(result)
"
  fi

  success "Token economy installed ($(capitalize "$tier") tier)"
}

# Get economy constraint lines for a role file
get_role_economy_lines() {
  local role="$1"

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r c_role c_default c_floor c_ceiling <<< "$constraint"
    if [[ "$c_role" == "$role" ]]; then
      local range="unrestricted"
      if [ -n "$c_floor" ] && [ -n "$c_ceiling" ]; then
        range="$(capitalize "$c_floor")–$(capitalize "$c_ceiling")"
      elif [ -n "$c_floor" ]; then
        range="$(capitalize "$c_floor")–unrestricted"
      elif [ -n "$c_ceiling" ]; then
        range="unrestricted–$(capitalize "$c_ceiling")"
      fi
      echo "Default economy: $(capitalize "$c_default")"
      echo "Economy range: $range"
      return
    fi
  done

  # Fallback
  echo "Default economy: Lean"
  echo "Economy range: unrestricted"
}
