#!/usr/bin/env bash
set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this script prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; installer-side
# code never reaches that file, so it sets its own. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8
umask 077

# --- Prerequisite check ---
# v2.26.58 (WINDOWS-SUPPORT-PLAN G4): the platform is resolved BEFORE the gates.
#
# The gates used to run at the very top, ~76 lines before `detect_platform` was
# called. detect_platform is where the Windows python handling lives: it tries
# `py` (the python.org launcher), `python`, then `py3` and builds a shim. So on a
# Windows box with `py` but no `python3` on PATH, the install died with
# "ERROR: python3 is required" while the code that would have fixed it sat
# unreachable further down the same file. A reorder, not new logic.
#
# Nothing between the old gate position and the old detect_platform call used
# jq or python3, so moving it earlier is safe. detect_platform reads only $OSTYPE.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"
detect_platform

# jq is used by ~60 hooks for parsing tool input JSON. Without it, hooks silently
# degrade (empty values, malformed JSON output). Fail fast at install.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed." >&2
  echo "" >&2
  echo "Install with:" >&2
  if command -v brew >/dev/null 2>&1; then
    echo "  brew install jq" >&2
  elif command -v apt-get >/dev/null 2>&1; then
    echo "  sudo apt-get install jq" >&2
  elif command -v dnf >/dev/null 2>&1; then
    echo "  sudo dnf install jq" >&2
  elif command -v pacman >/dev/null 2>&1; then
    echo "  sudo pacman -S jq" >&2
  elif [ "${PLATFORM:-}" = "windows" ]; then
    # Git Bash has none of the above, so the generic line below was the only
    # message a Windows user ever saw — true, and useless. Measured on a
    # windows-latest runner: jq is NOT preinstalled with Git for Windows.
    echo "  winget install jqlang.jq" >&2
    echo "  or:  choco install jq" >&2
    echo "" >&2
    echo "  Then reopen Git Bash so the new PATH is picked up." >&2
  else
    echo "  Check your package manager — jq is widely available." >&2
  fi
  exit 1
fi
# NOTE: no python3 gate here. detect_platform (called above) already resolves
# python3 — including the Windows `py`/`python`/`py3` shim — and prints a proper
# error if no interpreter exists at all. A second bare `command -v python3` here
# would re-introduce exactly the bug this reorder fixed.

# Safe Mode warning (Claude Code v2.1.169+)
# Installing under safe mode is fine, but the resulting session won't run hooks
# until the user clears the env var or drops --safe-mode. Warn so they don't
# install, exit, and wonder why Supercharger appears to be "off".
if [ "${CLAUDE_CODE_SAFE_MODE:-}" = "1" ]; then
  echo "" >&2
  echo "NOTE: CLAUDE_CODE_SAFE_MODE=1 is set in your environment." >&2
  echo "      Supercharger will install, but Claude Code skips hooks/MCP/skills/CLAUDE.md" >&2
  echo "      under safe mode. Unset the env var (or drop --safe-mode) before your next" >&2
  echo "      session to activate guardrails." >&2
  echo "" >&2
fi

# Source the remaining modules. SCRIPT_DIR, lib/utils.sh and detect_platform
# already ran in the prerequisite block at the top of this file (v2.26.58).
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
ARG_NOTIFY=""
ARG_COMMITS=""
ARG_MCP_PROFILE=""

show_usage() {
  echo "Usage: install.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --mode MODE        Install mode: safe, full (default: interactive; 'standard' maps to full)"
  echo "  --roles ROLES      Comma-separated roles: developer,writer,student,data,pm,designer,devops,researcher"
  echo "  --config ACTION    CLAUDE.md handling: deploy, merge, replace, skip"
  echo "  --settings ACTION  settings.json handling: deploy, merge, replace, skip"
  echo "  --economy TIER     Economy tier: standard, lean, minimal (default: lean)"
  echo "  --notify MODE      Desktop notifications: on, off, sound (default: on)"
  echo "  --commits MODE     Conventional commits: on, off (default: off)"
  echo "  --mcp-profile PROFILE  MCP profile: light, dev, research, full (default: light)"
  echo "  --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./install.sh                                              # Interactive"
  echo "  ./install.sh --mode full --roles developer,pm              # Partial (prompts for rest)"
  echo "  ./install.sh --mode full --roles developer --economy lean --config deploy --settings deploy  # Fully silent"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     ARG_MODE="$2"; shift 2 ;;
    --roles)    ARG_ROLES="$2"; shift 2 ;;
    --config)   ARG_CONFIG="$2"; shift 2 ;;
    --settings) ARG_SETTINGS="$2"; shift 2 ;;
    --economy)  ARG_ECONOMY="$2"; shift 2 ;;
    --notify)   ARG_NOTIFY="$2"; shift 2 ;;
    --commits)      ARG_COMMITS="$2"; shift 2 ;;
    --mcp-profile)  ARG_MCP_PROFILE="$2"; shift 2 ;;
    --help)     show_usage ;;
    *)          echo "Unknown option: $1"; show_usage ;;
  esac
