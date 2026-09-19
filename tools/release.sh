#!/usr/bin/env bash
# Claude Supercharger — Release Automation
# Bumps version, prepends CHANGELOG entry, runs tests, commits, tags, pushes.
#
# Usage:
#   bash tools/release.sh stage <patch|minor|major|X.Y.Z> [--message "..."] [--yes]
#     Run local smoke gate, bump, commit chore: release vX.Y.Z on branch rel/X.Y.Z,
#     push the branch only. CI then gates before anything reaches master.
#   bash tools/release.sh promote <X.Y.Z> [--yes]
#     Require CI green on ALL jobs (incl. Windows) for rel/X.Y.Z,
#     fast-forward master, tag, push, publish GitHub release, delete rel branch.
#   bash tools/release.sh [patch|minor|major|X.Y.Z] [--message "..."] [--dry-run] [--yes]
#     Legacy direct path: commit, tag, push master without waiting for CI.
#     (stage/promote is the CI-gated path; prefer it.)

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

# ── Subcommand dispatch ───────────────────────────────────────────────────────
# First positional arg may be 'stage' or 'promote'; everything else is the legacy
# path. Subcommand args are consumed here so the shared arg loop below is unaware.
SUBCOMMAND=""
PROMOTE_VERSION=""
case "${1:-}" in
  stage)
    SUBCOMMAND="stage"; shift
    ;;
  promote)
    SUBCOMMAND="promote"; shift
    PROMOTE_VERSION="${1:-}"
    case "$PROMOTE_VERSION" in
      [0-9]*.[0-9]*.[0-9]*) shift ;;
      *) echo "Usage: bash tools/release.sh promote X.Y.Z [--yes]"; exit 1 ;;
    esac
    ;;
esac

# ── Parse args ────────────────────────────────────────────────────────────────
BUMP_TYPE="patch"
MESSAGE=""
DRY_RUN=false
ASSUME_YES=false
EXPLICIT_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major) BUMP_TYPE="$1"; shift ;;
    # An explicit X.Y.Z, for when the computed bump is not the version you want.
    # The repo carries 53 orphaned v3.x tags from an earlier scheme (2026-04), so
    # `major` off a 2.x version computes 3.0.0 and collides with a published tag.
    [0-9]*.[0-9]*.[0-9]*) EXPLICIT_VERSION="$1"; shift ;;
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

# ── Shared helpers ────────────────────────────────────────────────────────────

# Read a y/N answer, or take the answer as given under --yes.
confirm() { # prompt -> 0 = proceed, 1 = declined
  local _ans
  if $ASSUME_YES; then echo -e "$1 ${YELLOW}[--yes]${NC}"; return 0; fi
  echo -n "$1 "
  read -r _ans
  [ "$_ans" = "y" ] || [ "$_ans" = "Y" ]
}

# Populate globals: CURRENT, MAJOR, MINOR, PATCH, NEW, TODAY
compute_new_version() {
  CURRENT=$(grep -m1 '^VERSION=' "$REPO_DIR/lib/utils.sh" | tr -d '"' | cut -d= -f2)
  if [ -z "$CURRENT" ]; then
    echo -e "${RED}Error:${NC} Could not read VERSION from lib/utils.sh"; exit 1
  fi
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
  case "$BUMP_TYPE" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  esac
  NEW="${MAJOR}.${MINOR}.${PATCH}"
  if [ -n "$EXPLICIT_VERSION" ]; then
    NEW="$EXPLICIT_VERSION"; BUMP_TYPE="explicit"
  fi
  TODAY=$(date +%Y-%m-%d)
}

# Refuse a version whose tag already exists.
# Refuse existing tag BEFORE the test run and before anything is written.
check_tag_not_exists() {
  if git -C "$REPO_DIR" rev-parse "v$NEW" >/dev/null 2>&1; then
    echo "Tag v$NEW already exists locally — pick another version."; exit 1
  fi
  # Remote check skipped under --dry-run (see legacy-path comment).
  if [ "$DRY_RUN" = false ] && git ls-remote --exit-code --tags origin "v$NEW" >/dev/null 2>&1; then
    echo "Tag v$NEW already exists on origin — pick another version."; exit 1
  fi
}

