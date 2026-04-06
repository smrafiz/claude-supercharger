#!/usr/bin/env bash
# Claude Supercharger — Smart Updater
# Detects current settings, backs up, pulls, and reinstalls while preserving config.
# Usage: bash tools/update.sh [--dry-run|--check]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INSTALLED_VERSION_FILE="$HOME/.claude/supercharger/.version"
REPO_URL="https://github.com/smrafiz/claude-supercharger"
RULES_DIR="$HOME/.claude/rules"
ALL_ROLES=("developer" "writer" "student" "data" "pm" "designer" "devops" "researcher")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Fetch latest version from GitHub contents API (no auth, no CDN cache)
fetch_remote_version() {
  python3 -c "
import urllib.request, json, base64
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/contents/lib/utils.sh'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=5) as r:
        data = json.load(r)
    content = base64.b64decode(data['content']).decode()
    for line in content.splitlines():
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

# Detect current installed config (roles, economy, mode)
detect_config() {
  DETECTED_ROLES=()
  for role in "${ALL_ROLES[@]}"; do
    [ -f "$RULES_DIR/${role}.md" ] && DETECTED_ROLES+=("$role")
  done

  ROLES_CSV=$(IFS=','; echo "${DETECTED_ROLES[*]}")

  DETECTED_ECONOMY="lean"
  if [ -f "$RULES_DIR/economy.md" ]; then
    DETECTED_ECONOMY=$(ECONOMY_FILE="$RULES_DIR/economy.md" python3 -c "
import os
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
    # Show changelog via GitHub commits API
    python3 -c "
import urllib.request, json
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/commits?per_page=8'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=5) as r:
        commits = json.load(r)
    print('  What changed:')
    for c in commits:
        msg = c['commit']['message'].splitlines()[0]
        sha = c['sha'][:7]
        print(f'    {sha}  {msg}')
except Exception:
    pass
" 2>/dev/null
    echo ""
    echo -e "  Run: ${BOLD}bash ~/.claude/supercharger/tools/update.sh${NC}"
  fi
  exit 0
fi

# --- Detect current config (used by both paths) ---
detect_config

if [ ${#DETECTED_ROLES[@]} -eq 0 ]; then
  echo -e "${RED}  ✗ No roles found in $RULES_DIR — is Supercharger installed?${NC}" >&2
  exit 1
fi

LOCAL=$(local_version)

# --- No git repo: one-liner install path ---
if [ ! -d "$REPO_DIR/.git" ]; then
  echo ""
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
  echo -e "  Detected configuration:"
  echo -e "    Mode:    ${BOLD}${DETECTED_MODE}${NC}"
  echo -e "    Roles:   ${BOLD}${ROLES_CSV}${NC}"
  echo -e "    Economy: ${BOLD}${DETECTED_ECONOMY}${NC}"
  echo ""
  read -r -p "  Update now? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
  fi
  echo ""
  TMP=$(mktemp -d)

  # Fetch expected HEAD commit SHA from GitHub API before cloning
  EXPECTED_SHA=$(python3 -c "
import urllib.request, json
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/commits/master'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
    print(data['sha'])
except Exception:
    print('')
" 2>/dev/null)

  if [ -z "$EXPECTED_SHA" ]; then
    echo -e "${RED}  ✗ Could not fetch expected commit SHA from GitHub API. Aborting.${NC}" >&2
    rm -rf "$TMP"
    exit 1
  fi

  git clone "${REPO_URL}.git" "$TMP/cs" --quiet

  ACTUAL_SHA=$(git -C "$TMP/cs" rev-parse HEAD 2>/dev/null || echo "")

  if [ -z "$ACTUAL_SHA" ] || [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo -e "${RED}  ✗ Integrity check failed: cloned commit ($ACTUAL_SHA) does not match expected ($EXPECTED_SHA). Aborting.${NC}" >&2
    rm -rf "$TMP"
    exit 1
  fi

  bash "$TMP/cs/install.sh" \
    --mode "$DETECTED_MODE" \
    --roles "$ROLES_CSV" \
    --economy "$DETECTED_ECONOMY" \
    --config merge \
    --settings merge
  rm -rf "$TMP"
  exit 0
fi

# --- Git repo path ---
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/backup.sh"

detect_platform

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

OLD_VERSION="$VERSION"

echo ""
echo -e "  ${BOLD}Claude Supercharger — Smart Update${NC}"
echo ""
echo -e "  Detected configuration:"
echo -e "    Mode:    ${BOLD}${DETECTED_MODE}${NC}"
echo -e "    Roles:   ${BOLD}${ROLES_CSV}${NC}"
echo -e "    Economy: ${BOLD}${DETECTED_ECONOMY}${NC}"
echo -e "    Current: ${BOLD}v${OLD_VERSION}${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "  ${YELLOW}--dry-run: no changes made.${NC}"
  exit 0
fi

read -r -p "  Proceed with update? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "  Update cancelled."
  exit 0
fi

echo ""
create_backup

echo -e "  Pulling latest changes..."
cd "$REPO_DIR"
if ! git pull --rebase 2>&1; then
  git rebase --abort 2>/dev/null || true
  echo -e "${RED}  ✗ git pull failed. Rebase aborted. Your config is unchanged.${NC}" >&2
  exit 1
fi

source "$REPO_DIR/lib/utils.sh"
NEW_VERSION="$VERSION"

if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo ""
  echo -e "  ${GREEN}Already up to date (v${OLD_VERSION}).${NC}"
  exit 0
fi

echo ""
echo -e "  Changes since v${OLD_VERSION}:"
if git rev-parse ORIG_HEAD &>/dev/null 2>&1; then
  git log --oneline ORIG_HEAD..HEAD 2>/dev/null | head -10 | sed 's/^/    /' || true
else
  git log --oneline -5 2>/dev/null | sed 's/^/    /' || true
fi
echo ""

echo -e "  Reinstalling with preserved settings..."
echo ""

bash "$REPO_DIR/install.sh" \
  --mode "$DETECTED_MODE" \
  --roles "$ROLES_CSV" \
  --economy "$DETECTED_ECONOMY" \
  --config merge \
  --settings merge

echo ""
echo -e "${GREEN}  ✓ Updated v${OLD_VERSION} → v${NEW_VERSION}${NC}"
echo ""
