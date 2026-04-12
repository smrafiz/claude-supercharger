#!/usr/bin/env bash
# Claude Supercharger — Verify on Stop Hook
# Event: Stop | Matcher: *
# Warns if files were modified but no test/build command was detected.
# Advisory only — never blocks (exit 0 always).

set -euo pipefail

AUDIT_DIR="$HOME/.claude/supercharger/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

# No audit log = nothing to check
[ ! -f "$AUDIT_FILE" ] && exit 0

# Check if files were modified (Write or Edit tool entries)
HAS_WRITES=false
if grep -q '"Write"\|"Edit"' "$AUDIT_FILE" 2>/dev/null; then
  HAS_WRITES=true
fi

# No writes = nothing to verify
$HAS_WRITES || exit 0

# Check if a test or build command ran
HAS_TEST=false
if grep -qiE '(npm test|yarn test|pnpm test|cargo test|pytest|go test|jest|vitest|mocha|npm run test|npm run build|cargo build|go build|make test|make build)' "$AUDIT_FILE" 2>/dev/null; then
  HAS_TEST=true
fi

if ! $HAS_TEST; then
  echo "" >&2
  echo "[Supercharger] ⚠ Files modified but no test/build command detected this session." >&2
  echo "  Consider running tests before finishing." >&2
  echo "" >&2
fi

exit 0