# Populate/prompt MESSAGE. Requires REPO_DIR and git context.
collect_message() {
  local _tag_base
  _tag_base=$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null \
    || git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
  if [ -z "$MESSAGE" ]; then
    echo -e "${BOLD}Recent commits since last release:${NC}"
    git -C "$REPO_DIR" log "${_tag_base}..HEAD" \
      --oneline --no-decorate 2>/dev/null | head -20 || true
    echo ""
    echo -n "CHANGELOG entry (one line, leave blank to auto-generate from commits): "
    read -r MESSAGE
  fi
  if [ -z "$MESSAGE" ]; then
    MESSAGE=$(git -C "$REPO_DIR" log "${_tag_base}..HEAD" \
      --oneline --no-decorate 2>/dev/null \
      | grep -vE '^[a-f0-9]+ chore:' \
      | head -5 \
      | sed 's/^[a-f0-9]* //' \
      | tr '\n' '; ' \
      | sed 's/; $//' \
      || echo "maintenance release")
  fi
  # The CHANGELOG line appends ". N tests passing.", so a message that already
  # ends in a period produced "…fix.. 5761 tests passing." Strip trailing
  # periods and spaces; every other punctuation mark is the author's.
  while [ "${MESSAGE% }" != "$MESSAGE" ] || [ "${MESSAGE%.}" != "$MESSAGE" ]; do
    MESSAGE="${MESSAGE% }"; MESSAGE="${MESSAGE%.}"
  done
}

# ── Rollback snapshot ─────────────────────────────────────────────────────────
# v2.26.75: declining the second confirm left six version fields bumped, a
# CHANGELOG entry prepended and the lot staged — next run produced v+2 with v+1's
# content. Snapshot restores byte-for-byte, not via git checkout (which destroys
# uncommitted edits to CHANGELOG/README that existed before the release started).
_RB_FILES="lib/utils.sh tools/supercharger.sh README.md CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json"
_RB_DIR=""

take_rollback_snapshot() {
  _RB_DIR=$(mktemp -d)
  local _rb_f
  for _rb_f in $_RB_FILES; do
    if [ -f "$REPO_DIR/$_rb_f" ]; then
      cp "$REPO_DIR/$_rb_f" "$_RB_DIR/$(printf '%s' "$_rb_f" | tr '/' '_')"
    fi
  done
}

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
  _RB_DIR=""
}

# ── Version bump + CHANGELOG (shared between stage and legacy) ────────────────
# Requires globals: CURRENT, NEW, TEST_COUNT (may be "?"), TODAY, CHANGELOG_LINE

do_version_bump() {
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

  if [ "$TEST_COUNT" != "?" ]; then
    sed -i.bak "s/tests-[0-9]*%20passing/tests-${TEST_COUNT}%20passing/" "$REPO_DIR/README.md"
    rm -f "$REPO_DIR/README.md.bak"
    echo -e "  ${GREEN}✓${NC} README.md (tests badge → ${TEST_COUNT})"
  fi

  local pfile
  for pfile in "$REPO_DIR/.claude-plugin/plugin.json" "$REPO_DIR/.claude-plugin/marketplace.json"; do
    if [ -f "$pfile" ]; then
      sed -i.bak "s/\"version\": \"${CURRENT}\"/\"version\": \"${NEW}\"/g" "$pfile"
      rm -f "${pfile}.bak"
      echo -e "  ${GREEN}✓${NC} $(basename "$pfile")"
    fi
  done
}

do_prepend_changelog() {
  local CHANGELOG="$REPO_DIR/CHANGELOG.md"
  # v2.26.25: `-m1` stops grep after the first match so head never causes SIGPIPE.
  local FIRST_ENTRY
  FIRST_ENTRY=$(grep -n -m1 '^\- \[' "$CHANGELOG" | cut -d: -f1)
  if [ -n "$FIRST_ENTRY" ]; then
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
}

