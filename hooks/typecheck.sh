#!/usr/bin/env bash
# Claude Supercharger — TypeScript Type Check Hook
# Event: PostToolUse | Matcher: Write,Edit
# Runs tsc --noEmit after editing .ts/.tsx files. Injects errors into context.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
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
    echo ""
  fi
}

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ_HASH=$(echo -n "$PROJECT_ROOT" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])" 2>/dev/null || echo "default")
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

# Timeout: prefer gtimeout (macOS coreutils), then timeout
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout 30"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout 30"
else
  TIMEOUT_CMD=""
fi

# Run type check
ERRORS=$(cd "$PROJECT_ROOT" && $TIMEOUT_CMD $TSC --noEmit --pretty false 2>&1 | grep -v '^$' | head -20 || true)

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
ERROR_COUNT=$(printf '%s\n' "$ERRORS" | grep -c ' error TS' 2>/dev/null || echo "?")

# Compact output for context injection
COMPACT=$(printf '%s\n' "$ERRORS" | grep ' error TS' | head -8 | sed 's|'"$PROJECT_ROOT/"'||g' | tr '\n' '|' | sed 's/|$//')

MSG="[TSC] ${ERROR_COUNT} type error(s) after editing $(basename "$FILE_PATH"): ${COMPACT}"

echo "$MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"

exit 0