done

# detect_platform is NOT re-run here: it already ran above, and a second call
# would build another python shim dir and prepend PATH twice.

# Determine if running non-interactively (all args provided)
NON_INTERACTIVE="false"
if [ -n "$ARG_MODE" ] && [ -n "$ARG_ROLES" ] && [ -n "$ARG_CONFIG" ] && [ -n "$ARG_SETTINGS" ]; then
  NON_INTERACTIVE="true"
fi

# Detect existing Supercharger installation → offer update
INSTALLED_VERSION_FILE="$HOME/.claude/supercharger/.version"
if [ -f "$INSTALLED_VERSION_FILE" ] && [[ "$NON_INTERACTIVE" == "false" ]]; then
  INSTALLED_VER=$(cat "$INSTALLED_VERSION_FILE" 2>/dev/null || echo "unknown")
  show_banner
  echo -e "${CYAN}  Supercharger v${INSTALLED_VER} is already installed.${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Update  — pull latest changes, preserve your config [recommended]"
  echo -e "  ${BOLD}2)${NC} Reinstall — fresh install (re-prompts mode, roles, economy)"
  echo ""
  read -rp "> " upgrade_choice
  echo ""
  if [[ "$upgrade_choice" != "2" ]]; then
    if [ -f "$SCRIPT_DIR/tools/update.sh" ]; then
      exec bash "$SCRIPT_DIR/tools/update.sh"
    elif [ -f "$HOME/.claude/supercharger/tools/update.sh" ]; then
      exec bash "$HOME/.claude/supercharger/tools/update.sh"
    else
      echo -e "${RED}  ✗ update.sh not found. Running fresh install instead.${NC}"
    fi
  fi
fi

# Detect first-time user
FIRST_TIME="false"
if [ ! -d "$HOME/.claude" ] || [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
  FIRST_TIME="true"
fi

# Step 1: Banner + Mode
show_banner

# Quick vs Custom fork — collapse the multi-question wizard to sensible defaults
# for the common case. Quick presets the tunable choices and only asks Notify
# (a personal/environmental preference we can't guess) plus the safety prompts
# for any existing CLAUDE.md/settings.json. Custom runs the full wizard.
# Only offered when interactive and mode wasn't preset via flags.
QUICK_INSTALL="false"
if [ -z "$ARG_MODE" ] && [[ "$NON_INTERACTIVE" == "false" ]]; then
  echo -e "${BOLD}How do you want to install?${NC}"
  echo ""
  echo -e "  ${BOLD}→ Press Enter for Quick install${NC} ${CYAN}(recommended)${NC}"
  echo -e "    Full mode · Developer · minimal economy · light MCP · conventional commits on"
  echo -e "    Every choice is changeable later (e.g. ${BOLD}eco lean${NC}, ${BOLD}./install.sh${NC} → Custom)."
  echo -e "  ${BOLD}→ Type ${NC}${BOLD}c${NC}${BOLD} for Custom${NC} — choose everything"
  echo ""
  read -rp "> " install_choice
  echo ""
  case "$install_choice" in
    c|C|custom|Custom) ;;  # fall through to the full wizard
    *)
      ARG_MODE="full"
      ARG_ROLES="developer"
      ARG_ECONOMY="minimal"
      ARG_MCP_PROFILE="light"
      ARG_COMMITS="on"
      QUICK_INSTALL="true"
      ;;
  esac
fi

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

# Backward compat: standard → full
[[ "$ARG_MODE" == "standard" ]] && ARG_MODE="full"

if [ -n "$ARG_MODE" ]; then
  MODE="$ARG_MODE"
