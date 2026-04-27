#!/usr/bin/env bash
# Claude Supercharger — Release Automation
# Bumps version, prepends CHANGELOG entry, runs tests, commits, tags, pushes.
#
# Usage: bash tools/release.sh [patch|minor|major] [--message "..."] [--dry-run]
#   patch     0.0.X — bug fixes, minor additions (default)
#   minor     0.X.0 — new features, backwards-compatible
#   major     X.0.0 — breaking changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Parse args ────────────────────────────────────────────────────────────────
BUMP_TYPE="patch"
MESSAGE=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major) BUMP_TYPE="$1"; shift ;;
    --message|-m)      MESSAGE="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Read current version ──────────────────────────────────────────────────────
CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
if [ -z "$CURRENT" ]; then
  echo -e "${RED}Error:${NC} Could not read VERSION from lib/utils.sh"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
TODAY=$(date +%Y-%m-%d)

echo -e "${CYAN}${BOLD}Claude Supercharger Release${NC}"
echo -e "  ${CURRENT} → ${BOLD}${NEW}${NC}  (${BUMP_TYPE})"
echo ""

# ── Collect changelog message ─────────────────────────────────────────────────
if [ -z "$MESSAGE" ]; then
  echo -e "${BOLD}Recent commits since last release:${NC}"
  git log "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD \
    --oneline --no-decorate 2>/dev/null | head -20 || true
  echo ""
  echo -n "CHANGELOG entry (one line, leave blank to auto-generate from commits): "
  read -r MESSAGE
fi

if [ -z "$MESSAGE" ]; then
  # Auto-generate from commits since last tag
  MESSAGE=$(git log "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD \
    --oneline --no-decorate 2>/dev/null \
    | grep -vE '^[a-f0-9]+ chore:' \
    | head -5 \
    | sed 's/^[a-f0-9]* //' \
    | tr '\n' '; ' \
    | sed 's/; $//' \
    || echo "maintenance release")
fi

if $DRY_RUN; then
  echo -e "${YELLOW}[dry-run] Would update: lib/utils.sh, tools/supercharger.sh, README.md, CHANGELOG.md${NC}"
  echo -e "${YELLOW}[dry-run] Would commit, tag v${NEW}, push${NC}"
  exit 0
fi

# Get current test count (skipped in dry-run)
TEST_COUNT=$(bash "$REPO_DIR/tests/run.sh" 2>&1 | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "?")
CHANGELOG_LINE="- [${NEW}] - ${TODAY} — ${MESSAGE}. ${TEST_COUNT} tests passing."

echo ""
echo -e "${BOLD}CHANGELOG entry:${NC}"
echo "  $CHANGELOG_LINE"
echo ""

echo -n "Proceed? [y/N] "
read -r CONFIRM
[ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { echo "Aborted."; exit 0; }

# ── Run tests ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Running tests...${NC}"
if ! bash "$REPO_DIR/tests/run.sh" 2>&1 | tail -3; then
  echo -e "${RED}Tests failed. Aborting release.${NC}"
  exit 1
fi
echo ""

# ── Bump version ──────────────────────────────────────────────────────────────
echo -e "${BOLD}Bumping version files...${NC}"

sed -i.bak "s/^VERSION=\"${CURRENT}\"/VERSION=\"${NEW}\"/" "$REPO_DIR/lib/utils.sh"
rm -f "$REPO_DIR/lib/utils.sh.bak"
echo -e "  ${GREEN}✓${NC} lib/utils.sh"

sed -i.bak "s/^VERSION=\"${CURRENT}\"/VERSION=\"${NEW}\"/" "$REPO_DIR/tools/supercharger.sh"
rm -f "$REPO_DIR/tools/supercharger.sh.bak"
echo -e "  ${GREEN}✓${NC} tools/supercharger.sh"

sed -i.bak "s/version-${CURRENT}-blue/version-${NEW}-blue/" "$REPO_DIR/README.md"
rm -f "$REPO_DIR/README.md.bak"
echo -e "  ${GREEN}✓${NC} README.md (version badge)"

# Update tests badge in README
if [ "$TEST_COUNT" != "?" ]; then
  sed -i.bak "s/tests-[0-9]*%20passing/tests-${TEST_COUNT}%20passing/" "$REPO_DIR/README.md"
  rm -f "$REPO_DIR/README.md.bak"
  echo -e "  ${GREEN}✓${NC} README.md (tests badge → ${TEST_COUNT})"
fi

# Plugin files
for pfile in "$REPO_DIR/.claude-plugin/plugin.json" "$REPO_DIR/.claude-plugin/marketplace.json"; do
  if [ -f "$pfile" ]; then
    sed -i.bak "s/\"version\": \"${CURRENT}\"/\"version\": \"${NEW}\"/g" "$pfile"
    rm -f "${pfile}.bak"
    echo -e "  ${GREEN}✓${NC} $(basename "$pfile")"
  fi
done

# ── Update CHANGELOG ──────────────────────────────────────────────────────────
CHANGELOG="$REPO_DIR/CHANGELOG.md"
FIRST_ENTRY=$(grep -n '^\- \[' "$CHANGELOG" | head -1 | cut -d: -f1)

if [ -n "$FIRST_ENTRY" ]; then
  # Insert before first existing entry
  python3 -c "
import sys
line_num = int(sys.argv[1]) - 1
new_line = sys.argv[2]
with open(sys.argv[3]) as f:
    lines = f.readlines()
lines.insert(line_num, new_line + '\n')
with open(sys.argv[3], 'w') as f:
    f.writelines(lines)
" "$FIRST_ENTRY" "$CHANGELOG_LINE" "$CHANGELOG"
else
  printf '\n%s\n' "$CHANGELOG_LINE" >> "$CHANGELOG"
fi
echo -e "  ${GREEN}✓${NC} CHANGELOG.md"

# ── Commit, tag, push ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Committing...${NC}"
git -C "$REPO_DIR" add \
  lib/utils.sh tools/supercharger.sh README.md CHANGELOG.md \
  .claude-plugin/plugin.json .claude-plugin/marketplace.json 2>/dev/null || true
git -C "$REPO_DIR" add lib/utils.sh tools/supercharger.sh README.md CHANGELOG.md

git -C "$REPO_DIR" commit -m "chore: release v${NEW}"
echo -e "  ${GREEN}✓${NC} Committed"

git -C "$REPO_DIR" tag "v${NEW}"
echo -e "  ${GREEN}✓${NC} Tagged v${NEW}"

git -C "$REPO_DIR" push origin master
git -C "$REPO_DIR" push origin "v${NEW}"
echo -e "  ${GREEN}✓${NC} Pushed"

echo ""
echo -e "${GREEN}${BOLD}Released v${NEW}${NC}"
