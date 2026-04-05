#!/usr/bin/env bash
# Claude Supercharger — Smart Updater
# Detects current settings, backs up, pulls, and reinstalls while preserving config.
# Usage: bash tools/update.sh [--dry-run|--check]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INSTALLED_VERSION_FILE="$HOME/.claude/supercharger/.version"
REPO_URL="https://github.com/smrafiz/claude-supercharger"
INSTALL_CMD="bash -c 'TMP=\$(mktemp -d) && git clone ${REPO_URL}.git \"\$TMP/cs\" && \"\$TMP/cs/install.sh\" && rm -rf \"\$TMP\"'"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Fetch latest version tag from GitHub API (no auth required)
fetch_remote_version() {
  python3 -c "
import urllib.request, json
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/releases/latest'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=5) as r:
        data = json.load(r)
    tag = data.get('tag_name', '').lstrip('v')
    print(tag)
except Exception:
    # fallback: check raw version file
    try:
        url2 = 'https://raw.githubusercontent.com/smrafiz/claude-supercharger/master/lib/utils.sh'
        req2 = urllib.request.Request(url2, headers={'User-Agent': 'claude-supercharger'})
        with urllib.request.urlopen(req2, timeout=5) as r:
            for line in r.read().decode().splitlines():
                if line.startswith('VERSION='):
                    print(line.split('=')[1].strip('\"'))
                    break
    except Exception:
        print('')
" 2>/dev/null
}

# Read local installed version
local_version() {
  if [ -f "$INSTALLED_VERSION_FILE" ]; then
    cat "$INSTALLED_VERSION_FILE"
  elif [ -f "$REPO_DIR/lib/utils.sh" ]; then
    grep '^VERSION=' "$REPO_DIR/lib/utils.sh" | head -1 | cut -d'"' -f2
  else
    echo "unknown"
  fi
}

# --check: just compare versions, no install
if [[ "${1:-}" == "--check" ]]; then
  LOCAL=$(local_version)
  echo -n "  Checking for updates... "
  REMOTE=$(fetch_remote_version)
  if [ -z "$REMOTE" ]; then
    echo -e "${YELLOW}could not reach GitHub${NC}"
    exit 0
  fi
  if [ "$LOCAL" = "$REMOTE" ]; then
    echo -e "${GREEN}up to date (v${LOCAL})${NC}"
  else
    echo -e "${YELLOW}update available: v${LOCAL} → v${REMOTE}${NC}"
    echo ""
    echo -e "  Run: ${BOLD}bash ~/.claude/supercharger/tools/update.sh${NC}"
  fi
  exit 0
fi

# No git repo — re-run one-liner install
if [ ! -d "$REPO_DIR/.git" ]; then
  LOCAL=$(local_version)
  echo ""
  echo -e "${YELLOW}  Installed via one-liner (no local git repo).${NC}"
  echo -n "  Checking for updates... "
  REMOTE=$(fetch_remote_version)
  if [ -z "$REMOTE" ]; then
    echo -e "${YELLOW}could not reach GitHub${NC}"
    exit 1
  fi
  if [ "$LOCAL" = "$REMOTE" ]; then
    echo -e "${GREEN}already up to date (v${LOCAL})${NC}"
    exit 0
  fi
  echo -e "${YELLOW}v${LOCAL} → v${REMOTE}${NC}"
  echo ""
  read -r -p "  Re-run installer to update? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
  fi
  echo ""
  eval "$INSTALL_CMD"
  exit $?
fi

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/backup.sh"

detect_platform

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Save current version before pull
OLD_VERSION="$VERSION"

RULES_DIR="$HOME/.claude/rules"
ALL_ROLES=("developer" "writer" "student" "data" "pm" "designer" "devops" "researcher")

# --- Infer current state ---

# Roles: check which role files exist
DETECTED_ROLES=()
for role in "${ALL_ROLES[@]}"; do
  if [ -f "$RULES_DIR/${role}.md" ]; then
    DETECTED_ROLES+=("$role")
  fi
done

if [ ${#DETECTED_ROLES[@]} -eq 0 ]; then
  error "No roles found in $RULES_DIR — is Supercharger installed?"
  exit 1
fi

ROLES_CSV=$(IFS=','; echo "${DETECTED_ROLES[*]}")

# Economy: grep the Active Tier line from economy.md
DETECTED_ECONOMY="lean"
if [ -f "$RULES_DIR/economy.md" ]; then
  DETECTED_ECONOMY=$(ECONOMY_FILE="$RULES_DIR/economy.md" python3 -c "
import re, os
with open(os.environ['ECONOMY_FILE']) as f:
    content = f.read()
for tier in ['minimal', 'lean', 'standard']:
    if tier.capitalize() in content[:800] or ('Active Tier' in content and tier in content.lower()[:800]):
        print(tier)
        break
else:
    print('lean')
" 2>/dev/null || echo "lean")
fi

# Mode: count #supercharger tagged hooks in settings.json
DETECTED_MODE="safe"
if [ -f "$HOME/.claude/settings.json" ]; then
  DETECTED_MODE=$(SETTINGS_PATH="$HOME/.claude/settings.json" python3 -c "
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

# --- Print detected state ---
echo ""
info "Claude Supercharger — Smart Update"
echo ""
echo -e "  Detected configuration:"
echo -e "    Mode:    ${BOLD}${DETECTED_MODE}${NC}"
echo -e "    Roles:   ${BOLD}${ROLES_CSV}${NC}"
echo -e "    Economy: ${BOLD}${DETECTED_ECONOMY}${NC}"
echo -e "    Current: ${BOLD}v${OLD_VERSION}${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
  info "--dry-run: no changes made."
  exit 0
fi

# Confirm before proceeding
read -r -p "  Proceed with update? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  info "Update cancelled."
  exit 0
fi

echo ""

# --- Backup ---
create_backup

# --- Pull ---
info "Pulling latest changes..."
cd "$REPO_DIR"

if ! git pull --rebase 2>&1; then
  git rebase --abort 2>/dev/null || true
  error "git pull failed. Rebase aborted. Your config is unchanged."
  error "Check your network or resolve conflicts manually."
  exit 1
fi

# Re-source utils.sh to get NEW_VERSION after pull
source "$REPO_DIR/lib/utils.sh"
NEW_VERSION="$VERSION"

# Already up to date?
if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo ""
  info "Already up to date (v${OLD_VERSION}). Nothing to do."
  exit 0
fi

# --- Changelog ---
echo ""
info "Changes since v${OLD_VERSION}:"
if git rev-parse ORIG_HEAD &>/dev/null 2>&1; then
  git log --oneline ORIG_HEAD..HEAD 2>/dev/null | head -10 || true
else
  git log --oneline -10 2>/dev/null || true
fi
echo ""

# --- Validate detected values ---
if [[ -z "$DETECTED_MODE" || -z "$ROLES_CSV" || -z "$DETECTED_ECONOMY" ]]; then
  error "Could not detect all required settings (mode=$DETECTED_MODE, roles=$ROLES_CSV, economy=$DETECTED_ECONOMY)."
  error "Run install.sh manually to reconfigure."
  exit 1
fi

# --- Reinstall with detected settings ---
info "Reinstalling with preserved settings..."
echo ""

bash "$REPO_DIR/install.sh" \
  --mode "$DETECTED_MODE" \
  --roles "$ROLES_CSV" \
  --economy "$DETECTED_ECONOMY" \
  --config merge \
  --settings merge

echo ""
success "Updated from v${OLD_VERSION} to v${NEW_VERSION}"
echo ""
