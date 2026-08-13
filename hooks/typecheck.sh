#!/usr/bin/env bash
# Claude Supercharger — TypeScript Type Check Hook
# Event: PostToolUse | Matcher: Write,Edit
# Runs tsc --noEmit after editing .ts/.tsx files. Injects errors into context.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-bounded-run.sh
. "$HOOKS_DIR/lib-bounded-run.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
FILE_PATH=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except: print('')
" 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0
PROJECT_DIR=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "typecheck" && exit 0
hook_profile_skip "typecheck" && exit 0

# Only .ts / .tsx files
case "$FILE_PATH" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# Find tsconfig.json walking up from the file
DIR="$(dirname "$FILE_PATH")"
TSCONFIG=""
SEARCH="$DIR"
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH/tsconfig.json" ]; then
    TSCONFIG="$SEARCH/tsconfig.json"
    PROJECT_ROOT="$SEARCH"
    break
  fi
  PARENT="$(dirname "$SEARCH")"
  [ "$PARENT" = "$SEARCH" ] && break
  SEARCH="$PARENT"
done

[ -z "$TSCONFIG" ] && exit 0

# Hash-cache: skip tsc if file content unchanged since last clean run
_typecheck_hash() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    # Git Bash has NEITHER. Returning "" here meant the cache key was empty, so
    # it never matched and tsc re-ran on every single write — the cache was
    # silently off for the whole platform. python3 is already a hard install
    # requirement, so this adds no dependency (same reasoning as lib-hash.sh).
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
PROJ_HASH=$(echo -n "$PROJECT_ROOT" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])" 2>/dev/null || echo "default")
PROJ_HASH=${PROJ_HASH//$'\r'/}
TC_CACHE="$SCOPE_DIR/.typecheck-cache-${PROJ_HASH}"

FILE_HASH=$(_typecheck_hash "$FILE_PATH")
if [ -n "$FILE_HASH" ] && [ -f "$TC_CACHE" ]; then
  CACHED_HASH=$(TC_CACHE="$TC_CACHE" FILE_PATH="$FILE_PATH" python3 -c "
import json, os
try:
  with open(os.environ['TC_CACHE']) as f:
    d = json.load(f)
  print(d.get(os.environ['FILE_PATH'], ''))
except Exception:
  print('')
" 2>/dev/null || echo "")
  if [ "$CACHED_HASH" = "$FILE_HASH" ]; then
    exit 0  # cache hit — file unchanged, skip tsc
  fi
fi

# Per-project opt-out
[ -f "$PROJECT_ROOT/.supercharger-no-typecheck" ] && exit 0

# Resolve tsc binary
TSC=""
for candidate in \
  "$PROJECT_ROOT/node_modules/.bin/tsc" \
  "$(npm root 2>/dev/null)/.bin/tsc" \
  "$(command -v tsc 2>/dev/null || echo "")"; do
  [ -x "$candidate" ] && TSC="$candidate" && break
done

if [ -z "$TSC" ]; then
  # Try npx as last resort
  command -v npx &>/dev/null || exit 0
  TSC="npx --no-install tsc"
fi

# Bound the tsc run. This used to fall back to an EMPTY prefix wherever GNU
# coreutils is absent — macOS and Git Bash both — so the 30s cap the source
# advertises did not exist on the platform this is developed on. See
# lib-bounded-run.sh; the hook is asyncRewake, but an unbounded tsc still holds
# a slot until the harness's 120s async limit.
TIMEOUT_CMD="sc_bounded_run ${SUPERCHARGER_TSC_BUDGET_S:-30}"

# Run type check (timed — feeds the slow-typecheck nudge below)
_TC_T0=$(date +%s 2>/dev/null || echo 0)
ERRORS=$(cd "$PROJECT_ROOT" && $TIMEOUT_CMD $TSC --noEmit --pretty false 2>&1 | grep -v '^$' | head -20 || true)
_TC_T1=$(date +%s 2>/dev/null || echo 0)

# v2.20.1: slow-typecheck discoverability nudge. tsc on a large repo is the one real
# per-edit cost, and the opt-out already exists but is undiscoverable — so a user on a
# big monorepo just feels "Supercharger is slow" and may uninstall. If tsc ran slow HERE,
# tell them ONCE per repo (stderr only → zero context tokens, never blocks) where the
# off-switch is. Threshold: SUPERCHARGER_TYPECHECK_SLOW_S (default 3s).
_TC_ELAPSED=$(( ${_TC_T1:-0} - ${_TC_T0:-0} ))
if [ "$_TC_ELAPSED" -ge "${SUPERCHARGER_TYPECHECK_SLOW_S:-3}" ] 2>/dev/null; then
  _TC_NUDGE="$SCOPE_DIR/.typecheck-slow-nudge-${PROJ_HASH}"
  if [ ! -f "$_TC_NUDGE" ]; then
    touch "$_TC_NUDGE" 2>/dev/null || true
    echo "[Supercharger] typecheck ran ${_TC_ELAPSED}s on this repo. To skip it here: create '.supercharger-no-typecheck' in the repo root (or use /profile minimal). Shown once per repo." >&2
  fi
fi

if [ -z "$ERRORS" ]; then
  # Update cache: file was clean, store hash for next run
  if [ -n "${FILE_HASH:-}" ]; then
    TC_CACHE="$TC_CACHE" FILE_PATH="$FILE_PATH" FILE_HASH="$FILE_HASH" python3 -c "
import json, os
cache_file = os.environ['TC_CACHE']
file_path = os.environ['FILE_PATH']
file_hash = os.environ['FILE_HASH']
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
fi

# Count error lines
# v2.6.42: awk emits exactly one number; `grep -c | || echo ?` interpolated
# "0\n0" into the user-facing message on zero matches.
ERROR_COUNT=$(printf '%s\n' "$ERRORS" | awk '/ error TS/{c++} END{print c+0}')

# Compact output for context injection
COMPACT=$(printf '%s\n' "$ERRORS" | grep ' error TS' | head -8 | sed 's|'"$PROJECT_ROOT/"'||g' | tr '\n' '|' | sed 's/|$//')

MSG="[TSC] ${ERROR_COUNT} type error(s) after editing $(basename "$FILE_PATH"): ${COMPACT}"

echo "$MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

# v2.7.30: header intent is "inject errors into context" — systemMessage only
# reaches the USER, so Claude never saw the tsc errors it's meant to fix. Use
# hookSpecificOutput.additionalContext (supported on PostToolUse) to reach Claude.
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
