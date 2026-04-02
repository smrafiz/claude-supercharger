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
source "$SCRIPT_DIR/lib/mcp.sh"
source "$SCRIPT_DIR/lib/economy.sh"

# --- Argument parsing ---
ARG_MODE=""
ARG_ROLES=""
ARG_CONFIG=""
ARG_SETTINGS=""
ARG_ECONOMY=""

show_usage() {
  echo "Usage: install.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --mode MODE        Install mode: safe, standard, full (default: interactive)"
  echo "  --roles ROLES      Comma-separated roles: developer,writer,student,data,pm,designer,devops,researcher"
  echo "  --config ACTION    CLAUDE.md handling: deploy, merge, replace, skip"
  echo "  --settings ACTION  settings.json handling: deploy, merge, replace, skip"
  echo "  --economy TIER     Economy tier: standard, lean, minimal (default: lean)"
  echo "  --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./install.sh                                              # Interactive"
  echo "  ./install.sh --mode standard --roles developer,pm         # Partial (prompts for rest)"
  echo "  ./install.sh --mode standard --roles developer --economy lean --config deploy --settings deploy  # Fully silent"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     ARG_MODE="$2"; shift 2 ;;
    --roles)    ARG_ROLES="$2"; shift 2 ;;
    --config)   ARG_CONFIG="$2"; shift 2 ;;
    --settings) ARG_SETTINGS="$2"; shift 2 ;;
    --economy)  ARG_ECONOMY="$2"; shift 2 ;;
    --help)     show_usage ;;
    *)          echo "Unknown option: $1"; show_usage ;;
  esac
done

detect_platform

# Detect first-time user
FIRST_TIME="false"
if [ ! -d "$HOME/.claude" ] || [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
  FIRST_TIME="true"
fi

# Step 1: Banner + Mode
show_banner

if [[ "$FIRST_TIME" == "true" ]] && [ -z "$ARG_MODE" ]; then
  echo -e "${CYAN}Welcome! Looks like this is your first time with Claude Supercharger.${NC}"
  echo ""
  echo -e "  Supercharger configures Claude Code to be safer, more focused, and more efficient."
  echo -e "  It deploys to ${BOLD}~/.claude/${NC} — Claude Code's native config directory."
  echo ""
  echo -e "  ${BOLD}What you'll choose:${NC}"
  echo -e "    1. Install mode — how many features to enable"
  echo -e "    2. Roles — what kind of work you do (code, write, analyze, etc.)"
  echo -e "    3. Economy — how concise Claude's responses should be"
  echo ""
  echo -e "  Everything is reversible. Run ${BOLD}./uninstall.sh${NC} to remove cleanly."
  echo ""
fi

if [ -n "$ARG_MODE" ]; then
  MODE="$ARG_MODE"
else
  echo -e "${BOLD}Step 1 of 4: Install Mode${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Safe       — configs + safety hooks (no notifications, no auto-format)"
  echo -e "  ${BOLD}2)${NC} Standard   — adds notifications, git-safety, auto-format [recommended]"
  echo -e "  ${BOLD}3)${NC} Full       — adds prompt validation, compaction backup, diagnostics"
  echo ""
  read -rp "> " mode_choice
  case "$mode_choice" in
    1) MODE="safe" ;;
    3) MODE="full" ;;
    *) MODE="standard" ;;
  esac
  echo ""
fi

