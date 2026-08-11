#!/usr/bin/env bash
# Claude Supercharger — Release Automation
# Bumps version, prepends CHANGELOG entry, runs tests, commits, tags, pushes.
#
# Usage: bash tools/release.sh [patch|minor|major] [--message "..."] [--dry-run] [--yes]
#   patch     0.0.X — bug fixes, minor additions (default)
#   minor     0.X.0 — new features, backwards-compatible
#   major     X.0.0 — breaking changes
#   --yes     auto-confirm both prompts (for a tool-invoked shell that cannot answer)

set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

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
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major) BUMP_TYPE="$1"; shift ;;
    --message|-m)      MESSAGE="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    # v2.26.75: this script has TWO prompts and had no way to answer either from a
    # tool-invoked shell, so /sc-update's non-interactive path had no counterpart
    # here. Same flag names as update.sh — a second spelling for the same idea is
    # its own papercut.
    --yes|-y|--non-interactive) ASSUME_YES=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Read a y/N answer, or take the answer as given under --yes.
confirm() { # prompt -> 0 = proceed, 1 = declined
  local _ans
  if $ASSUME_YES; then echo -e "$1 ${YELLOW}[--yes]${NC}"; return 0; fi
  echo -n "$1 "
  read -r _ans
  [ "$_ans" = "y" ] || [ "$_ans" = "Y" ]
}

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
# have not run yet. Declining HERE is free — nothing has been written yet.
confirm "Proceed? [y/N]" || { echo "Aborted."; exit 0; }
echo ""

# ── Rollback snapshot ─────────────────────────────────────────────────────────
# v2.26.75: everything below rewrites the tree, but the SECOND confirm ("commit
# these N files?") came after all of it. Declining there exited 0 with six version
# fields bumped, a CHANGELOG entry prepended and the lot staged — and the message
# said "'git reset' to unstage", which unstages without reverting the bump. The
# next run then read the already-bumped VERSION as CURRENT and produced v+2,
# releasing v+2 with v+1's content. Hit for real releasing v2.26.74.
#
# Restore from a byte snapshot rather than `git checkout --`: the checkout would
# also destroy uncommitted edits to CHANGELOG.md or README.md that were in the
# tree BEFORE the release started. This puts back exactly what this script saw.
_RB_FILES="lib/utils.sh tools/supercharger.sh README.md CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json"
_RB_DIR=$(mktemp -d)
for _rb_f in $_RB_FILES; do
  if [ -f "$REPO_DIR/$_rb_f" ]; then
    cp "$REPO_DIR/$_rb_f" "$_RB_DIR/$(printf '%s' "$_rb_f" | tr '/' '_')"
  fi
done

rollback_bump() {
  local _f _s
  for _f in $_RB_FILES; do
    _s="$_RB_DIR/$(printf '%s' "$_f" | tr '/' '_')"
    if [ -f "$_s" ]; then cp "$_s" "$REPO_DIR/$_f"; fi
  done
  # Unstage too — `git add -A` ran before the confirm. Files the user had staged
  # themselves before invoking this script are the acceptable loss; the tracked
  # CONTENT is untouched either way.
  git -C "$REPO_DIR" reset -q >/dev/null 2>&1 || true
  rm -rf "$_RB_DIR"
}

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
  # Also past the snapshot, so this early exit has to revert too — otherwise it
  # leaves the same half-bumped tree the confirm-decline used to.
  rollback_bump
  echo -e "${RED}Error:${NC} nothing staged — no changes to release. Version bump reverted."
  exit 1
fi

STAGED_COUNT=$(printf '%s\n' "$STAGED" | wc -l | tr -d ' ')
printf '%s\n' "$STAGED" | sed 's/^/  /'
echo ""
if ! confirm "Commit these ${STAGED_COUNT} file(s) as v${NEW}? [y/N]"; then
  rollback_bump
  echo -e "${YELLOW}Aborted — version bump and CHANGELOG entry REVERTED, nothing staged.${NC}"
  echo "  The tree is back to its pre-release state; re-run when ready."
  exit 0
fi

# Past the last decision point — the snapshot has no further use.
rm -rf "$_RB_DIR"

git -C "$REPO_DIR" commit -m "chore: release v${NEW}"
echo -e "  ${GREEN}✓${NC} Committed"

git -C "$REPO_DIR" tag "v${NEW}"
echo -e "  ${GREEN}✓${NC} Tagged v${NEW}"

# v2.26.25: was `push origin master`, unconditionally. Releases in this repo are
# cut on a release/X branch and merged to master afterwards, so that line pushed
# a branch the commit was not on: git printed "Everything up-to-date", exited 0,
# and the tag went to the remote pointing at a commit no remote branch contained.
# A green "Released" for a release nobody could fetch. Push what was actually
# committed — HEAD — and say plainly when the work is not on master yet.
BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
git -C "$REPO_DIR" push origin "$BRANCH"
git -C "$REPO_DIR" push origin "v${NEW}"
echo -e "  ${GREEN}✓${NC} Pushed ${BRANCH} + v${NEW}"

echo ""
if [ "$BRANCH" = "master" ]; then
  echo -e "${GREEN}${BOLD}Released v${NEW}${NC}"
else
  # Not an error — it is the normal branch flow — but the release is only half
  # done, and the tag already points at an unmerged commit. Saying "Released"
  # here is what made the gap easy to miss.
  echo -e "${YELLOW}${BOLD}Tagged v${NEW} on ${BRANCH} — NOT yet on master.${NC}"
  echo -e "  v${NEW} points at a commit master does not contain. Finish with:"
  echo -e "    git checkout master"
  echo -e "    git merge --no-ff ${BRANCH} -m \"Merge ${NEW} — <summary>\""
  echo -e "    git push origin master"
fi
