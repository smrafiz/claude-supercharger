#!/usr/bin/env bash
# Claude Supercharger — Cache Clear Tool
# Clears typecheck and quality-gate hash caches.
# Usage: bash tools/cache-clear.sh [--dry-run]

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
DRY_RUN=0

for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=1
done

if [ ! -d "$SCOPE_DIR" ]; then
  echo "No cache directory found ($SCOPE_DIR). Nothing to clear."
  exit 0
fi

REMOVED=0
for pattern in ".typecheck-cache-*" ".quality-gate-cache-*"; do
  for f in "$SCOPE_DIR"/$pattern; do
    [ -f "$f" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] would remove: $f"
    else
      rm -f "$f"
      echo "Removed: $(basename "$f")"
    fi
    REMOVED=$((REMOVED + 1))
  done
done

if [ "$REMOVED" = "0" ]; then
  echo "No cache files found. Nothing to clear."
elif [ "$DRY_RUN" = "0" ]; then
  echo "Cleared $REMOVED cache file(s)."
fi