# Shared stage/commit sequence: add -A, preview, confirm, commit on current branch.
# Requires globals: NEW. Sets nothing. Calls rollback_bump + exit on decline.
do_stage_and_confirm_commit() {
  echo ""
  echo -e "${BOLD}Staging all changes...${NC}"
  git -C "$REPO_DIR" add -A

  local STAGED
  STAGED=$(git -C "$REPO_DIR" diff --cached --name-only)
  if [ -z "$STAGED" ]; then
    rollback_bump
    echo -e "${RED}Error:${NC} nothing staged — no changes to release. Version bump reverted."
    exit 1
  fi

  local STAGED_COUNT
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
  rm -rf "$_RB_DIR"; _RB_DIR=""

  git -C "$REPO_DIR" commit -m "chore: release v${NEW}"
  echo -e "  ${GREEN}✓${NC} Committed"
}

# Create the GitHub release object. Loud on failure — never silent green.
# Uses globals: NEW, MESSAGE
publish_github_release() {
  command -v gh >/dev/null 2>&1 || { echo -e "  ${YELLOW}!${NC} gh not installed — no GitHub release for v${NEW}"; return 1; }
  gh auth status >/dev/null 2>&1 || { echo -e "  ${YELLOW}!${NC} gh not authenticated — no GitHub release for v${NEW}"; return 1; }
  local title
  title=$(printf '%s\n' "$MESSAGE" | head -1)
  [ -n "$title" ] && title="v${NEW} — ${title}" || title="v${NEW}"
  gh release create "v${NEW}" --title "$title" --generate-notes >/dev/null 2>&1 || return 1
  # Verify by BEHAVIOUR, not by exit code. [[silent-success-tooling]]
  gh release view "v${NEW}" >/dev/null 2>&1
}

# ── Per-file smoke gate (OOM-safe) ────────────────────────────────────────────
# Runs each tests/test-*.sh in its own subshell with an isolated HOME and CI=1.
# Sets global TEST_COUNT (total passing). Returns 1 if any file has failures.
#
# Replaces `bash tests/run.sh` for the stage path: run.sh OOMs on this box.
# The REAL gate is CI green in promote — this is a fast pre-filter only.
# ponytail: sequential per-file; upgrade to parallel if gate latency matters.
TEST_COUNT="?"
run_per_file_gate() {
  local gate_dir="${1:-$REPO_DIR}"
  local total_passed=0 total_failed=0 failed_files="" f iso_home out f_passed f_failed

  echo -e "${BOLD}Running tests (per-file smoke gate)...${NC}"

  for f in "$gate_dir"/tests/test-*.sh; do
    [ -f "$f" ] || continue
    iso_home=$(mktemp -d)
    # Isolated HOME + CI=1; capture output AND exit code (rc).
    out=$(HOME="$iso_home" CI=1 bash "$f" < /dev/null 2>&1) && rc=0 || rc=$?
    rm -rf "$iso_home"

    # "N passed" and "M failed" are substrings of the report() output line.
    # ANSI codes surround the numbers but the words "passed"/"failed" are bare,
    # so grep -oE '[0-9]+ passed' matches even with colour codes around the digit.
    f_passed=$(printf '%s\n' "$out" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '^[0-9]+' || true)
    f_failed=$(printf '%s\n' "$out" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '^[0-9]+' || true)
    f_passed="${f_passed:-0}"
    f_failed="${f_failed:-0}"

    # A file that exits non-zero WITHOUT a "M failed" report line has crashed
    # before reporting (harness died, syntax error, killed). Counting it as 0/0
    # would make a broken file invisible to the gate — flag it as one failure.
    if [ "$f_failed" -eq 0 ] && [ "$rc" -ne 0 ]; then
      f_failed=1
      failed_files="${failed_files}
  $(basename "$f") (crashed, rc=${rc}, no report line)"
    elif [ "$f_failed" -gt 0 ]; then
      failed_files="${failed_files}
  $(basename "$f") (${f_failed} failed)"
    fi

    total_passed=$((total_passed + f_passed))
    if [ "$f_failed" -gt 0 ]; then
      total_failed=$((total_failed + f_failed))
    fi
  done

  TEST_COUNT="$total_passed"

  if [ "$total_failed" -gt 0 ]; then
    echo -e "${RED}Smoke gate: ${total_failed} test(s) failed in:${NC}${failed_files}"
    return 1
  fi

  echo -e "  ${GREEN}✓${NC} ${total_passed} tests passed (smoke gate)"
}

