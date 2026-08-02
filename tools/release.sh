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

# ── Run tests (once) ──────────────────────────────────────────────────────────
# One run serves both purposes: it gates the release AND supplies TEST_COUNT for
# the CHANGELOG line. This used to be two full runs — one for the count, one to
# gate — which turned a ~7-minute suite into a ~14-minute release and was a large
# part of why this script went unused in favour of hand-rolled commits.
echo ""
echo -e "${BOLD}Running tests...${NC}"
if ! TEST_OUTPUT=$(bash "$REPO_DIR/tests/run.sh" < /dev/null 2>&1); then
  printf '%s\n' "$TEST_OUTPUT" | tail -5
  echo -e "${RED}Tests failed. Aborting release.${NC}"
  exit 1
fi
printf '%s\n' "$TEST_OUTPUT" | tail -3

# Last '<n> passed' in the output is the grand total (per-file totals precede it).
TEST_COUNT=$(printf '%s\n' "$TEST_OUTPUT" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "?")
CHANGELOG_LINE="- [${NEW}] - ${TODAY} — ${MESSAGE}. ${TEST_COUNT} tests passing."

echo ""
echo -e "${BOLD}CHANGELOG entry:${NC}"
echo "  $CHANGELOG_LINE"
echo ""

# Confirm AFTER the gate: never ask someone to approve a release whose tests
# have not run yet.
echo -n "Proceed? [y/N] "
read -r CONFIRM
[ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { echo "Aborted."; exit 0; }
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
# v2.26.25: was `grep -n … | head -1`. grep now emits ~122KB of matches and the
# pipe buffer is 64KB, so head exited first, grep took SIGPIPE, and `set -o
# pipefail` turned that into a non-zero pipeline that `set -e` killed the script
# on — silently, right after the version files were bumped. Size-dependent, so it
# worked for every release until the CHANGELOG crossed the buffer. `-m1` makes
# grep stop on its own and removes the pipe.
FIRST_ENTRY=$(grep -n -m1 '^\- \[' "$CHANGELOG" | cut -d: -f1)

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
# Stage everything, not a fixed list. The old fixed list (lib/utils.sh,
# tools/supercharger.sh, README.md, CHANGELOG.md, .claude-plugin/*) meant a
# release commit could contain the version bump and *not the change it was
# releasing* — v2.24.6 would have shipped bumped badges with tests/run.sh left
# behind in the working tree. Any release touching a hook, lib, tool or test hit
# this, which is why releases have been hand-rolled instead.
#
# 'git add -A' honours .gitignore, but it is broader than the old behaviour, so
# the staged set is printed and confirmed below — that preview is what keeps a
# stray file out of a tagged, pushed commit.
echo ""
echo -e "${BOLD}Staging all changes...${NC}"
git -C "$REPO_DIR" add -A

STAGED=$(git -C "$REPO_DIR" diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo -e "${RED}Error:${NC} nothing staged — no changes to release."
  exit 1
fi

STAGED_COUNT=$(printf '%s\n' "$STAGED" | wc -l | tr -d ' ')
printf '%s\n' "$STAGED" | sed 's/^/  /'
echo ""
echo -n "Commit these ${STAGED_COUNT} file(s) as v${NEW}? [y/N] "
read -r CONFIRM_FILES
if [ "$CONFIRM_FILES" != "y" ] && [ "$CONFIRM_FILES" != "Y" ]; then
  echo "Aborted — changes left staged; 'git reset' to unstage."
  exit 0
fi

git -C "$REPO_DIR" commit -m "chore: release v${NEW}"
echo -e "  ${GREEN}✓${NC} Committed"

git -C "$REPO_DIR" tag "v${NEW}"
echo -e "  ${GREEN}✓${NC} Tagged v${NEW}"

git -C "$REPO_DIR" push origin master
git -C "$REPO_DIR" push origin "v${NEW}"
echo -e "  ${GREEN}✓${NC} Pushed"

echo ""
echo -e "${GREEN}${BOLD}Released v${NEW}${NC}"
