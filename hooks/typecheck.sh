#!/usr/bin/env bash
# Claude Supercharger — TypeScript Type Check Hook
# Event: PostToolUse | Matcher: Write,Edit
# Runs tsc --noEmit after editing .ts/.tsx files. Injects errors into context.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

INPUT=$(cat)
FILE_PATH=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except: print('')
" 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

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

[ -z "$ERRORS" ] && exit 0

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
