#!/usr/bin/env bash
# Claude Supercharger — Session Complete Hook
# Event: Stop | Matcher: (none)
# Logs session metadata on exit. Sends webhook if configured.

set -eo pipefail

SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"

mkdir -p "$SUMMARIES_DIR" 2>/dev/null || true

# Capture session metadata
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -10 || echo "")

# Write session-end marker to summaries dir
MARKER_FILE="$SUMMARIES_DIR/.last-session"
{
  echo "timestamp: $TIMESTAMP"
  echo "project: $PROJECT"
  echo "branch: $BRANCH"
  echo "modified_files:"
  if [ -n "$MODIFIED" ]; then
    echo "$MODIFIED" | while read -r f; do echo "  - $f"; done
  else
    echo "  (none detected)"
  fi
} > "$MARKER_FILE" 2>/dev/null || true

# Send webhook notification if configured — uses shared webhook lib
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  if webhook_enabled; then
    send_webhook "Claude Code session complete" || true
  fi
fi

exit 0
