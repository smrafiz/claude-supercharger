#!/usr/bin/env bash
# Claude Supercharger — Auto-Format Hook
# Event: PostToolUse | Matcher: Write|Edit
# Runs project formatter on edited files. Developer role only.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")

# Try prettier (JavaScript/TypeScript)
if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  if command -v npx &>/dev/null; then
    npx --yes prettier --write "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try black (Python)
if [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -q 'black' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
  if command -v black &>/dev/null; then
    black -q "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try rustfmt (Rust)
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  if command -v rustfmt &>/dev/null; then
    rustfmt "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try gofmt (Go)
if [ -f "$PROJECT_ROOT/go.mod" ] && [[ "$FILE_PATH" == *.go ]]; then
  if command -v gofmt &>/dev/null; then
    gofmt -w "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

exit 0
