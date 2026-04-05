#!/usr/bin/env bash
# Claude Supercharger — Smart Updater
# Detects current settings, backs up, pulls, and reinstalls while preserving config.
# Usage: bash tools/update.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Verify this is a git repo
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "  ✗ Not a git repository: $REPO_DIR" >&2
  echo "  ✗ Update requires a git clone. See README for installation." >&2
  exit 1
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
