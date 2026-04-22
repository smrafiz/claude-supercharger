#!/usr/bin/env bash
# Claude Supercharger — Stop Verification
# Event: Stop | Matcher: *
# Merged from verify-on-stop.sh + project-verify.sh
# 1. Warns if files were modified but no test/build ran (advisory)
# 2. Runs .claude/verify.sh if present and injects failures into context

set -euo pipefail

AUDIT_DIR="$HOME/.claude/supercharger/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

# ── Part 1: verify-on-stop (advisory, stderr only) ──

# Detect test command from project
detect_test_cmd() {
  local dir="${1:-.}"
  if [ -f "$dir/package.json" ]; then
    # Check for test script in package.json
    if python3 -c "import json; d=json.load(open('$dir/package.json')); exit(0 if 'test' in d.get('scripts',{}) else 1)" 2>/dev/null; then
      # Detect package manager
      if [ -f "$dir/pnpm-lock.yaml" ]; then echo "pnpm test"
      elif [ -f "$dir/bun.lockb" ]; then echo "bun test"
      elif [ -f "$dir/yarn.lock" ]; then echo "yarn test"
      else echo "npm test"
      fi
      return
    fi
  fi
  if [ -f "$dir/pytest.ini" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.cfg" ]; then
    echo "pytest"
    return
  fi
  if [ -f "$dir/Cargo.toml" ]; then
    echo "cargo test"
    return
  fi
  if [ -f "$dir/go.mod" ]; then
    echo "go test ./..."
    return
  fi
  echo ""
}

PROJECT_DIR="${PWD}"
TEST_CMD=$(detect_test_cmd "$PROJECT_DIR")

if [ -f "$AUDIT_FILE" ]; then
  HAS_WRITES=false
  grep -q '"Write"\|"Edit"' "$AUDIT_FILE" 2>/dev/null && HAS_WRITES=true

  if $HAS_WRITES; then
    HAS_TEST=false
    grep -qiE '(npm test|yarn test|pnpm test|cargo test|pytest|go test|jest|vitest|mocha|npm run test|npm run build|cargo build|go build|make test|make build)' "$AUDIT_FILE" 2>/dev/null && HAS_TEST=true

    if ! $HAS_TEST; then
      echo "" >&2
      echo "[Supercharger] ⚠ Files modified but no test/build command detected this session." >&2
      if [ -n "$TEST_CMD" ]; then
        echo "  Try: ${TEST_CMD}" >&2
      else
        echo "  Consider running tests before finishing." >&2
      fi
      echo "" >&2
    fi
  fi
fi

# ── Part 2: project-verify (blocks Claude on failure) ──
VERIFY_SCRIPT=""
[ -f ".claude/verify.sh" ] && VERIFY_SCRIPT=".claude/verify.sh"
[ -z "$VERIFY_SCRIPT" ] && [ -f "$PWD/.claude/verify.sh" ] && VERIFY_SCRIPT="$PWD/.claude/verify.sh"

[ -z "$VERIFY_SCRIPT" ] && exit 0

# Skip if no file changes this session
CHANGED=$(git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
if [ -z "$CHANGED" ]; then
  echo "[Supercharger] stop-verify: skipped (no file changes)" >&2
  exit 0
fi

VERIFY_OUTPUT=""
VERIFY_EXIT=0
VERIFY_OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1) || VERIFY_EXIT=$?

if [ "$VERIFY_EXIT" -eq 0 ]; then
  echo "[Supercharger] stop-verify: passed" >&2
  exit 0
fi

TRUNCATED=$(printf '%.2000s' "$VERIFY_OUTPUT")
MSG="[PROJECT VERIFY FAILED] Verification script (.claude/verify.sh) returned exit code ${VERIFY_EXIT}. Fix these before finishing:

${TRUNCATED}"

REASON_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
  || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"stopReason":%s}\n' "$REASON_JSON"

echo "[Supercharger] stop-verify: FAILED (exit $VERIFY_EXIT)" >&2
exit 0
