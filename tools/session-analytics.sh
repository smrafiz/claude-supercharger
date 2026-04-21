#!/usr/bin/env bash
# Claude Supercharger — Session Analytics
# Usage: bash tools/session-analytics.sh [--days N] [--projects PATH]

set -euo pipefail

DAYS=7
PROJECTS_DIR="$HOME/.claude/projects"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days|-d)     DAYS="$2"; shift 2 ;;
    --projects|-p) PROJECTS_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash tools/session-analytics.sh [--days N] [--projects PATH]"
      echo "  --days N        Lookback window in days (default: 7)"
      echo "  --projects PATH Override projects directory (default: ~/.claude/projects/)"
      exit 0 ;;
    *) shift ;;
  esac
done

if [ ! -d "$PROJECTS_DIR" ]; then
  echo "No session data found"
  exit 0
fi
