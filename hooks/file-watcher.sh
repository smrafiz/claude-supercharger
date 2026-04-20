#!/usr/bin/env bash
# Claude Supercharger — File Change Watcher
# Event: FileChanged | Matcher: .env,.envrc,package.json,.claude/settings.json
# Notifies Claude when watched files change so it doesn't act on stale assumptions.

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('file_path') or d.get('path') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
  .env|.envrc)
    MSG="[FILE CHANGED] '${FILE_PATH}' was modified externally. Environment variables may have changed — reload the env before running commands that depend on them."
    ;;
  package.json)
    MSG="[FILE CHANGED] 'package.json' was modified externally. Run the appropriate install command (npm/yarn/pnpm install) if dependencies changed."
    ;;
  settings.json)
    MSG="[FILE CHANGED] '.claude/settings.json' was modified externally. Hook configuration may have changed — treat this with caution (CVE-2025-59536)."
    ;;
  *)
    MSG="[FILE CHANGED] '${FILE_PATH}' was modified externally."
    ;;
esac

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")

printf '{"hookSpecificOutput":{"hookEventName":"FileChanged","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] file-watcher: ${BASENAME} changed" >&2
exit 0
