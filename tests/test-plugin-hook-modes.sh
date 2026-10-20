#!/usr/bin/env bash
# The plugin runs each hooks/hooks.json command directly, and the plugin cache keeps
# git's file mode. A hook committed 644 never runs there: Claude Code reports
# "Permission denied" as a non-blocking error and the call goes ahead unguarded.
# Eight guards shipped that way from 2026-07-19 to 2026-10-19; the installer hid it
# by running chmod on its own copies.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Plugin hook file modes ==="

begin_test "plugin: every script hooks.json runs is committed executable"
bad=""
for f in $(grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' "$REPO_DIR/hooks/hooks.json" | sort -u); do
  m=$(git -C "$REPO_DIR" ls-files -s "$f" | cut -c1-6)
  [ "$m" = 100755 ] || bad="$bad $f($m)"
done
[ -z "$bad" ] && pass || fail "not 100755:$bad"

report
