#!/usr/bin/env bash
# Claude Supercharger — Stop Verification
# Event: Stop | Matcher: *
# Merged from verify-on-stop.sh + project-verify.sh
# 1. Warns if files were modified but no test/build ran (advisory)
# 2. Runs .claude/verify.sh if present and injects failures into context
#
# The verdict is memoized against the tree that produced it, so an unchanged
# tree is not re-verified every turn (a PASS is skipped; a FAIL is re-emitted).
# Disable the memo: SUPERCHARGER_VERIFY_MEMO=0
# Budget for the verify script: SUPERCHARGER_VERIFY_BUDGET_S=<seconds> (default 10)

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

AUDIT_DIR="$SUPERCHARGER_STATE/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

# ── Part 1: verify-on-stop (advisory, stderr only) ──

# Detect test command from project
detect_test_cmd() {
  local dir="${1:-.}"
  if [ -f "$dir/package.json" ]; then
    # Check for test script in package.json
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); exit(0 if 'test' in d.get('scripts',{}) else 1)" "$dir/package.json" 2>/dev/null; then
      # Detect package manager
      if [ -f "$dir/pnpm-lock.yaml" ]; then echo "pnpm test"
      elif [ -f "$dir/bun.lockb" ]; then echo "bun test"
      elif [ -f "$dir/yarn.lock" ]; then echo "yarn test"
      else echo "npm test"
      fi
      return
    fi
  fi
  if [ -f "$dir/pytest.ini" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.cfg" ]; then
    echo "pytest"
    return
  fi
  if [ -f "$dir/Cargo.toml" ]; then
    echo "cargo test"
    return
  fi
  if [ -f "$dir/go.mod" ]; then
    echo "go test ./..."
    return
  fi
  echo ""
}

PROJECT_DIR="${PWD}"
TEST_CMD=$(detect_test_cmd "$PROJECT_DIR")

if [ -f "$AUDIT_FILE" ]; then
  HAS_WRITES=false
  grep -q '"Write"\|"Edit"' "$AUDIT_FILE" 2>/dev/null && HAS_WRITES=true

  if $HAS_WRITES; then
    HAS_TEST=false
    grep -qiE '(npm test|yarn test|pnpm test|cargo test|pytest|go test|jest|vitest|mocha|npm run test|npm run build|cargo build|go build|make test|make build)' "$AUDIT_FILE" 2>/dev/null && HAS_TEST=true

    if ! $HAS_TEST; then
      echo "" >&2
      echo "[Supercharger] ⚠ Files modified but no test/build command detected this session." >&2
      if [ -n "$TEST_CMD" ]; then
        echo "  Try: ${TEST_CMD}" >&2
      else
        echo "  Consider running tests before finishing." >&2
      fi
      echo "" >&2
    fi
  fi
fi

# ── Part 2: project-verify (blocks Claude on failure) ──
VERIFY_SCRIPT=""
[ -f ".claude/verify.sh" ] && VERIFY_SCRIPT=".claude/verify.sh"
[ -z "$VERIFY_SCRIPT" ] && [ -f "$PWD/.claude/verify.sh" ] && VERIFY_SCRIPT="$PWD/.claude/verify.sh"

[ -z "$VERIFY_SCRIPT" ] && exit 0