else
  echo -e "${BOLD}Install Mode${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Safe       — safety hooks + auto-approve + audit trail (25 hooks)"
  echo -e "  ${BOLD}2)${NC} Full       — everything: git-safety, agent routing, context advisor, quality gate [recommended]"
  echo ""
  read -rp "> " mode_choice
  case "$mode_choice" in
    1) MODE="safe" ;;
    *) MODE="full" ;;
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
  echo -e "${BOLD}Your Roles${NC}"
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
  echo -e "${BOLD}Token Economy${NC}"
  echo ""
  echo -e "${BOLD}Select Token Economy:${NC}"
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  select_economy_tier "$ROLES_CSV"
fi

# MCP Profile selection
MCP_PROFILE="light"
if [ -n "$ARG_MCP_PROFILE" ]; then
  MCP_PROFILE=$(echo "$ARG_MCP_PROFILE" | tr '[:upper:]' '[:lower:]')
elif [[ "$NON_INTERACTIVE" == "false" ]]; then
  echo -e "${BOLD}MCP Servers${NC}"
  echo ""
  echo -e "  MCP servers extend Claude with real-time tools."
  echo -e "  More = more capable, but higher token cost per session."
  echo ""
  echo -e "  ${BOLD}1)${NC} Light    — context7 docs lookup only (~300 tokens) [recommended]"
  echo -e "  ${BOLD}2)${NC} Dev      — + Playwright, GitHub, Magic UI (~1,200 tokens)"
  echo -e "  ${BOLD}3)${NC} Research — + memory + sequential thinking (~1,500 tokens)"
  echo -e "  ${BOLD}4)${NC} Full     — everything: dev + research (~3,500 tokens)"
  echo ""
  echo "  Heavy/specialty MCPs are opt-in post-install via env var:"
  echo "    export SUPERCHARGER_MCP_EXTRAS=\"playwright,github,sequential-thinking,memory\""
  echo "    bash tools/mcp-profile.sh dev   # re-applies with extras"
  echo ""
  read -rp "> " mcp_choice
  case "$mcp_choice" in
    2) MCP_PROFILE="dev" ;;
    3) MCP_PROFILE="research" ;;
    4) MCP_PROFILE="full" ;;
    *) MCP_PROFILE="light" ;;
  esac
  echo ""
fi

# Desktop notifications
NOTIFY_MODE="on"
if [ -n "$ARG_NOTIFY" ]; then
  NOTIFY_MODE=$(echo "$ARG_NOTIFY" | tr '[:upper:]' '[:lower:]')
elif [[ "$NON_INTERACTIVE" == "false" ]]; then
  echo -e "${BOLD}Desktop Notifications${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} On     — popup when Claude needs your attention [default]"
  echo -e "  ${BOLD}2)${NC} Sound  — beep only, no popup"
  echo -e "  ${BOLD}3)${NC} Off    — no desktop notifications (webhooks still work)"
  echo ""
  read -rp "> " notify_choice
  case "$notify_choice" in
    2) NOTIFY_MODE="sound" ;;
    3) NOTIFY_MODE="off" ;;
    *) NOTIFY_MODE="on" ;;
  esac
  echo ""
fi

# Conventional commits (opt-in)
COMMITS_MODE="off"
if [ -n "$ARG_COMMITS" ]; then
  COMMITS_MODE=$(echo "$ARG_COMMITS" | tr '[:upper:]' '[:lower:]')
elif [[ "$NON_INTERACTIVE" == "false" ]] && [[ "$HAS_DEVELOPER" == "true" ]]; then
  echo -e "${BOLD}Conventional Commits${NC}"
  echo ""
  echo -e "  Enforce conventional commit format? (feat:, fix:, chore:, etc.)"
  echo ""
  echo -e "  ${BOLD}1)${NC} Off  — no commit message checks [default]"
  echo -e "  ${BOLD}2)${NC} On   — block non-conventional commits"
  echo ""
  read -rp "> " commits_choice
  case "$commits_choice" in
    2) COMMITS_MODE="on" ;;
    *) COMMITS_MODE="off" ;;
  esac
  echo ""
fi

# Step 3: Existing config handling
CLAUDE_MD_ACTION="deploy"
if [ -n "$ARG_CONFIG" ]; then
  CLAUDE_MD_ACTION="$ARG_CONFIG"
elif [ -f "$HOME/.claude/CLAUDE.md" ]; then
  echo -e "${BOLD}Existing Config${NC}"
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
echo -e "${BOLD}Installing...${NC}"
echo ""

# Ensure directories exist
mkdir -p "$HOME/.claude/rules"

# Backup
create_backup

# Deploy CLAUDE.md
ROLES_LIST=$(format_roles_list)
MODE_LABEL=$(capitalize "$MODE")