# ── cmd_stage ─────────────────────────────────────────────────────────────────
cmd_stage() {
  compute_new_version

  # Stage must run from master so rel/ is off the current master commit.
  local ORIG_BRANCH
  ORIG_BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
  if [ "$ORIG_BRANCH" != "master" ]; then
    echo -e "${RED}Error:${NC} 'stage' must be run from master (currently on ${ORIG_BRANCH})."
    exit 1
  fi

  check_tag_not_exists

  echo -e "${CYAN}${BOLD}Claude Supercharger Release (stage)${NC}"
  echo -e "  ${CURRENT} → ${BOLD}${NEW}${NC}  (${BUMP_TYPE})"
  echo ""

  collect_message

  echo ""

  # Local smoke gate — OOM-safe per-file runner; real gate is CI in promote.
  run_per_file_gate "$REPO_DIR" || {
    echo -e "${RED}Fix failing tests before staging.${NC}"; exit 1
  }

  CHANGELOG_LINE="- [${NEW}] - ${TODAY} — ${MESSAGE}. ${TEST_COUNT} tests passing."

  echo ""
  echo -e "${BOLD}CHANGELOG entry:${NC}"
  echo "  $CHANGELOG_LINE"
  echo ""

  # Confirm AFTER the gate: never ask someone to approve a release whose tests
  # have not run yet. Declining HERE is free — nothing has been written yet.
  confirm "Proceed? [y/N]" || { echo "Aborted."; exit 0; }
  echo ""

  # Snapshot BEFORE touching any file — rollback_bump restores on decline.
  take_rollback_snapshot

  do_version_bump
  echo ""
  do_prepend_changelog

  # Create rel/X.Y.Z NOW — before staging or committing — so the release
  # commit lands on rel/, not on master. master's HEAD never advances.
  local REL_BRANCH="rel/${NEW}"

  # Cleanup trap: on any failure after branch creation, restore master.
  # Called by the EXIT trap if set -e aborts mid-way, OR by the decline path in
  # do_stage_and_confirm_commit (which exits 0 after rollback_bump; EXIT fires).
  local _STAGE_CLEANUP_BRANCH=""
  _stage_cleanup() {
    [ -n "$_STAGE_CLEANUP_BRANCH" ] || return 0
    # Restore version files from snapshot if the commit never happened.
    if [ -n "$_RB_DIR" ] && [ -d "$_RB_DIR" ]; then rollback_bump; fi
    # -f: the working tree may have bumped files not yet staged/committed.
    git -C "$REPO_DIR" checkout master >/dev/null 2>&1 || \
      git -C "$REPO_DIR" checkout -f master >/dev/null 2>&1 || true
    git -C "$REPO_DIR" branch -D "$_STAGE_CLEANUP_BRANCH" >/dev/null 2>&1 || true
    _STAGE_CLEANUP_BRANCH=""
  }
  trap _stage_cleanup EXIT INT TERM

  git -C "$REPO_DIR" checkout -b "$REL_BRANCH"
  _STAGE_CLEANUP_BRANCH="$REL_BRANCH"
  echo -e "  ${GREEN}✓${NC} Created branch ${REL_BRANCH}"

  # Stage + confirm + commit, all on rel/X.Y.Z.
  # On decline: rollback_bump reverts files + unstages, then exits 0;
  # EXIT trap fires _stage_cleanup → git checkout master → branch -D rel/.
  do_stage_and_confirm_commit

  git -C "$REPO_DIR" push -u origin "$REL_BRANCH"
  echo -e "  ${GREEN}✓${NC} Pushed ${REL_BRANCH}"
  local REL_SHA
  REL_SHA=$(git -C "$REPO_DIR" rev-parse "$REL_BRANCH")

  # Return to master. Its HEAD is still the pre-release commit; git restores
  # the working tree to master's state (unbumped files) automatically.
  git -C "$REPO_DIR" checkout master
  _STAGE_CLEANUP_BRANCH=""  # Promote handles the rest; no local cleanup needed.
  trap - EXIT INT TERM

  echo ""

  # Print CI URL if gh is available. Match on headSha, the way promote does:
  # rel/ branch names repeat across attempts, and at stage time the new run has
  # usually not been created yet — so --limit 1 by branch name printed the
  # PREVIOUS attempt's run, a green URL for a build that never tested this code.
  # No match yet is the normal case; fall back to the branch message.
  local CI_URL=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    CI_URL=$(gh run list --branch "$REL_BRANCH" --limit 10 --json headSha,url \
      2>/dev/null | python3 -c "
import sys, json
runs = json.load(sys.stdin)
sha = sys.argv[1]
print(next((r['url'] for r in runs if r.get('headSha') == sha), ''))
" "$REL_SHA" 2>/dev/null || true)
  fi

  echo -e "${GREEN}${BOLD}Staged v${NEW} on ${REL_BRANCH}${NC}"
  if [ -n "$CI_URL" ]; then
    echo "  CI: ${CI_URL}"
  else
    echo "  CI: check Actions for branch ${REL_BRANCH}"
  fi
  echo ""
  echo "  When ALL CI jobs are green (including Windows (Git Bash)), run:"
  echo "    bash tools/release.sh promote ${NEW}"
}

# ── cmd_promote ───────────────────────────────────────────────────────────────
cmd_promote() {
  local VER="$PROMOTE_VERSION"
  local REL_BRANCH="rel/${VER}"

  echo -e "${CYAN}${BOLD}Claude Supercharger Release (promote)${NC}"
  echo -e "  Promoting ${REL_BRANCH} → master + tag + GitHub release"
  echo ""

  # 1. Fetch so origin refs are current.
  echo "Fetching from origin..."
  git -C "$REPO_DIR" fetch origin >/dev/null 2>&1

  # 2. Require origin/rel/X.Y.Z to exist.
  if ! git -C "$REPO_DIR" rev-parse "origin/${REL_BRANCH}" >/dev/null 2>&1; then
    echo -e "${RED}Error:${NC} origin/${REL_BRANCH} does not exist."
    echo "Run 'bash tools/release.sh stage ${VER}' first."
    exit 1
  fi

  # 3. CI gate — require completed + every job success, incl. Windows (Git Bash).
  command -v gh >/dev/null 2>&1 || {
    echo -e "${RED}Error:${NC} gh not installed — cannot gate on CI."; exit 1
  }
  gh auth status >/dev/null 2>&1 || {
    echo -e "${RED}Error:${NC} gh not authenticated — run: gh auth login"; exit 1
  }

  local BRANCH_SHA
  BRANCH_SHA=$(git -C "$REPO_DIR" rev-parse "origin/${REL_BRANCH}")
  echo "Branch HEAD: ${BRANCH_SHA}"

  # Find the run whose headSha matches the branch tip.
  local RUN_JSON
  RUN_JSON=$(gh run list --branch "$REL_BRANCH" --limit 10 \
    --json headSha,status,conclusion,databaseId,url 2>/dev/null || echo "[]")

  # Extract fields for the matching run. Python handles both compact and pretty JSON.
  local RUN_STATUS RUN_CONCLUSION RUN_ID
  RUN_STATUS=$(printf '%s' "$RUN_JSON" | python3 -c "
import sys, json
runs = json.load(sys.stdin)
sha = sys.argv[1]
for r in runs:
    if r.get('headSha') == sha:
        print(r.get('status', 'none')); sys.exit(0)
print('none')
" "$BRANCH_SHA" 2>/dev/null || echo "none")

  if [ "$RUN_STATUS" = "none" ]; then
    echo -e "${RED}Error:${NC} No CI run found for ${REL_BRANCH} at ${BRANCH_SHA}."
    echo "CI may not have started yet. Check: gh run list --branch ${REL_BRANCH}"
    exit 1
  fi

  if [ "$RUN_STATUS" != "completed" ]; then
    echo "CI is not finished yet (status: ${RUN_STATUS})."
    echo "Re-run promote when all jobs are green:"
    echo "  bash tools/release.sh promote ${VER}"
    exit 1  # NOT a rollback — nothing has been changed.
  fi

  RUN_CONCLUSION=$(printf '%s' "$RUN_JSON" | python3 -c "
import sys, json
runs = json.load(sys.stdin)
sha = sys.argv[1]
for r in runs:
    if r.get('headSha') == sha:
        print(r.get('conclusion', 'none')); sys.exit(0)
print('none')
" "$BRANCH_SHA" 2>/dev/null || echo "none")

  RUN_ID=$(printf '%s' "$RUN_JSON" | python3 -c "
import sys, json
runs = json.load(sys.stdin)
sha = sys.argv[1]
for r in runs:
    if r.get('headSha') == sha:
        print(r.get('databaseId', '')); sys.exit(0)
print('')
" "$BRANCH_SHA" 2>/dev/null || echo "")

  echo "CI run: completed / ${RUN_CONCLUSION} (id: ${RUN_ID})"

  # Job-level check.
  local JOBS_JSON FAILED_JOBS WINDOWS_PRESENT
  JOBS_JSON=$(gh run view "$RUN_ID" --json jobs 2>/dev/null || echo '{"jobs":[]}')

  FAILED_JOBS=$(printf '%s' "$JOBS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
failed = [j['name'] for j in d.get('jobs', []) if j.get('conclusion') != 'success']
print('\n'.join(failed))
" 2>/dev/null || echo "")

  if [ -n "$FAILED_JOBS" ]; then
    echo -e "${RED}CI gate failed — these jobs did not succeed:${NC}"
    printf '%s\n' "$FAILED_JOBS" | sed 's/^/  FAILED: /'
    exit 1
  fi

  # Explicitly verify the Windows job was present and green.
  WINDOWS_PRESENT=$(printf '%s' "$JOBS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
win = [j for j in d.get('jobs', []) if 'Windows (Git Bash)' in j.get('name', '')]
print('yes' if win else 'no')
" 2>/dev/null || echo "no")

  if [ "$WINDOWS_PRESENT" != "yes" ]; then
    echo -e "${RED}CI gate:${NC} 'Windows (Git Bash)' job not found in run ${RUN_ID}."
    echo "All jobs must succeed including Windows. Check: gh run view ${RUN_ID}"
    exit 1
  fi

  echo -e "  ${GREEN}✓${NC} All CI jobs succeeded (including Windows (Git Bash))"
  echo ""

  # 4. Fast-forward master to rel/X.Y.Z.
  # Verify before confirming so the user does not approve a doomed operation.
  local CUR_BRANCH
  CUR_BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
  if [ "$CUR_BRANCH" != "master" ]; then
    git -C "$REPO_DIR" checkout master >/dev/null 2>&1
  fi
  # Sync local master from origin before the FF check.
  git -C "$REPO_DIR" pull --ff-only origin master >/dev/null 2>&1

  local MASTER_SHA REL_TIP
  MASTER_SHA=$(git -C "$REPO_DIR" rev-parse master)
  REL_TIP=$(git -C "$REPO_DIR" rev-parse "origin/${REL_BRANCH}")

  # master must be an ancestor-or-equal of rel/ for FF to succeed.
  if ! git -C "$REPO_DIR" merge-base --is-ancestor "$MASTER_SHA" "$REL_TIP" 2>/dev/null; then
    echo -e "${RED}Error:${NC} master cannot be fast-forwarded to ${REL_BRANCH}."
    echo "master has diverged. Do NOT force. Resolve with:"
    echo "  git log --oneline master...origin/${REL_BRANCH}"
    exit 1
  fi

  confirm "Merge ${REL_BRANCH} → master (fast-forward) and publish v${VER}? [y/N]" \
    || { echo "Aborted."; exit 0; }
  echo ""

  if ! git -C "$REPO_DIR" merge --ff-only "origin/${REL_BRANCH}"; then
    # Should not reach here (we checked above), but guard for races.
    echo -e "${RED}Error:${NC} fast-forward failed — master may have changed concurrently."
    echo "Do NOT force. Re-run promote after investigating."
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} master fast-forwarded to ${REL_BRANCH}"

  # 5. Tag AFTER the commit is on master.
  git -C "$REPO_DIR" tag "v${VER}"
  echo -e "  ${GREEN}✓${NC} Tagged v${VER}"

  # 6. Push master then tag.
  git -C "$REPO_DIR" push origin master
  git -C "$REPO_DIR" push origin "v${VER}"
  echo -e "  ${GREEN}✓${NC} Pushed master + v${VER}"

  # 7. Publish GitHub release; loud on failure. [[guard-fails-open-oracle-fails-loud]]
  # Set the globals publish_github_release reads.
  NEW="$VER"; MESSAGE=""
  echo ""
  if publish_github_release; then
    echo -e "  ${GREEN}✓${NC} Published GitHub release v${VER}"
  else
    echo -e "  ${YELLOW}${BOLD}!${NC} ${YELLOW}GitHub release NOT created for v${VER}.${NC}"
    echo -e "    The tag is pushed; the code is released. Releases page is not updated."
    echo -e "    Create it with:  gh release create v${VER} --generate-notes"
  fi

  # 8. Delete rel branch local + remote (best-effort; not fatal if missing).
  git -C "$REPO_DIR" push origin --delete "$REL_BRANCH" >/dev/null 2>&1 || true
  git -C "$REPO_DIR" branch -d "$REL_BRANCH" >/dev/null 2>&1 || true
  echo -e "  ${GREEN}✓${NC} Deleted ${REL_BRANCH}"

  echo ""
  echo -e "${GREEN}${BOLD}Released v${VER}${NC}"
}

# ── cmd_legacy ────────────────────────────────────────────────────────────────
# The original direct-to-master path, preserved exactly. Prints a one-line note
# that stage/promote is the CI-gated alternative.
cmd_legacy() {
  compute_new_version

  # Refuse a version whose tag already exists, BEFORE the 7-minute test run and
  # before anything is written. Tagging is the last step, so a collision used to
  # surface only after the suite had run and the version bump and CHANGELOG entry
  # were already committed.
  check_tag_not_exists

  echo -e "${CYAN}${BOLD}Claude Supercharger Release${NC}"
  echo -e "  ${CURRENT} → ${BOLD}${NEW}${NC}  (${BUMP_TYPE})"
  echo ""

  collect_message

  if $DRY_RUN; then
    echo -e "${YELLOW}[dry-run] Would update: lib/utils.sh, tools/supercharger.sh, README.md, CHANGELOG.md${NC}"
    echo -e "${YELLOW}[dry-run] Would commit, tag v${NEW}, push, publish a GitHub release${NC}"
    exit 0
  fi

  # ── Run tests (once) ─────────────────────────────────────────────────────────
  # One run serves both purposes: it gates the release AND supplies TEST_COUNT for
  # the CHANGELOG line.
  # v2.29.26: gate on a CLEAN checkout, not on the release's own dirty tree.
  local GATE_DIR GATE_WT
  GATE_DIR="$REPO_DIR"
  GATE_WT=""
  cleanup_gate_wt() {
    [ -n "$GATE_WT" ] || return 0
    git -C "$REPO_DIR" worktree remove --force "$GATE_WT" >/dev/null 2>&1 || rm -rf "$GATE_WT"
    GATE_WT=""
  }
  trap cleanup_gate_wt EXIT INT TERM

  if [ "${SUPERCHARGER_RELEASE_GATE_INPLACE:-0}" != "1" ] \
     && git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local _wt
    _wt=$(mktemp -d); rm -rf "$_wt"
    if git -C "$REPO_DIR" worktree add -q --detach "$_wt" HEAD >/dev/null 2>&1; then
      GATE_WT="$_wt"
      while IFS= read -r -d '' f; do
        rm -f "$_wt/$f"
      done < <(git -C "$REPO_DIR" ls-files -z --deleted)
      while IFS= read -r -d '' f; do
        mkdir -p "$_wt/$(dirname "$f")"
        cp -p "$REPO_DIR/$f" "$_wt/$f" 2>/dev/null || true
      done < <(git -C "$REPO_DIR" ls-files -z --modified --others --exclude-standard)
      git -C "$_wt" add -A >/dev/null 2>&1 || true
      git -C "$_wt" -c user.email=release@local -c user.name=release \
          commit -q -m "release candidate" >/dev/null 2>&1 || true
      GATE_DIR="$_wt"
    else
      rm -rf "$_wt"
      echo -e "${YELLOW}Could not create a worktree; gating in place.${NC}" >&2
    fi
  fi

  echo ""
  if [ "$GATE_DIR" = "$REPO_DIR" ]; then
    echo -e "${BOLD}Running tests...${NC} ${YELLOW}(in place -- tree is dirty)${NC}"
  else
    echo -e "${BOLD}Running tests...${NC} (clean checkout of the candidate tree)"
  fi
  local TEST_OUTPUT
  if ! TEST_OUTPUT=$(cd "$GATE_DIR" && bash tests/run.sh < /dev/null 2>&1); then
    printf '%s\n' "$TEST_OUTPUT" | tail -5
    echo -e "${RED}Tests failed. Aborting release.${NC}"
    exit 1
  fi
  printf '%s\n' "$TEST_OUTPUT" | tail -3
  cleanup_gate_wt

  # Last '<n> passed' in the output is the grand total.
  TEST_COUNT=$(printf '%s\n' "$TEST_OUTPUT" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "?")
  CHANGELOG_LINE="- [${NEW}] - ${TODAY} — ${MESSAGE}. ${TEST_COUNT} tests passing."

  echo ""
  echo -e "${BOLD}CHANGELOG entry:${NC}"
  echo "  $CHANGELOG_LINE"
  echo ""

  # Confirm AFTER the gate.
  confirm "Proceed? [y/N]" || { echo "Aborted."; exit 0; }
  echo ""

  take_rollback_snapshot

  do_version_bump

  do_prepend_changelog

  do_stage_and_confirm_commit

  git -C "$REPO_DIR" tag "v${NEW}"
  echo -e "  ${GREEN}✓${NC} Tagged v${NEW}"

  # v2.26.25: push HEAD's branch (not a hard-coded 'master').
  local BRANCH
  BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
  git -C "$REPO_DIR" push origin "$BRANCH"
  git -C "$REPO_DIR" push origin "v${NEW}"
  echo -e "  ${GREEN}✓${NC} Pushed ${BRANCH} + v${NEW}"

  # v4.0.28: create the GitHub RELEASE object (not just the tag).
  echo ""
  if [ "$BRANCH" = "master" ]; then
    if publish_github_release; then
      echo -e "  ${GREEN}✓${NC} Published GitHub release v${NEW}"
    else
      echo -e "  ${YELLOW}${BOLD}!${NC} ${YELLOW}GitHub release NOT created for v${NEW}.${NC}"
      echo -e "    The tag is pushed, so the code is out; the Releases page is not."
      echo -e "    Create it with:  gh release create v${NEW} --generate-notes"
    fi
    echo -e "${GREEN}${BOLD}Released v${NEW}${NC}"
  else
    echo -e "${YELLOW}${BOLD}Tagged v${NEW} on ${BRANCH} — NOT yet on master.${NC}"
    echo -e "  v${NEW} points at a commit master does not contain. Finish with:"
    echo -e "    git checkout master"
    echo -e "    git merge --no-ff ${BRANCH} -m \"Merge ${NEW} — <summary>\""
    echo -e "    git push origin master"
  fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$SUBCOMMAND" in
  stage)   cmd_stage ;;
  promote) cmd_promote ;;
  *)
    # Legacy direct path. Print a note so users discover the CI-gated alternative.
    echo -e "${YELLOW}Note: this legacy path pushes master BEFORE CI runs. Prefer the CI-gated flow: 'release.sh stage <patch|minor|major|X.Y.Z>' then 'release.sh promote X.Y.Z'.${NC}" >&2
    cmd_legacy
    ;;
esac
