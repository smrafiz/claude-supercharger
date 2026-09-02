#!/usr/bin/env bash
# Claude Supercharger — Commit Guard (consolidated)
# Event: PreToolUse | Matcher: Bash
#
# ONE hook, three independent self-gating checks on `git commit`. Merged from the
# former commit-coauthor-guard.sh + commit-check.sh + commit-secret-guard.sh to
# remove 2 process forks from EVERY Bash call (they each fired + fast-exited).
# Behavior is identical — each check keeps its own opt-in/disable flag and its own
# block reason; any check can deny. Order: cheap → expensive (coauthor grep,
# conventional-format parse, then the staged-diff secret scan which forks git).
# Disable: SUPERCHARGER_COMMIT_SECRET_GUARD=0  |  SUPERCHARGER_COMMIT_CODE_SCAN=0
#          SUPERCHARGER_DEFAULT_BRANCH_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Shared fast-path: nothing here matters unless the command mentions a commit.
case "$_INPUT" in *commit*) ;; *) exit 0 ;; esac

# Extract the command once (jq, python fallback).
CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# Confirm a real `git commit` (word boundary — leaves commit-tree/commit-graph alone;
# leading boundary handles chained commands like `... && git commit`).
printf '%s\n' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit([[:space:]]|$)' || exit 0

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

_deny() {  # $1 = reason (plain text) → emit PreToolUse deny + exit 2
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# ─── Check 1: co-author guard (opt-in, default OFF) ──────────────────────────
# Enable per-machine: touch scope/.coauthor-guard ; per-session: SUPERCHARGER_COAUTHOR_GUARD=1 (0 disables).
if ! check_hook_disabled "commit-coauthor-guard"; then
  _ca_on=false
  case "${SUPERCHARGER_COAUTHOR_GUARD:-}" in
    0) _ca_on=false ;;
    1) _ca_on=true ;;
    *) [ -f "$SUPERCHARGER_STATE/scope/.coauthor-guard" ] && _ca_on=true ;;
  esac
  if $_ca_on; then
    case "$CMD" in *"git commit --help"*|*"git commit -h"*) ;; *)
      if printf '%s\n' "$CMD" | grep -qiE 'co-authored-by:'; then
        echo "[Supercharger] commit-coauthor-guard: blocked AI attribution trailer" >&2
        _deny 'This commit message contains a "Co-Authored-By:" trailer (AI attribution). The coauthor guard is enabled, which forbids AI attribution in commit history. Remove the Co-Authored-By line from the commit message and commit again. (Disable: SUPERCHARGER_COAUTHOR_GUARD=0, or rm ~/.claude/supercharger/scope/.coauthor-guard)'
      fi
    ;; esac
  fi
fi