# Skip if no file changes this session
CHANGED=$(git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
if [ -z "$CHANGED" ]; then
  echo "[Supercharger] stop-verify: skipped (no file changes)" >&2
  exit 0
fi

# ── Memoize the verdict by tree content ──────────────────────────────────────
# The clean-tree skip above is the only gate, and it stops applying the moment a
# work session touches anything: from then on EVERY turn end re-runs the whole
# verify script, including the many turns that only read files, answer a
# question, or run a command. Measured across 30 days of real transcripts,
# stop-verify was the single most expensive hook in the install — 118 minutes
# over 3185 runs, more than double the next one — and most of those runs
# re-derived a verdict that could not have changed since the previous turn.
#
# The signature covers what the verify script actually sees: HEAD, the porcelain
# status, the full working diff, and the size/mtime of untracked files (which no
# diff includes). A pass is skipped; a FAIL is re-emitted from cache rather than
# skipped, so a failing verification keeps blocking every turn until it is fixed
# — the point of the hook survives the optimisation.
#
# Opt out with SUPERCHARGER_VERIFY_MEMO=0.
# shellcheck source=hooks/lib-hash.sh
. "${BASH_SOURCE[0]%/*}/lib-hash.sh" 2>/dev/null || true
_SV_MEMO="${SUPERCHARGER_VERIFY_MEMO:-1}"
_SV_SIG=""
_SV_CACHE=""
if [ "$_SV_MEMO" != "0" ] && command -v sc_md5 >/dev/null 2>&1; then
  _SV_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
  _SV_SIG=$( { git rev-parse HEAD 2>/dev/null || true
               git status --porcelain 2>/dev/null || true
               git diff HEAD 2>/dev/null || true
               if [ -n "$_SV_UNTRACKED" ]; then
                 printf '%s\n' "$_SV_UNTRACKED" | tr '\n' '\0' | xargs -0 ls -ld 2>/dev/null || true
               fi
             } | sc_md5 2>/dev/null | cut -c1-16)
  _SV_SIG=${_SV_SIG//$'\r'/}     # Windows python print() ends lines with CRLF
  _SV_PROJ=$(printf '%s' "$PROJECT_DIR" | sc_md5 2>/dev/null | cut -c1-12)
  _SV_PROJ=${_SV_PROJ//$'\r'/}
  [ -n "$_SV_SIG" ] && [ -n "$_SV_PROJ" ] \
    && _SV_CACHE="$SUPERCHARGER_STATE/scope/.stop-verify-$_SV_PROJ"
fi

if [ -n "$_SV_CACHE" ] && [ -f "$_SV_CACHE" ]; then
  IFS= read -r _SV_HEAD < "$_SV_CACHE" || _SV_HEAD=""
  _SV_CSIG=${_SV_HEAD%% *}
  _SV_CEXIT=${_SV_HEAD##* }
  if [ "$_SV_CSIG" = "$_SV_SIG" ]; then
    if [ "$_SV_CEXIT" = "0" ]; then
      echo "[Supercharger] stop-verify: passed (cached — nothing changed since the last run)" >&2
      exit 0
    fi
    # Still failing, and still the same tree. Re-block without re-running: the
    # answer cannot have changed, but silence here would let the failure through.
    _SV_PREV=$(tail -n +2 "$_SV_CACHE" 2>/dev/null || true)
    _SV_MSG="[PROJECT VERIFY FAILED] Verification script (.claude/verify.sh) returned exit code ${_SV_CEXIT}. Fix these before finishing:

$(printf '%.2000s' "$_SV_PREV")"
    _SV_JSON=$(printf '%s' "$_SV_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
      || printf '"%s"' "$(printf '%s' "$_SV_MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"decision":"block","reason":%s}\n' "$_SV_JSON"
    echo "[Supercharger] stop-verify: FAILED (cached, exit $_SV_CEXIT — tree unchanged)" >&2
    exit 0
  fi
fi

# Bounded, because this hook has 15s before Claude Code kills it and a project's
# verify.sh is usually a test suite. Measured on a real install: 18 Stop timeouts
# in 30 days, each burning the full 15s and producing NOTHING — the script never
# finished, no verdict was reached, and the {"decision":"block"} below never
# printed, so a FAILING verification did not block completion. Strictly worse
# than not running: the cost of the check without the check.
#
# The budget is deliberately under the registered timeout so the overrun is OURS
# to report rather than an external kill we cannot see. `timeout` is not present
# on macOS (nor gtimeout without coreutils), so this backgrounds the script and
# polls — no dependency on a binary that may not exist.
_VERIFY_BUDGET="${SUPERCHARGER_VERIFY_BUDGET_S:-10}"
VERIFY_OUTPUT=""
VERIFY_EXIT=0
_VOUT=$(mktemp) || _VOUT=""
if [ -z "$_VOUT" ]; then
  echo "[Supercharger] stop-verify: skipped (no temp dir)" >&2
  exit 0
fi
bash "$VERIFY_SCRIPT" >"$_VOUT" 2>&1 &
_VPID=$!
_waited=0
while kill -0 "$_VPID" 2>/dev/null && [ "$_waited" -lt "$_VERIFY_BUDGET" ]; do
  sleep 1
  _waited=$((_waited + 1))
done
if kill -0 "$_VPID" 2>/dev/null; then
  kill "$_VPID" 2>/dev/null || true
  wait "$_VPID" 2>/dev/null || true
  rm -f "$_VOUT"
  # Say so. A silent skip here is what made the old behaviour undiagnosable.
  echo "[Supercharger] stop-verify: SKIPPED — .claude/verify.sh exceeded ${_VERIFY_BUDGET}s." >&2
  echo "  It was stopped so it could not blow this hook's 15s limit. Run it yourself," >&2
  echo "  shorten it, or raise the budget: SUPERCHARGER_VERIFY_BUDGET_S=<seconds>." >&2
  exit 0
fi
wait "$_VPID" 2>/dev/null || VERIFY_EXIT=$?
VERIFY_OUTPUT=$(cat "$_VOUT" 2>/dev/null || true)
rm -f "$_VOUT"

# Record the verdict against the tree that produced it. Only a run that reached
# a verdict is cached — an overrun exits above, so a script killed at the budget
# never memoizes a "pass" it did not earn.
if [ -n "$_SV_CACHE" ]; then
  mkdir -p "$(dirname "$_SV_CACHE")" 2>/dev/null || true
  { printf '%s %s\n' "$_SV_SIG" "$VERIFY_EXIT"
    printf '%.2000s\n' "$VERIFY_OUTPUT"
  } > "$_SV_CACHE.$$.tmp" 2>/dev/null \
    && mv "$_SV_CACHE.$$.tmp" "$_SV_CACHE" 2>/dev/null \
    || rm -f "$_SV_CACHE.$$.tmp" 2>/dev/null || true
fi

if [ "$VERIFY_EXIT" -eq 0 ]; then
  echo "[Supercharger] stop-verify: passed" >&2
  exit 0
fi

TRUNCATED=$(printf '%.2000s' "$VERIFY_OUTPUT")
MSG="[PROJECT VERIFY FAILED] Verification script (.claude/verify.sh) returned exit code ${VERIFY_EXIT}. Fix these before finishing:

${TRUNCATED}"

REASON_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
# v2.7.30: BLOCK the stop via decision:"block" (+reason, shown to Claude). The
# old {"stopReason":...} only applies when continue:false — so the verify
# failure never actually blocked completion; Claude finished with it ignored.
printf '{"decision":"block","reason":%s}\n' "$REASON_JSON"

echo "[Supercharger] stop-verify: FAILED (exit $VERIFY_EXIT)" >&2
exit 0
