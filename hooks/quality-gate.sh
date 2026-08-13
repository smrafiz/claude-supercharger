#!/usr/bin/env bash
# Claude Supercharger — Quality Gate Hook (3-stage pipeline)
# Event: PostToolUse | Matcher: Write,Edit
# Stage 1: Run linter → Stage 2: Auto-fix → Stage 3: Re-check
# Replaces auto-format.sh with a more comprehensive quality gate.

set -euo pipefail

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
fi

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-hash.sh
. "$HOOKS_DIR/lib-hash.sh" 2>/dev/null || true
# shellcheck source=hooks/lib-bounded-run.sh
. "$HOOKS_DIR/lib-bounded-run.sh"
init_hook_suppress "$PROJECT_ROOT"
check_hook_disabled "quality-gate" && exit 0
hook_profile_skip "quality-gate" && exit 0

# Hash-cache: skip lint if file unchanged since last clean run
_qg_hash() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    # Git Bash has NEITHER, and an empty key never matches, so the lint cache was
    # silently off for the whole platform. See _typecheck_hash for the same fix.
    python3 -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1" 2>/dev/null || echo ""
  fi
}

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR"
# CR strip: Windows python print() ends lines with CRLF and $(...) removes
# only the newline, so this hash carried a carriage return into the CACHE
# FILENAME below. CR is illegal in a Windows filename, the write failed, and
# the cache never hit — tsc and lint re-ran on every single write, platform
# wide, with nothing reporting it. A digest cannot legitimately contain a CR.
QG_PROJ_HASH=$(echo -n "$PROJECT_ROOT" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])" 2>/dev/null || echo "default")
QG_PROJ_HASH=${QG_PROJ_HASH//$'\r'/}
QG_CACHE="$SCOPE_DIR/.quality-gate-cache-${QG_PROJ_HASH}"
QG_FILE_HASH=$(_qg_hash "$FILE_PATH")

if [ -n "$QG_FILE_HASH" ] && [ -f "$QG_CACHE" ]; then
  QG_CACHED=$(QG_CACHE="$QG_CACHE" FILE_PATH="$FILE_PATH" python3 -c "
import json, os
try:
  with open(os.environ['QG_CACHE']) as f:
    d = json.load(f)
  print(d.get(os.environ['FILE_PATH'], ''))
except Exception:
  print('')
" 2>/dev/null || echo "")
  if [ "$QG_CACHED" = "$QG_FILE_HASH" ]; then
    exit 0  # cache hit — file unchanged, skip lint
  fi
fi

EXT="${FILE_PATH##*.}"
MAX_ITERATIONS=2
ITERATION=0
HAD_ISSUES=false

# Bound every linter/formatter run. The old `else TIMEOUT_CMD=""` branch made
# this wrapper a no-op on any host without GNU coreutils — macOS and Git Bash,
# i.e. two of the three platforms — so eslint/prettier/ruff ran unbounded and a
# hung toolchain took this blocking hook to its 15s harness timeout. Resolution
# (real binary vs shell fallback) now lives in the lib; see lib-bounded-run.sh.
TIMEOUT_CMD="sc_bounded_run ${SUPERCHARGER_LINT_BUDGET_S:-30}"

lint_and_fix() {
  local file="$1"
  local issues=""

  case "$EXT" in
    py)
      # Stage 1: Lint
      if command -v ruff &>/dev/null; then
        issues=$($TIMEOUT_CMD ruff check "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          $TIMEOUT_CMD ruff check --fix "$file" 2>/dev/null || true
          # Also format
          $TIMEOUT_CMD ruff format "$file" 2>/dev/null || true
          return 0
        fi
        $TIMEOUT_CMD ruff format "$file" 2>/dev/null || true
      elif command -v black &>/dev/null; then
        $TIMEOUT_CMD black -q "$file" 2>/dev/null || true
      fi
      ;;
    js|jsx|ts|tsx|mjs|cjs)
      # Stage 1: Lint
      if command -v eslint &>/dev/null && { ls "$PROJECT_ROOT"/.eslintrc* &>/dev/null 2>&1 || ls "$PROJECT_ROOT"/eslint.config* &>/dev/null 2>&1; }; then
        issues=$($TIMEOUT_CMD eslint "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          $TIMEOUT_CMD eslint --fix "$file" 2>/dev/null || true
        fi
      fi
      # Format
      if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        if command -v npx &>/dev/null; then
          $TIMEOUT_CMD npx --no-install prettier --write "$file" 2>/dev/null || true
        fi
      fi
      ;;
    rs)
      if command -v rustfmt &>/dev/null; then
        $TIMEOUT_CMD rustfmt "$file" 2>/dev/null || true
      fi
      ;;
    go)
      if command -v gofmt &>/dev/null; then
        $TIMEOUT_CMD gofmt -w "$file" 2>/dev/null || true
      fi
      if command -v golangci-lint &>/dev/null; then
        issues=$($TIMEOUT_CMD golangci-lint run "$file" 2>&1) || true
        [ -n "$issues" ] && HAD_ISSUES=true
      fi
      ;;
    *)
      # No linter for this file type
      return 0
      ;;
  esac

  return 0
}