# ─── Check 2: Conventional Commit format (opt-in via .conventional-commits) ──
if [ -f "$SUPERCHARGER_STATE/.conventional-commits" ] && ! check_hook_disabled "commit-check"; then
  # shellcheck source=hooks/cmd-normalize.sh
  source "$HOOKS_DIR/cmd-normalize.sh"
  _CC_CMD=$(normalize_cmd "$CMD")

  # Find the first `git commit` segment (handles `safe && git commit ...`).
  _CC_SEGS=$(split_segments "$_CC_CMD"); [ -z "$_CC_SEGS" ] && _CC_SEGS="$_CC_CMD"
  _CC_SEG=""
  while IFS= read -r _seg; do
    if printf '%s\n' "$_seg" | grep -qE '^git commit([[:space:]]|$)'; then _CC_SEG="$_seg"; break; fi
  done <<< "$_CC_SEGS"

  # Only validate when we found a real commit segment that isn't --amend.
  if [ -n "$_CC_SEG" ] && ! printf '%s\n' "$_CC_SEG" | grep -qE '(^|[[:space:]])--amend([[:space:]]|$)'; then
    # Heredoc segments are truncated by the line-based iterator — fall back to the full command.
    if printf '%s\n' "$_CC_SEG" | grep -qE '<<-?'"'"'?EOF'"'"'?'; then _CC_TARGET="$CMD"; else _CC_TARGET="$_CC_SEG"; fi
    MSG=$(COMMIT_CMD="$_CC_TARGET" python3 -c "
import os, re
cmd = os.environ['COMMIT_CMD']
heredoc = re.search(r\"<<'?EOF'?\s*\n(.+?)\nEOF\b\", cmd, re.DOTALL)
if heredoc:
    lines = [l.strip() for l in heredoc.group(1).splitlines() if l.strip()]
    print(lines[0] if lines else '')
else:
    m = re.search(r\"-m\s+[\\\"'](.+?)[\\\"']\", cmd)
    print(m.group(1) if m else '')
" 2>/dev/null || echo "")
    if [ -n "$MSG" ] && ! printf '%s\n' "$MSG" | grep -qE '^Merge '; then
      _CC_TYPES="feat|fix|chore|docs|style|refactor|test|perf|ci|build|revert"
      if ! printf '%s\n' "$MSG" | grep -qE "^(${_CC_TYPES})(\([^)]+\))?!?: .+"; then
        echo "" >&2
        echo "Supercharger blocked this commit (conventional-commit format)." >&2
        echo "  Command: $CMD" >&2
        _deny "commit message does not follow conventional commit format.
  Expected : type(scope): description  or  type: description  or  type!: description (breaking)
  Valid types: feat, fix, chore, docs, style, refactor, test, perf, ci, build, revert
  Examples  : feat(auth): add OAuth support
              fix: resolve null pointer in parser
              feat!: drop Node 16 support (breaking change)"
      fi
    fi
  fi
fi

# ─── Check 2b: committing straight onto the default branch (default ON) ──────
#
# The rule exists in prose and had no mechanism: guardrails.md and Claude Code's
# own instructions both say to branch first, and nothing enforced it. Measured
# before this: `git commit -m "wip"` on master was allowed by all 160 hooks.
# A rule stated in a description with no mechanism is the highest-yield hook
# candidate this project has found (see the coverage-diff research notes).
#
# ASK, never deny, and only when actually ON the default branch — so it is silent
# in the normal case of working on a feature branch. Measured across three local
# repos: two were on feature branches (silent), one was on master. That one is
# THIS repo, which is trunk-based on purpose, so the escape hatch is not
# theoretical — `"allowDefaultBranchCommits": true` in .supercharger.json turns it
# off for projects that commit to the trunk deliberately.
#
# Asks once per session per repo: a release cuts several commits in a row, and
# re-asking each time is how a guard gets switched off.
#
# The fork is paid ONLY here, after the `git commit` gate has already matched,
# so ordinary Bash calls are untouched.
if [ "${SUPERCHARGER_DEFAULT_BRANCH_GUARD:-1}" != "0" ] \
   && ! check_hook_disabled "commit-default-branch"; then
  _db_allow=false
  case "$CMD" in *"git commit --help"*|*"git commit -h"*) _db_allow=true ;; esac
  if [ -f "$PROJECT_DIR/.supercharger.json" ] \
     && grep -q '"allowDefaultBranchCommits"[[:space:]]*:[[:space:]]*true' "$PROJECT_DIR/.supercharger.json" 2>/dev/null; then
    _db_allow=true
  fi
  if [ "$_db_allow" = false ]; then
    _DB_BRANCH=$( (cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null) || true )
    # The default branch as the REMOTE reports it, falling back to the common
    # names. Never guess from the current branch — that would make every branch
    # its own default and the check vacuous.
    _DB_DEFAULT=$( (cd "$PROJECT_DIR" 2>/dev/null && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true )
    if [ -z "$_DB_DEFAULT" ]; then
      case "$_DB_BRANCH" in main|master) _DB_DEFAULT="$_DB_BRANCH" ;; esac
    fi
    if [ -n "$_DB_BRANCH" ] && [ -n "$_DB_DEFAULT" ] && [ "$_DB_BRANCH" = "$_DB_DEFAULT" ]; then
      _DB_KEY=$(printf '%s' "$PROJECT_DIR" | tr -c 'A-Za-z0-9' '-' | tail -c 60)
      _DB_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
      _DB_ACK="$SUPERCHARGER_STATE/scope/.default-branch-ack-${_DB_SID:-nosession}${_DB_KEY}"
      if [ ! -f "$_DB_ACK" ]; then
        mkdir -p "$SUPERCHARGER_STATE/scope" 2>/dev/null || true
        : > "$_DB_ACK" 2>/dev/null || true
        _RSN=$(printf 'This commit lands directly on %s, the default branch. If that is deliberate — a trunk-based repo, or a release commit — go ahead; this asks once per session per repo. Otherwise branch first: git switch -c <name>. Silence for this project: add "allowDefaultBranchCommits": true to .supercharger.json. Disable everywhere: SUPERCHARGER_DEFAULT_BRANCH_GUARD=0' "$_DB_BRANCH" \
          | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
        if [ -n "$_RSN" ]; then
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$_RSN"
          exit 0
        fi
      fi
    fi
  fi
fi

# ─── Check 3: secret in the staged diff (default ON) ─────────────────────────
if [ "${SUPERCHARGER_COMMIT_SECRET_GUARD:-1}" != "0" ]; then
  ( [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] && cd "$PROJECT_DIR" 2>/dev/null || exit 0
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    DIFF=$(git diff --cached --unified=0 --no-color 2>/dev/null || true)
    [ -z "$DIFF" ] && exit 0
    ADDED=$(printf '%s\n' "$DIFF" | awk '/^\+\+\+ /{next} /^\+/{sub(/^\+/,""); print}')
    [ -z "$ADDED" ] && exit 0
    # shellcheck source=hooks/lib-secret-patterns.sh
    . "$HOOKS_DIR/lib-secret-patterns.sh"
    _CP=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")
    printf '%s\n' "$ADDED" | LC_ALL=C grep -qE "$_CP" && exit 42
    exit 0 )
  if [ "$?" -eq 42 ]; then
    echo "[Supercharger] commit-secret-guard: SECRET in staged diff — blocking commit" >&2
    BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"; mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
    printf '[%s] secret in staged commit — blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
    SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"
    echo "secrets" > "$SUPERCHARGER_STATE/scope/.scan-alert-${SID}" 2>/dev/null || true
    _deny 'The staged changes introduce a value matching a known secret/credential format (API key, token, private key, or wallet key). Blocking this commit to prevent leaking it into git history. Remove the secret from the staged files (use an env var or a secrets manager), re-stage, and commit again. If this is a false positive, run the commit yourself in the terminal.'
  fi
fi

# ─── Check 4: code-vulnerability patterns in the staged diff (default ON) ─────
# The write-time code-security-scanner only sees each single Write/Edit Claude
# makes; it misses vulns that emerge across several edits, in human edits, or in
# code that predates the hook. This is the commit-boundary backstop, reusing the
# SAME patterns (lib_code_patterns.py) so the two enforcement points can't drift.
# ASKS (not deny) — like the write-time scanner it may be intentional in a test or
# security tool. Disable: SUPERCHARGER_COMMIT_CODE_SCAN=0.
if [ "${SUPERCHARGER_COMMIT_CODE_SCAN:-1}" != "0" ]; then
  _CV_TMP=$(mktemp 2>/dev/null) || _CV_TMP="${TMPDIR:-/tmp}/commit-codescan.$$"
  ( [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] && cd "$PROJECT_DIR" 2>/dev/null || exit 0
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    DIFF=$(git diff --cached --unified=0 --no-color 2>/dev/null || true)
    [ -z "$DIFF" ] && exit 0
    ADDED=$(printf '%s\n' "$DIFF" | awk '/^\+\+\+ /{next} /^\+/{sub(/^\+/,""); print}')
    [ -z "$ADDED" ] && exit 0
    ADDED_CODE="$ADDED" HOOKS_DIR="$HOOKS_DIR" python3 > "$_CV_TMP" 2>/dev/null <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ.get('HOOKS_DIR', ''))
try:
    import lib_code_patterns
except Exception:
    sys.exit(0)
hits = lib_code_patterns.scan_content(os.environ.get('ADDED_CODE', ''))
if hits:
    print(' | '.join(hits[:3]))
PYEOF
  )
  _CV=$(cat "$_CV_TMP" 2>/dev/null); rm -f "$_CV_TMP" 2>/dev/null
  if [ -n "$_CV" ]; then
    SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"
    mkdir -p "$SUPERCHARGER_STATE/scope" 2>/dev/null || true
    echo "code" > "$SUPERCHARGER_STATE/scope/.scan-alert-${SID}" 2>/dev/null || true
    echo "[Supercharger] commit-guard: code-vuln pattern in staged diff — ask" >&2
    _MSG="The staged changes introduce potentially insecure code pattern(s): ${_CV}. These may be intentional (test fixtures, a security tool) — if so, confirm and commit. Otherwise review before it lands in git history. (Disable: SUPERCHARGER_COMMIT_CODE_SCAN=0)"
    RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
    exit 0
  fi
fi

exit 0
