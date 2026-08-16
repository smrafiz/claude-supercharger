#!/usr/bin/env bash
# Claude Supercharger — Session Start Update Check
# Event: SessionStart | Matcher: (none)
# Checks for updates once per day and prints a banner if one is available.

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

# Opt out of the once-daily version check (the only network call Supercharger
# makes). Set SUPERCHARGER_NO_UPDATE_CHECK=1 to disable entirely.
[ "${SUPERCHARGER_NO_UPDATE_CHECK:-0}" = "1" ] && exit 0

# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
VERSION_FILE="$SUPERCHARGER_DIR/.version"
CACHE_FILE="$SUPERCHARGER_DIR/.update-cache"
CACHE_TTL=86400  # 24 hours

# Skip if no installed version stamp (pre-1.7.4 installs)
[ -f "$VERSION_FILE" ] || exit 0

LOCAL=$(cat "$VERSION_FILE")

# Is $1 strictly newer than $2, comparing numerically field by field? A plain
# `!=` was used here, and it announced an "update" whenever the two strings
# merely DIFFERED — including when the local install was NEWER. That is not a
# corner case: the cache below holds the last-seen remote version for 24 hours,
# so after any successful update the notice pointed BACKWARDS at the version the
# user had just left, for the rest of the day. A notifier that cries wolf gets
# ignored, which is how an install ends up twenty releases behind.
_sc_newer_than() {
  [ "$1" = "$2" ] && return 1
  _a="$1"; _b="$2"
  while [ -n "$_a$_b" ]; do
    _x="${_a%%.*}"; _y="${_b%%.*}"
    case "$_x" in ''|*[!0-9]*) _x=0 ;; esac
    case "$_y" in ''|*[!0-9]*) _y=0 ;; esac
    [ "$_x" -gt "$_y" ] && return 0
    [ "$_x" -lt "$_y" ] && return 1
    case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
    case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
  done
  return 1
}

# Use cached result if fresh
if [ -f "$CACHE_FILE" ]; then
  # v2.6.78: GNU-first stat order with numeric guard. Linux `stat -f` returns
  # filesystem stats (mountpoint string "File: ..."), which polluted CACHE_MTIME
  # and tripped set -u on "File" — same Linux-portability fix as scope-guard
  # in v2.6.73.
  CACHE_MTIME=$(stat -c "%Y" "$CACHE_FILE" 2>/dev/null || stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo "")
  case "$CACHE_MTIME" in ''|*[!0-9]*) CACHE_MTIME=0 ;; esac
  CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
  if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
    REMOTE=$(cat "$CACHE_FILE")
    if [ -n "$REMOTE" ] && _sc_newer_than "$REMOTE" "$LOCAL"; then
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

  if [ -n "$REMOTE" ] && _sc_newer_than "$REMOTE" "$LOCAL"; then
    echo "╔══════════════════════════════════════════════╗" >&2
    echo "║  Supercharger update: v${LOCAL} → v${REMOTE}" >&2
    echo "║  Run: bash ~/.claude/supercharger/tools/update.sh" >&2
    echo "╚══════════════════════════════════════════════╝" >&2
  fi
} &

exit 0
