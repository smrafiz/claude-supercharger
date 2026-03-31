#!/usr/bin/env bash
# Claude Supercharger — Role Selection & Deployment

AVAILABLE_ROLES=("developer" "writer" "student" "data" "pm")
ROLE_LABELS=("Developer — build things" "Writer — communicate things" "Student — learn things" "Data — analyze things" "PM — plan things")
SELECTED_ROLES=()

select_roles() {
  echo ""
  info "Which roles describe you best? (comma-separated, or 'all')"
  info "These will be your default. All roles are available via mode switching."
  echo ""
  for i in "${!AVAILABLE_ROLES[@]}"; do
    echo -e "  ${BOLD}$((i+1)))${NC} ${ROLE_LABELS[$i]}"
  done
  echo ""

  local input
  read -rp "> " input

  if [[ "$input" == "all" ]]; then
    SELECTED_ROLES=("${AVAILABLE_ROLES[@]}")
    return
  fi

  IFS=',' read -ra selections <<< "$input"
  for sel in "${selections[@]}"; do
    sel=$(echo "$sel" | tr -d ' ')
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#AVAILABLE_ROLES[@]}" ]; then
      SELECTED_ROLES+=("${AVAILABLE_ROLES[$((sel-1))]}")
    else
      warn "Invalid selection: $sel (skipping)"
    fi
  done

  if [ ${#SELECTED_ROLES[@]} -eq 0 ]; then
    warn "No valid roles selected. Defaulting to Writer."
    SELECTED_ROLES=("writer")
  fi
}

deploy_roles() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/rules"
  mkdir -p "$target_dir"

  # Install ALL roles (enables mid-conversation mode switching)
  for role in "${AVAILABLE_ROLES[@]}"; do
    local role_file="$source_dir/configs/roles/${role}.md"
    if [ -f "$role_file" ]; then
      cp "$role_file" "$target_dir/${role}.md"
    fi
  done

  # Report selected primary roles
  for role in "${SELECTED_ROLES[@]}"; do
    success "Primary role: ${role}"
  done
  if [ ${#SELECTED_ROLES[@]} -lt ${#AVAILABLE_ROLES[@]} ]; then
    info "  All 5 roles installed (mode switching enabled)"
  fi
}

format_roles_list() {
  local result=""
  for role in "${SELECTED_ROLES[@]}"; do
    local capitalized
    capitalized="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    if [ -n "$result" ]; then
      result="$result, $capitalized"
    else
      result="$capitalized"
    fi
  done
  echo "$result"
}
