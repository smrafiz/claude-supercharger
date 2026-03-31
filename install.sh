#!/usr/bin/env bash
set -euo pipefail
umask 077

# Resolve source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/roles.sh"
source "$SCRIPT_DIR/lib/hooks.sh"
source "$SCRIPT_DIR/lib/extras.sh"

detect_platform

# Step 1: Banner + Mode
show_banner
echo -e "${BOLD}Step 1 of 4: Install Mode${NC}"
echo ""
echo -e "  ${BOLD}1)${NC} Safe       — configs + safety hooks only"
echo -e "  ${BOLD}2)${NC} Standard   — recommended (configs + hooks + productivity)"
echo -e "  ${BOLD}3)${NC} Full       — everything (+ MCP setup + diagnostics)"
echo ""
read -rp "> " mode_choice
case "$mode_choice" in
  1) MODE="safe" ;;
  3) MODE="full" ;;
  *) MODE="standard" ;;
esac
echo ""

# Step 2: Roles
echo -e "${BOLD}Step 2 of 4: Your Roles${NC}"
select_roles
echo ""

# Check if Developer role is selected
HAS_DEVELOPER="false"
for role in "${SELECTED_ROLES[@]}"; do
  [[ "$role" == "developer" ]] && HAS_DEVELOPER="true"
done

# Step 3: Existing config handling
echo -e "${BOLD}Step 3 of 4: Existing Config${NC}"
echo ""

CLAUDE_MD_ACTION="deploy"
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  info "Found existing CLAUDE.md"
  echo ""
  echo -e "  ${BOLD}1)${NC} Merge   — append Supercharger to your existing file"
  echo -e "  ${BOLD}2)${NC} Replace — back up yours, use Supercharger's"
  echo -e "  ${BOLD}3)${NC} Skip    — keep yours, install everything else"
  echo ""
  read -rp "> " claude_choice
  case "$claude_choice" in
    1) CLAUDE_MD_ACTION="merge" ;;
    3) CLAUDE_MD_ACTION="skip" ;;
    *) CLAUDE_MD_ACTION="replace" ;;
  esac
  echo ""
fi

SETTINGS_ACTION="deploy"
if [ -f "$HOME/.claude/settings.json" ]; then
  info "Found existing settings.json"
  echo ""
  echo -e "  ${BOLD}1)${NC} Merge   — add Supercharger hooks to your config"
  echo -e "  ${BOLD}2)${NC} Replace — back up yours, use Supercharger's"
  echo -e "  ${BOLD}3)${NC} Skip    — keep yours, no hooks installed"
  echo ""
  read -rp "> " settings_choice
  case "$settings_choice" in
    1) SETTINGS_ACTION="merge" ;;
    3) SETTINGS_ACTION="skip" ;;
    *) SETTINGS_ACTION="replace" ;;
  esac
  echo ""
fi

# Step 4: Install
echo -e "${BOLD}Step 4 of 4: Installing...${NC}"
echo ""

# Ensure directories exist
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/shared"

# Backup
create_backup

# Deploy CLAUDE.md
ROLES_LIST=$(format_roles_list)
MODE_LABEL=$(echo "$MODE" | sed 's/^./\U&/')

if [[ "$CLAUDE_MD_ACTION" == "deploy" || "$CLAUDE_MD_ACTION" == "replace" ]]; then
  sed -e "s/{{ROLES}}/$ROLES_LIST/g" -e "s/{{MODE}}/$MODE_LABEL/g" \
    "$SCRIPT_DIR/configs/universal/CLAUDE.md" > "$HOME/.claude/CLAUDE.md"
  success "Universal config installed"
elif [[ "$CLAUDE_MD_ACTION" == "merge" ]]; then
  # Remove existing Supercharger block if present
  if grep -q "^# --- Claude Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    sed -i.bak '/^# --- Claude Supercharger/,$d' "$HOME/.claude/CLAUDE.md"
    rm -f "$HOME/.claude/CLAUDE.md.bak"
  fi
  # Append Supercharger block
  cat >> "$HOME/.claude/CLAUDE.md" << MERGEBLOCK

# --- Claude Supercharger v${VERSION} ---
# Do not edit below this line. Managed by Supercharger.
# To remove: run uninstall.sh or delete this block.
# Roles: ${ROLES_LIST} | Mode: ${MODE_LABEL}
MERGEBLOCK
  success "Universal config merged (your CLAUDE.md preserved)"
elif [[ "$CLAUDE_MD_ACTION" == "skip" ]]; then
  info "Skipped CLAUDE.md"
fi

# Deploy universal rules
cp "$SCRIPT_DIR/configs/universal/supercharger.md" "$HOME/.claude/rules/supercharger.md"
success "Universal rules installed"

cp "$SCRIPT_DIR/configs/universal/guardrails.md" "$HOME/.claude/rules/guardrails.md"
success "Guardrails installed"

# Deploy roles
deploy_roles "$SCRIPT_DIR"

# Deploy shared assets
cp "$SCRIPT_DIR/shared/anti-patterns.yml" "$HOME/.claude/shared/anti-patterns.yml"
success "Anti-patterns library installed"

# Deploy hooks
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  deploy_hook_scripts "$SCRIPT_DIR"

  if [[ "$SETTINGS_ACTION" == "replace" ]] && [ -f "$HOME/.claude/settings.json" ]; then
    rm "$HOME/.claude/settings.json"
  fi

  if merge_hooks_into_settings "$MODE" "$HAS_DEVELOPER"; then
    HOOK_COUNT=$(count_installed_hooks "$MODE" "$HAS_DEVELOPER")
    success "${HOOK_COUNT} hook(s) installed (${MODE_LABEL} mode)"
  else
    error "Failed to configure hooks. Run claude-check for details."
  fi
else
  info "Skipped hooks installation"
fi

# Deploy extras (Full mode)
deploy_extras "$SCRIPT_DIR" "$MODE"

# Summary
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done! Claude Supercharger v${VERSION} installed.${NC}"
echo ""
echo -e "  Mode:  ${BOLD}${MODE_LABEL}${NC}"
echo -e "  Roles: ${BOLD}${ROLES_LIST}${NC}"
echo ""
if [[ "$MODE" == "full" ]]; then
  echo -e "  Run ${BOLD}claude-check${NC} to verify installation."
else
  echo -e "  Upgrade anytime: ${BOLD}./install.sh${NC} (choose Full)"
fi
echo ""
