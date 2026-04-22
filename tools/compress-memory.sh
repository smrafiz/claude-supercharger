#!/usr/bin/env bash
# Claude Supercharger — Memory File Compressor
# Usage: supercharger compress <filepath>
#
# Compresses natural language files (CLAUDE.md, MEMORY.md, etc.) to reduce
# input tokens. Preserves code blocks, URLs, paths, headings, and structure.
# Backup saved as FILE.original.md.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: supercharger compress <filepath>"
  echo ""
  echo "Compresses natural language markdown files to reduce input tokens."
  echo "Preserves code, URLs, paths, headings. Backup saved as FILE.original.md."
  exit 1
fi

FILEPATH="$1"

if [ ! -f "$FILEPATH" ]; then
  echo "Error: File not found: $FILEPATH"
  exit 1
fi

cd "$TOOLS_DIR"
python3 -m compress "$(cd "$(dirname "$FILEPATH")" && pwd)/$(basename "$FILEPATH")"
