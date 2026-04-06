#!/usr/bin/env bash
# Claude Supercharger — Quality Gate Hook (3-stage pipeline)
# Event: PostToolUse | Matcher: Write,Edit
# Stage 1: Run linter → Stage 2: Auto-fix → Stage 3: Re-check
# Replaces auto-format.sh with a more comprehensive quality gate.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")
EXT="${FILE_PATH##*.}"
MAX_ITERATIONS=3
ITERATION=0
HAD_ISSUES=false

lint_and_fix() {
  local file="$1"
  local issues=""

  case "$EXT" in
    py)
      # Stage 1: Lint
      if command -v ruff &>/dev/null; then
        issues=$(ruff check "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          ruff check --fix "$file" 2>/dev/null || true
          # Also format
          ruff format "$file" 2>/dev/null || true
          return 0
        fi
        ruff format "$file" 2>/dev/null || true
      elif command -v black &>/dev/null; then
        black -q "$file" 2>/dev/null || true
      fi
      ;;
    js|jsx|ts|tsx|mjs|cjs)
      # Stage 1: Lint
      if command -v eslint &>/dev/null && { compgen -G "$PROJECT_ROOT/.eslintrc*" &>/dev/null || compgen -G "$PROJECT_ROOT/eslint.config*" &>/dev/null; }; then
        issues=$(eslint "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          eslint --fix "$file" 2>/dev/null || true
        fi
      fi
      # Format
      if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        if command -v npx &>/dev/null; then
          npx --yes prettier --write "$file" 2>/dev/null || true
        fi
      fi
      ;;
    rs)
      if command -v rustfmt &>/dev/null; then
        rustfmt "$file" 2>/dev/null || true
      fi
      if command -v cargo &>/dev/null && [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        issues=$(cargo clippy --message-format=short 2>&1 | grep "$file" || true)
        [ -n "$issues" ] && HAD_ISSUES=true
      fi
      ;;
    go)
      if command -v gofmt &>/dev/null; then
        gofmt -w "$file" 2>/dev/null || true
      fi
      if command -v golangci-lint &>/dev/null; then
        issues=$(golangci-lint run "$file" 2>&1) || true
        [ -n "$issues" ] && HAD_ISSUES=true
      fi
      ;;
    *)
      # No linter for this file type
      return 0
      ;;
  esac

  return 0
}

# Run the pipeline with iteration
while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  HAD_ISSUES=false
  lint_and_fix "$FILE_PATH"

  if ! $HAD_ISSUES; then
    break
  fi

  ITERATION=$((ITERATION + 1))

  # Stage 3: Re-check — only continue if auto-fix actually changed something
  if [ $ITERATION -lt $MAX_ITERATIONS ]; then
    sleep 0.1
  fi
done

exit 0