if [[ "$CLAUDE_MD_ACTION" == "deploy" || "$CLAUDE_MD_ACTION" == "replace" ]]; then
  # v2.26.72: write the SAME wrapper the merge path appends. This branch used to
  # write the bare template, so a fresh install produced a CLAUDE.md that nothing
  # else could recognise:
  #   - uninstall.sh keys on `^# --- Claude Supercharger` and left all 54 lines
  #     behind — verified, and a straight violation of "clean uninstall".
  #   - the next install's merge path saw an unmarked block and stripped it with
  #     the pre-v2.3 LEGACY rule, warning about a block it had written itself one
  #     run earlier. That warning is what prompted this.
  #   - that legacy rule deletes from the H1 to EOF, so anything a user appended
  #     after the block went with it (backed up, but gone from the live file).
  # One writer, one marker, so every reader agrees.
  {
    echo "# --- Claude Supercharger v${VERSION} ---"
    echo "# Do not edit below this line. Managed by Supercharger."
    echo "# To remove: run uninstall.sh or delete this block."
    echo ""
    sed -e "s/{{ROLES}}/$ROLES_LIST/g" -e "s/{{MODE}}/$MODE_LABEL/g" -e "s/{{VERSION}}/v${VERSION}/g" \
      "$SCRIPT_DIR/configs/universal/CLAUDE.md"
  } > "$HOME/.claude/CLAUDE.md"
  success "Universal config installed"