# Step 2: Roles
if [ -n "$ARG_ROLES" ]; then
  IFS=',' read -ra role_names <<< "$ARG_ROLES"
  SELECTED_ROLES=()
  for r in "${role_names[@]}"; do
    r=$(echo "$r" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    for valid in "${AVAILABLE_ROLES[@]}"; do
      if [[ "$r" == "$valid" ]]; then
        SELECTED_ROLES+=("$r")
        break
      fi
    done
  done
  if [ ${#SELECTED_ROLES[@]} -eq 0 ]; then
    SELECTED_ROLES=("writer")
  fi
else
  echo -e "${BOLD}Step 2 of 4: Your Roles${NC}"
  select_roles
  echo ""
fi

# Check if Developer role is selected
HAS_DEVELOPER="false"
for role in "${SELECTED_ROLES[@]}"; do
  [[ "$role" == "developer" ]] && HAS_DEVELOPER="true"
done

# Economy tier selection
if [ -n "$ARG_ECONOMY" ]; then
  SELECTED_TIER=$(echo "$ARG_ECONOMY" | tr '[:upper:]' '[:lower:]')
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  SELECTED_TIER=$(validate_tier_for_roles "$SELECTED_TIER" "$ROLES_CSV")
else
  echo -e "${BOLD}Select Token Economy:${NC}"
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  select_economy_tier "$ROLES_CSV"
fi

# Step 3: Existing config handling
CLAUDE_MD_ACTION="deploy"
if [ -n "$ARG_CONFIG" ]; then
  CLAUDE_MD_ACTION="$ARG_CONFIG"
elif [ -f "$HOME/.claude/CLAUDE.md" ]; then
  echo -e "${BOLD}Step 3 of 4: Existing Config${NC}"
  echo ""
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
if [ -n "$ARG_SETTINGS" ]; then
  SETTINGS_ACTION="$ARG_SETTINGS"
elif [ -f "$HOME/.claude/settings.json" ]; then
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

# Backup
create_backup

# Deploy CLAUDE.md
ROLES_LIST=$(format_roles_list)
MODE_LABEL=$(capitalize "$MODE")

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
  # Append full Supercharger config below marker
  {
    echo ""
    echo "# --- Claude Supercharger v${VERSION} ---"
    echo "# Do not edit below this line. Managed by Supercharger."
    echo "# To remove: run uninstall.sh or delete this block."
    echo ""
    sed -e "s/{{ROLES}}/$ROLES_LIST/g" -e "s/{{MODE}}/$MODE_LABEL/g" \
      "$SCRIPT_DIR/configs/universal/CLAUDE.md"
  } >> "$HOME/.claude/CLAUDE.md"
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

# Deploy economy
deploy_economy "$SCRIPT_DIR" "$SELECTED_TIER"

# Deploy shared assets
cp "$SCRIPT_DIR/configs/universal/anti-patterns.yml" "$HOME/.claude/rules/anti-patterns.yml"
success "Anti-patterns library installed (rules/)"

# Deploy agents
if [ -d "$SCRIPT_DIR/configs/agents" ]; then
  mkdir -p "$HOME/.claude/agents"
  cp "$SCRIPT_DIR/configs/agents/"*.md "$HOME/.claude/agents/" 2>/dev/null || true
  AGENT_COUNT=$(ls "$SCRIPT_DIR/configs/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
  success "${AGENT_COUNT} agent(s) installed"
fi

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

# Deploy MCP servers (zero-config)
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  if merge_mcp_into_settings "$ROLES_CSV"; then
    MCP_TOTAL=$(count_mcp_servers "$ROLES_CSV")
    MCP_ROLE=$(count_role_servers "$ROLES_CSV")
    MCP_CORE=$((MCP_TOTAL - MCP_ROLE))
    success "${MCP_TOTAL} MCP server(s) configured (${MCP_CORE} core + ${MCP_ROLE} for your roles)"
  else
    error "Failed to configure MCP servers."
  fi
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
echo -e "  Economy: ${BOLD}$(capitalize "$SELECTED_TIER")${NC}"
echo ""
echo -e "  Want more MCP servers? Run: ${BOLD}bash tools/mcp-setup.sh${NC}"
if [[ "$MODE" == "full" ]]; then
  echo -e "  Run ${BOLD}claude-check${NC} to verify installation."
else
  echo -e "  Upgrade anytime: ${BOLD}./install.sh${NC} (choose Full)"
fi
echo ""

# MCP Usage Tips
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  echo -e "${CYAN}  MCP Quick Tips:${NC}"
  echo -e "  Try: ${BOLD}\"Look up React useEffect docs\"${NC} → Context7"
  echo -e "  Try: ${BOLD}\"Think through this step by step\"${NC} → Sequential Thinking"
  if echo "$ROLES_CSV" | grep -q "developer"; then
    echo -e "  Try: ${BOLD}\"Test the login page in a browser\"${NC} → Playwright"
  fi
  if echo "$ROLES_CSV" | grep -qE "(writer|student|data|pm|designer|researcher)"; then
    echo -e "  Try: ${BOLD}\"Search for CSS grid examples\"${NC} → DuckDuckGo"
  fi
  echo ""
fi