PREV_ISSUES=""
while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  HAD_ISSUES=false
  lint_and_fix "$FILE_PATH"

  if ! $HAD_ISSUES; then
    break
  fi

  # Compare with previous iteration — break if issues unchanged (fix can't resolve them)
  CURRENT_HASH=$(sc_md5 < "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" = "$PREV_ISSUES" ]; then
    break
  fi
  PREV_ISSUES="$CURRENT_HASH"

  ITERATION=$((ITERATION + 1))
done

# Re-hash after potential auto-fix modifications
QG_PRE_HASH="$QG_FILE_HASH"
QG_FILE_HASH=$(_qg_hash "$FILE_PATH")

# Skip the re-check when nothing could have changed the answer.
#
# The re-check below is a SECOND full linter invocation, and on the common path —
# a file that was already clean — it re-derives a verdict the loop just computed.
# Each one is a cold node/interpreter start, and this hook runs on every Write and
# Edit: measured on a real install at 1423 runs, 1.77s median, 53 minutes over 30
# days. Roughly half of that is this duplicate.
#
# Two conditions must BOTH hold to skip, because either alone is not enough:
#   - the loop found no issues, so there is nothing that a fix could have left over
#   - the file is byte-identical, so the formatter did not rewrite it after the
#     lint (prettier can reformat a clean file, and in principle change what a
#     linter says about it)
# If the hash is unavailable for any reason, the condition is false and the
# re-check runs — this may only ever skip work that is provably redundant.
QG_SKIP_RECHECK=false
if ! $HAD_ISSUES && [ -n "$QG_FILE_HASH" ] && [ "$QG_FILE_HASH" = "$QG_PRE_HASH" ]; then
  QG_SKIP_RECHECK=true
fi

# Final re-check: inject any remaining unfixed issues as systemMessage
REMAINING=""
if ! $QG_SKIP_RECHECK; then
  case "$EXT" in
    py)
      if command -v ruff &>/dev/null; then
        REMAINING=$($TIMEOUT_CMD ruff check "$FILE_PATH" 2>&1) || true
      fi
      ;;
    js|jsx|ts|tsx|mjs|cjs)
      if command -v eslint &>/dev/null && { ls "$PROJECT_ROOT"/.eslintrc* &>/dev/null 2>&1 || ls "$PROJECT_ROOT"/eslint.config* &>/dev/null 2>&1; }; then
        REMAINING=$($TIMEOUT_CMD eslint "$FILE_PATH" 2>&1) || true
      fi
      ;;
    go)
      if command -v golangci-lint &>/dev/null; then
        REMAINING=$($TIMEOUT_CMD golangci-lint run "$FILE_PATH" 2>&1) || true
      fi
      ;;
  esac
fi

if [ -n "$REMAINING" ]; then
  TRUNCATED=$(printf '%.1500s' "$REMAINING")
  MSG="[QUALITY GATE] Unfixed lint issues in ${FILE_PATH} (auto-fix could not resolve):

${TRUNCATED}

Fix these issues before marking the task complete."
  # v2.7.40: lint feedback is for Claude to fix → hookSpecificOutput.additionalContext
  # (PostToolUse), not systemMessage (which only reaches the user).
  CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.stdin.read()}}))" 2>/dev/null)
  [ -n "$CONTEXT_JSON" ] && printf '%s\n' "$CONTEXT_JSON"
fi

# Write cache on clean exit (no remaining issues after pipeline)
if [ -z "$REMAINING" ] && [ -n "${QG_FILE_HASH:-}" ]; then
  QG_CACHE="$QG_CACHE" FILE_PATH="$FILE_PATH" QG_FILE_HASH="$QG_FILE_HASH" python3 -c "
import json, os
cache_file = os.environ['QG_CACHE']
file_path = os.environ['FILE_PATH']
file_hash = os.environ['QG_FILE_HASH']
try:
  with open(cache_file) as f:
    d = json.load(f)
except Exception:
  d = {}
d[file_path] = file_hash
d = {k: v for k, v in d.items() if os.path.exists(k)}
import tempfile
with tempfile.NamedTemporaryFile('w', dir=os.path.dirname(cache_file), delete=False, suffix='.tmp') as tf:
  json.dump(d, tf)
  tf.flush()
  os.fsync(tf.fileno())
os.replace(tf.name, cache_file)
" 2>/dev/null || true
fi

exit 0