elif [[ "$CLAUDE_MD_ACTION" == "merge" ]]; then
  # Remove existing Supercharger block if present
  if grep -q "^# --- Claude Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    sed -i.bak '/^# --- Claude Supercharger/,$d' "$HOME/.claude/CLAUDE.md"
    rm -f "$HOME/.claude/CLAUDE.md.bak"
  fi
  # Strip legacy unmarked Supercharger block (pre-v2.3 installs merged content
  # without wrapper markers — survives updates and duplicates ~70 lines / ~3KB
  # into every session's context). Backup first, then delete from the H1 to EOF.
  if grep -q "^# Claude Supercharger v" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    cp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.legacy-bak"
    sed -i.tmp '/^# Claude Supercharger v/,$d' "$HOME/.claude/CLAUDE.md"
    rm -f "$HOME/.claude/CLAUDE.md.tmp"
    warn "Stripped legacy unmarked Supercharger block from ~/.claude/CLAUDE.md (backup at .legacy-bak)"
  fi
  # Append full Supercharger config below marker
  {
    echo ""
    echo "# --- Claude Supercharger v${VERSION} ---"
    echo "# Do not edit below this line. Managed by Supercharger."
    echo "# To remove: run uninstall.sh or delete this block."
    echo ""
    sed -e "s/{{ROLES}}/$ROLES_LIST/g" -e "s/{{MODE}}/$MODE_LABEL/g" -e "s/{{VERSION}}/v${VERSION}/g" \
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
deploy_economy "$SCRIPT_DIR" "$SELECTED_TIER" "$ROLES_CSV"

# Deploy shared assets
cp "$SCRIPT_DIR/configs/universal/anti-patterns.yml" "$HOME/.claude/rules/anti-patterns.yml"
success "Anti-patterns library installed (rules/)"

# Deploy agents
if [ -d "$SCRIPT_DIR/configs/agents" ]; then
  mkdir -p "$HOME/.claude/agents"
  cp "$SCRIPT_DIR/configs/agents/"*.md "$HOME/.claude/agents/" 2>/dev/null || true
  # A reference copy alongside roles/, so tooling can tell OUR agents from the
  # user's. `/sc off` moves agent definitions aside — they cost ~2970 tokens of
  # listing per session — and without this there is no way to know which of
  # ~/.claude/agents/*.md we installed: a user's own writer.md looks identical to
  # ours. Mirrors deploy_roles(), which keeps supercharger/roles/ for the same
  # reason. On an install that pre-dates this, the dir is simply absent and
  # `off` moves nothing rather than guessing.
  mkdir -p "$HOME/.claude/supercharger/agents"
  cp "$SCRIPT_DIR/configs/agents/"*.md "$HOME/.claude/supercharger/agents/" 2>/dev/null || true
  AGENT_COUNT=$(ls "$SCRIPT_DIR/configs/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
  success "${AGENT_COUNT} agent(s) installed"
fi

# Deploy commands
if [ -d "$SCRIPT_DIR/configs/commands" ]; then
  mkdir -p "$HOME/.claude/commands"
  cp "$SCRIPT_DIR/configs/commands/"*.md "$HOME/.claude/commands/" 2>/dev/null || true
  CMD_NAMES=$(ls "$SCRIPT_DIR/configs/commands/"*.md 2>/dev/null | xargs -I{} basename {} .md | sed 's/^/\//' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  CMD_COUNT=$(ls "$SCRIPT_DIR/configs/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
  success "${CMD_COUNT} command(s) installed (${CMD_NAMES})"
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

  # Apply notification preference
  NOTIFY_FLAG_OFF="$HOME/.claude/supercharger/.no-desktop-notify"
  NOTIFY_FLAG_SOUND="$HOME/.claude/supercharger/.sound-only-notify"
  rm -f "$NOTIFY_FLAG_OFF" "$NOTIFY_FLAG_SOUND"
  if [[ "$NOTIFY_MODE" == "off" ]]; then
    touch "$NOTIFY_FLAG_OFF"
    success "Desktop notifications disabled"
  elif [[ "$NOTIFY_MODE" == "sound" ]]; then
    touch "$NOTIFY_FLAG_SOUND"
    success "Desktop notifications set to sound only"
  else
    success "Desktop notifications enabled"
  fi

  # Apply conventional commits preference
  COMMITS_FLAG="$HOME/.claude/supercharger/.conventional-commits"
  rm -f "$COMMITS_FLAG"
  if [[ "$COMMITS_MODE" == "on" ]]; then
    touch "$COMMITS_FLAG"
    success "Conventional commit enforcement enabled"
  else
    info "Conventional commits: off (enable with --commits on)"
  fi
else
  info "Skipped hooks installation"
fi

# Deploy MCP servers (zero-config)
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  if merge_mcp_into_settings "$ROLES_CSV" "$MCP_PROFILE"; then
    MCP_TOTAL=$(count_mcp_servers "$ROLES_CSV" "$MCP_PROFILE")
    MCP_ROLE=$(count_role_servers "$ROLES_CSV")
    MCP_CORE=$((MCP_TOTAL - MCP_ROLE))
    success "${MCP_TOTAL} MCP server(s) configured [${MCP_PROFILE} profile]"
  else
    error "Failed to configure MCP servers."
  fi
fi

# Deploy extras (Full mode). Quick already picked the MCP profile, so suppress
# the secondary "Run MCP setup?" wizard prompt (treat Quick as non-interactive
# for extras only).
EXTRAS_NONINT="$NON_INTERACTIVE"
[[ "$QUICK_INSTALL" == "true" ]] && EXTRAS_NONINT="true"
deploy_extras "$SCRIPT_DIR" "$MODE" "$EXTRAS_NONINT"

# Summary
echo ""
# Write installed version stamp
echo "$VERSION" > "$HOME/.claude/supercharger/.version"
echo "${ROLES_CSV}" > "$HOME/.claude/supercharger/.roles"
mkdir -p "$HOME/.claude/supercharger/scope"
echo "$MCP_PROFILE" > "$HOME/.claude/supercharger/scope/.mcp-profile"
echo "$SELECTED_TIER" > "$HOME/.claude/supercharger/scope/.economy-tier"

# How many tagged entries we left in settings.json. guard-registration-check
# compares against this so it can see PARTIAL registration loss, not just the
# total-absence case it caught before — 1-of-154 registered used to be silent.
# Written last, after every settings write (hooks, statusLine, MCP), and with the
# same expression the check uses, so the two are always the same metric.
if [ -r "$HOME/.claude/settings.json" ]; then
  grep -o -- '#supercharger' "$HOME/.claude/settings.json" 2>/dev/null | wc -l | tr -d ' ' \
    > "$HOME/.claude/supercharger/.registration-count" 2>/dev/null || true
fi

echo -e "${CYAN}────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done! Claude Supercharger v${VERSION} installed.${NC}"
echo ""
echo -e "  Mode:     ${BOLD}${MODE_LABEL}${NC}"
echo -e "  Roles:    ${BOLD}${ROLES_LIST}${NC}"
echo -e "  Economy:  ${BOLD}$(capitalize "$SELECTED_TIER")${NC}"
echo -e "  Notify:   ${BOLD}$(capitalize "$NOTIFY_MODE")${NC}"
echo ""
echo -e "  Slash commands installed — type ${BOLD}/supercharger${NC} in any chat to list them."
echo -e "  Want plain Claude for a bit? ${BOLD}/sc off${NC} switches to default Claude, ${BOLD}/sc on${NC} restores it."
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
