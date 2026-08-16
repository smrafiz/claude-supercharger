#!/usr/bin/env bash
# Claude Supercharger — Smart Updater
# Detects current settings, backs up, pulls, and reinstalls while preserving config.
# Usage: bash tools/update.sh [--dry-run|--check|--yes|-y|--non-interactive]
#
# --yes / -y / --non-interactive   Skip the "Update now?" and "Proceed?"
#                                   confirmation prompts. Also honored when
#                                   SUPERCHARGER_NONINTERACTIVE=1 is exported.
#                                   Use for dotfile sync, CI, automated rollouts.

set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INSTALLED_VERSION_FILE="$HOME/.claude/supercharger/.version"
REPO_URL="https://github.com/smrafiz/claude-supercharger"
RULES_DIR="$HOME/.claude/rules"
ALL_ROLES=("developer" "writer" "student" "data" "pm" "designer" "devops" "researcher")

# Shared helpers (sc_version_newer). Sourced defensively: this file also runs from
# an install directory, where lib/ sits beside tools/, and a missing lib must not
# take the updater down — the fallback below keeps version comparison working.
if [ -f "$REPO_DIR/lib/utils.sh" ]; then
  # shellcheck source=lib/utils.sh
  . "$REPO_DIR/lib/utils.sh" 2>/dev/null || true
fi
if ! command -v sc_version_newer >/dev/null 2>&1; then
  sc_version_newer() {
    [ "$1" = "$2" ] && return 1
    local _a="$1" _b="$2" _x _y
    while [ -n "$_a$_b" ]; do
      _x="${_a%%.*}"; _y="${_b%%.*}"
      case "$_x" in ''|*[!0-9]*) _x=0 ;; esac
      case "$_y" in ''|*[!0-9]*) _y=0 ;; esac
      [ "$_x" -gt "$_y" ] && return 0
      [ "$_x" -lt "$_y" ] && return 1
      case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
      case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
    done
    return 1
  }
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'


# Parse flags early — before any network calls or config detection
NONINTERACTIVE="${SUPERCHARGER_NONINTERACTIVE:-0}"
[ "$NONINTERACTIVE" = "1" ] && NONINTERACTIVE=true || NONINTERACTIVE=false
for _arg in "$@"; do
  case "$_arg" in
    --dry-run)
      echo -e "  ${YELLOW}--dry-run: no changes made.${NC}"
      exit 0
      ;;
    --yes|-y|--non-interactive)
      NONINTERACTIVE=true
      ;;
  esac
done

