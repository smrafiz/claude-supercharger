#!/usr/bin/env bash
# Claude Supercharger — Design Context Injector
# Event: PreToolUse | Matcher: Write,Edit
# When editing a CSS/style file, injects DESIGN.md into context if present in project root.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)

# Extract file path being written/edited
FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Only fire for style files
case "$FILE_PATH" in
  *.css|*.scss|*.sass|*.less|*.styl|*.styled.ts|*.styled.tsx|*.styled.js|*.styles.ts|*.styles.tsx|*.styles.js|*tailwind.config*|*theme.ts|*theme.tsx|*theme.js)
    ;;
  *)
    exit 0
    ;;
esac

# Resolve project dir
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

DESIGN_FILE="$PROJECT_DIR/DESIGN.md"
[ -f "$DESIGN_FILE" ] || exit 0

# Read and inject DESIGN.md (cap at 4KB to avoid token bloat)
DESIGN_CONTENT=$(head -c 4096 "$DESIGN_FILE" 2>/dev/null || true)
[ -z "$DESIGN_CONTENT" ] && exit 0

MSG="[DESIGN] Editing style file. Active design context:\n\n${DESIGN_CONTENT}"

echo "[Supercharger] design-context: injecting DESIGN.md for $(basename "$FILE_PATH")" >&2

MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || exit 0

if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$MSG_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$MSG_JSON"
fi

exit 0
