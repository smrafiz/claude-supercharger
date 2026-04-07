#!/usr/bin/env bash
# Claude Supercharger — Session Start Update Check
# Event: SessionStart | Matcher: (none)
# Checks for updates once per day and prints a banner if one is available.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
VERSION_FILE="$SUPERCHARGER_DIR/.version"
CACHE_FILE="$SUPERCHARGER_DIR/.update-cache"
CACHE_TTL=86400  # 24 hours

# Skip if no installed version stamp (pre-1.7.4 installs)
[ -f "$VERSION_FILE" ] || exit 0

LOCAL=$(cat "$VERSION_FILE")

# Use cached result if fresh
if [ -f "$CACHE_FILE" ]; then
  CACHE_MTIME=$(stat -f "%m" "$CACHE_FILE" 2>/dev/null || stat -c "%Y" "$CACHE_FILE" 2>/dev/null || echo 0)
  CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
  if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
    REMOTE=$(cat "$CACHE_FILE")
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ]; then
      echo "╔══════════════════════════════════════════════╗" >&2
      echo "║  Supercharger update: v${LOCAL} → v${REMOTE}" >&2
      echo "║  Run: bash ~/.claude/supercharger/tools/update.sh" >&2
      echo "╚══════════════════════════════════════════════╝" >&2
    fi
    exit 0
  fi
fi

# Fetch remote version and cache it (background, non-blocking)
{
  REMOTE=$(python3 -c "
import urllib.request, json, base64
try:
    url = 'https://api.github.com/repos/smrafiz/claude-supercharger/contents/lib/utils.sh'
    req = urllib.request.Request(url, headers={'User-Agent': 'claude-supercharger'})
    with urllib.request.urlopen(req, timeout=4) as r:
        data = json.load(r)
    content = base64.b64decode(data['content']).decode()
    for line in content.splitlines():
        if line.startswith('VERSION='):
            print(line.split('=')[1].strip('\"'))
            break
except Exception:
    print('')
" 2>/dev/null)

  [ -n "$REMOTE" ] && echo "$REMOTE" > "$CACHE_FILE"

  if [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ]; then
    echo "╔══════════════════════════════════════════════╗" >&2
    echo "║  Supercharger update: v${LOCAL} → v${REMOTE}" >&2
    echo "║  Run: bash ~/.claude/supercharger/tools/update.sh" >&2
    echo "╚══════════════════════════════════════════════╝" >&2
  fi
} &

exit 0