# Fetch the latest released version = the VERSION string in lib/utils.sh on master.
fetch_remote_version() {
  # The single source of truth is VERSION in lib/utils.sh — NOT git tags. The repo
  # carries orphaned tags from an earlier scheme (v3.6.x, 2026-04) that outrank the
  # current 2.x file version, so a max-tag sort (the pre-2.11.1 approach) wrongly
  # reported v3.6.35 as "latest" and every 2.x release looked perpetually stale.
  #
  # Primary: the GitHub contents API with a raw-accept header — served FRESH (no CDN
  # cache), so a check run seconds after a release sees the new version. The 2.11.1
  # fix used raw.githubusercontent.com as primary, but that host is CDN-cached and
  # lags minutes behind a release, so /sc-update falsely reported "up to date" for a
  # few minutes after every release. curl honours http(s)_proxy. Raw is kept as a
  # fallback (no rate limit, but possibly stale); the python API path is the last resort.
  local v
  v=$(curl -fsSL --max-time 6 -H 'Accept: application/vnd.github.raw' \
        "https://api.github.com/repos/smrafiz/claude-supercharger/contents/lib/utils.sh?ref=master" 2>/dev/null \
        | grep -m1 '^VERSION=' | cut -d'"' -f2)
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
    return
  fi
  # Fallback 1: raw file over HTTPS — no rate limit, but CDN-cached (may be stale).
  v=$(curl -fsSL --max-time 6 \
        "https://raw.githubusercontent.com/smrafiz/claude-supercharger/master/lib/utils.sh" 2>/dev/null \
        | grep -m1 '^VERSION=' | cut -d'"' -f2)
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
    return
  fi
  # Fallback 2: GitHub REST API via python (for hosts without curl).
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
import re, os
with open(os.environ['ECONOMY_FILE']) as f:
    content = f.read()
m = re.search(r'### Active Tier:\s*(standard|lean|minimal)', content, re.IGNORECASE)
print(m.group(1).lower() if m else 'lean')
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
if count > 5:
    print('full')
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
  if ! sc_version_newer "$REMOTE" "$LOCAL"; then
    # Equal, or the published version is older than what is installed (the API
    # lags after a release). Neither is an update; saying so kept users chasing a
    # notice that pointed backwards.
    if [ "$LOCAL" = "$REMOTE" ]; then
      echo -e "${GREEN}up to date (v${LOCAL})${NC}"
    else
      echo -e "${GREEN}up to date (v${LOCAL}; published: v${REMOTE})${NC}"
    fi
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
    echo -e "  Run: ${BOLD}bash ~/.claude/supercharger/tools/update.sh --yes${NC}   (--yes applies it non-interactively)"
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
if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
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
  # REFUSE to move backwards. This used to be `if equal then stop` and otherwise
  # proceed, so a remote OLDER than the install counted as an update and was
  # applied — a silent downgrade that reverts shipped fixes. The remote version
  # comes from the GitHub contents API, which is CDN-cached and does lag: it
  # served 2.27.14 while master was already ahead. Anyone updating inside that
  # window, or running a build ahead of master, would have been rolled back.
  if ! sc_version_newer "$REMOTE" "$LOCAL"; then
    echo -e "${YELLOW}installed v${LOCAL} is newer than the published v${REMOTE} — not downgrading.${NC}"
    echo -e "  This is normal right after a release (the GitHub API lags) or on a development build."
    echo -e "  To install the published version deliberately, check it out and run its installer:"
    echo -e "    git -C <your-clone> checkout v${REMOTE} && bash <your-clone>/install.sh"
    exit 0
  fi
  echo -e "${YELLOW}v${LOCAL} → v${REMOTE}${NC}"
  echo ""
  echo -e "  Detected configuration:"
  echo -e "    Mode:    ${BOLD}${DETECTED_MODE}${NC}"
  echo -e "    Roles:   ${BOLD}${ROLES_CSV}${NC}"
  echo -e "    Economy: ${BOLD}${DETECTED_ECONOMY}${NC}"
  echo ""
  if [ "$NONINTERACTIVE" = "true" ]; then
    echo -e "  ${YELLOW}--yes: auto-confirming update.${NC}"
  else
    read -r -p "  Update now? [y/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
      echo "  Cancelled."
      exit 0
    fi
  fi
  echo ""
  TMP=$(mktemp -d)

  # Fetch expected HEAD commit SHA to verify the clone below. The unauthenticated
  # GitHub API is capped at 60 req/hr per IP, so a single anonymous call here used
  # to 403 on shared IPs / NAT / CI and ABORT the whole update (users behind a
  # rate-limited IP found /sc-update permanently dead). Resolve resiliently:
  #   1. authenticated `gh` (5000/hr) — most users on a GitHub repo have it;
  #   2. curl with the .sha media type; 3. python urllib (both anonymous).
  # If ALL are unavailable (rate limit / offline), PROCEED WITH A WARNING rather
  # than abort — the clone is a TLS-authenticated github.com fetch either way, so
  # the SHA compare is a best-effort freshness check, not the sole trust anchor.
  # A SUCCESSFULLY-fetched SHA that MISMATCHES the clone still aborts (fail-closed).
  EXPECTED_SHA=""
  if command -v gh >/dev/null 2>&1; then
    EXPECTED_SHA=$(gh api "repos/smrafiz/claude-supercharger/commits/master" --jq '.sha' 2>/dev/null || echo "")
  fi
  if [ -z "$EXPECTED_SHA" ] && command -v curl >/dev/null 2>&1; then
    # v2.26.79: `|| echo ""` — without it this line ABORTS the update it is only
    # meant to inform. `curl -f` exits 22 on HTTP 403, which is what the anonymous
    # API returns once the 60-req/hr per-IP cap is hit; `set -o pipefail` hands 22
    # to the assignment and `set -e` kills the script. So the exact rate-limit case
    # the comment above says to survive was fatal, and only on a shared/NAT'd IP —
    # invisible until a Windows CI runner hit the cap on v2.26.78.
    # The sibling `gh` branch had the guard and the python branch catches its own
    # exceptions; this was the one arm of three without it.
    EXPECTED_SHA=$(curl -fsSL --max-time 6 -H 'Accept: application/vnd.github.sha' \
      "https://api.github.com/repos/smrafiz/claude-supercharger/commits/master" 2>/dev/null | tr -d '[:space:]' || echo "")
  fi
  if [ -z "$EXPECTED_SHA" ]; then
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
  fi

  git clone "${REPO_URL}.git" "$TMP/cs" --quiet

  ACTUAL_SHA=$(git -C "$TMP/cs" rev-parse HEAD 2>/dev/null || echo "")

  if [ -z "$EXPECTED_SHA" ]; then
    echo -e "${YELLOW}  ⚠ Could not fetch expected commit SHA (GitHub API unavailable or rate-limited).${NC}" >&2
    echo -e "${YELLOW}    Proceeding with the TLS-authenticated clone without the extra freshness check.${NC}" >&2
  elif [ -z "$ACTUAL_SHA" ] || [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo -e "${RED}  ✗ Integrity check failed: cloned commit ($ACTUAL_SHA) does not match expected ($EXPECTED_SHA). Aborting.${NC}" >&2
    rm -rf "$TMP"
    exit 1
  fi

  # Detect current notify/commits settings
  DETECTED_NOTIFY="on"
  [ -f "$HOME/.claude/supercharger/.no-desktop-notify" ] && DETECTED_NOTIFY="off"
  [ -f "$HOME/.claude/supercharger/.sound-only-notify" ] && DETECTED_NOTIFY="sound"
  DETECTED_COMMITS="off"
  [ -f "$HOME/.claude/supercharger/.conventional-commits" ] && DETECTED_COMMITS="on"
  # 2.21.9: preserve the MCP profile. install.sh defaults it to "light" and
  # unconditionally overwrites scope/.mcp-profile, so without re-passing it every
  # update silently reset a user's dev/research/full profile back to light.
  DETECTED_MCP_PROFILE=$(tr -d '[:space:]' < "$HOME/.claude/supercharger/scope/.mcp-profile" 2>/dev/null || echo "")
  [ -z "$DETECTED_MCP_PROFILE" ] && DETECTED_MCP_PROFILE="light"

  bash "$TMP/cs/install.sh" \
    --mode "$DETECTED_MODE" \
    --roles "$ROLES_CSV" \
    --economy "$DETECTED_ECONOMY" \
    --notify "$DETECTED_NOTIFY" \
    --commits "$DETECTED_COMMITS" \
    --mcp-profile "$DETECTED_MCP_PROFILE" \
    --config merge \
    --settings merge
  rm -rf "$TMP"
  exit 0
fi

# --- Git repo path ---
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/backup.sh"

detect_platform


# v2.26.25: was `OLD_VERSION="$VERSION"`, i.e. the version from the REPO's
# lib/utils.sh sourced just above. NEW_VERSION re-sources that same file after
# `git pull`, so the "has anything changed?" test compared the repo to itself and
# reported "Already up to date" whenever the checkout was current — which it
# always is straight after a local release. The update then exited 0 without
# deploying a single file, so a green run meant nothing had happened.
#
# This is why an install sat 15 releases behind (2.26.1 vs 2.26.16) while every
# `/sc-update` reported success. What we want to know is whether the INSTALLED
# tree differs from the repo, so read the installed marker; fall back to the repo
# version only when there is no installation to compare against.
OLD_VERSION=$(cat "$INSTALLED_VERSION_FILE" 2>/dev/null || echo "$VERSION")
[ -z "$OLD_VERSION" ] && OLD_VERSION="$VERSION"

echo ""
echo -e "  ${BOLD}Claude Supercharger — Smart Update${NC}"
echo ""
echo -e "  Detected configuration:"
echo -e "    Mode:    ${BOLD}${DETECTED_MODE}${NC}"
echo -e "    Roles:   ${BOLD}${ROLES_CSV}${NC}"
echo -e "    Economy: ${BOLD}${DETECTED_ECONOMY}${NC}"
echo -e "    Current: ${BOLD}v${OLD_VERSION}${NC}"
echo ""



if [ "$NONINTERACTIVE" = "true" ]; then
  echo -e "  ${YELLOW}--yes: auto-proceeding with update.${NC}"
else
  read -r -p "  Proceed with update? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "  Update cancelled."
    exit 0
  fi
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

# Detect current notify/commits settings
DETECTED_NOTIFY="on"
[ -f "$HOME/.claude/supercharger/.no-desktop-notify" ] && DETECTED_NOTIFY="off"
[ -f "$HOME/.claude/supercharger/.sound-only-notify" ] && DETECTED_NOTIFY="sound"
DETECTED_COMMITS="off"
[ -f "$HOME/.claude/supercharger/.conventional-commits" ] && DETECTED_COMMITS="on"
# 2.21.9: preserve the MCP profile across updates (see the --check path above).
DETECTED_MCP_PROFILE=$(tr -d '[:space:]' < "$HOME/.claude/supercharger/scope/.mcp-profile" 2>/dev/null || echo "")
[ -z "$DETECTED_MCP_PROFILE" ] && DETECTED_MCP_PROFILE="light"

bash "$REPO_DIR/install.sh" \
  --mode "$DETECTED_MODE" \
  --roles "$ROLES_CSV" \
  --economy "$DETECTED_ECONOMY" \
  --notify "$DETECTED_NOTIFY" \
  --commits "$DETECTED_COMMITS" \
  --mcp-profile "$DETECTED_MCP_PROFILE" \
  --config merge \
  --settings merge

echo ""
echo -e "${GREEN}  ✓ Updated v${OLD_VERSION} → v${NEW_VERSION}${NC}"
echo -e "  Type ${BOLD}/supercharger${NC} in any chat to see what's available."
echo ""
