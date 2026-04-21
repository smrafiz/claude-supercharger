#!/usr/bin/env bash
# Claude Supercharger — Quality Gate Hook (3-stage pipeline)
# Event: PostToolUse | Matcher: Write,Edit
# Stage 1: Run linter → Stage 2: Auto-fix → Stage 3: Re-check
# Replaces auto-format.sh with a more comprehensive quality gate.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
fi

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")
EXT="${FILE_PATH##*.}"
MAX_ITERATIONS=2
ITERATION=0
HAD_ISSUES=false

# Resolve timeout command: prefer gtimeout (macOS coreutils), then timeout, else plain execution
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout 30"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout 30"
else
  TIMEOUT_CMD=""
fi

lint_and_fix() {
  local file="$1"
  local issues=""

  case "$EXT" in
    py)
      # Stage 1: Lint
      if command -v ruff &>/dev/null; then
        issues=$($TIMEOUT_CMD ruff check "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          $TIMEOUT_CMD ruff check --fix "$file" 2>/dev/null || true
          # Also format
          $TIMEOUT_CMD ruff format "$file" 2>/dev/null || true
          return 0
        fi
        $TIMEOUT_CMD ruff format "$file" 2>/dev/null || true
      elif command -v black &>/dev/null; then
        $TIMEOUT_CMD black -q "$file" 2>/dev/null || true
      fi
      ;;
    js|jsx|ts|tsx|mjs|cjs)
      # Stage 1: Lint
      if command -v eslint &>/dev/null && { ls "$PROJECT_ROOT"/.eslintrc* &>/dev/null 2>&1 || ls "$PROJECT_ROOT"/eslint.config* &>/dev/null 2>&1; }; then
        issues=$($TIMEOUT_CMD eslint "$file" 2>&1) || true
        if [ -n "$issues" ]; then
          HAD_ISSUES=true
          # Stage 2: Auto-fix
          $TIMEOUT_CMD eslint --fix "$file" 2>/dev/null || true
        fi
      fi
      # Format
      if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        if command -v npx &>/dev/null; then
          $TIMEOUT_CMD npx --no prettier --write "$file" 2>/dev/null || true
        fi
      fi
      ;;
    rs)
      if command -v rustfmt &>/dev/null; then
        $TIMEOUT_CMD rustfmt "$file" 2>/dev/null || true
      fi
      ;;
    go)
      if command -v gofmt &>/dev/null; then
        $TIMEOUT_CMD gofmt -w "$file" 2>/dev/null || true
      fi
      if command -v golangci-lint &>/dev/null; then
        issues=$($TIMEOUT_CMD golangci-lint run "$file" 2>&1) || true
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

PREV_ISSUES=""
while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  HAD_ISSUES=false
  lint_and_fix "$FILE_PATH"

  if ! $HAD_ISSUES; then
    break
  fi

  # Compare with previous iteration — break if issues unchanged (fix can't resolve them)
  CURRENT_HASH=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1 || md5 -q "$FILE_PATH" 2>/dev/null || echo "")
  if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" = "$PREV_ISSUES" ]; then
    break
  fi
  PREV_ISSUES="$CURRENT_HASH"

  ITERATION=$((ITERATION + 1))
done

# Final re-check: inject any remaining unfixed issues as systemMessage
REMAINING=""
case "$EXT" in
  py)
    if command -v ruff &>/dev/null; then
      REMAINING=$($TIMEOUT_CMD ruff check "$FILE_PATH" 2>&1) || true
    fi
    ;;
  js|jsx|ts|tsx|mjs|cjs)
    if command -v eslint &>/dev/null && { ls "$PROJECT_ROOT"/.eslintrc* &>/dev/null 2>&1 || ls "$PROJECT_ROOT"/eslint.config* &>/dev/null 2>&1; }; then
      REMAINING=$($TIMEOUT_CMD eslint "$FILE_PATH" 2>&1) || true
    fi
    ;;
  go)
    if command -v golangci-lint &>/dev/null; then
      REMAINING=$($TIMEOUT_CMD golangci-lint run "$FILE_PATH" 2>&1) || true
    fi
    ;;
esac

if [ -n "$REMAINING" ]; then
  TRUNCATED=$(printf '%.1500s' "$REMAINING")
  MSG="[QUALITY GATE] Unfixed lint issues in ${FILE_PATH} (auto-fix could not resolve):

${TRUNCATED}

Fix these issues before marking the task complete."
  CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps({'systemMessage':sys.stdin.read()}))" 2>/dev/null)
  [ -n "$CONTEXT_JSON" ] && printf '%s\n' "$CONTEXT_JSON"
fi

exit 0
