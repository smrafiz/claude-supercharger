#!/usr/bin/env bash
# Claude Supercharger — Project Verify Hook
# Event: Stop | Matcher: *
# Runs .claude/verify.sh in the project root (if present).
# If verification fails, returns output to Claude so it can fix before finishing.
# Opt-in per project — no .claude/verify.sh = this hook is a no-op.

set -euo pipefail

# Find the project verify script
VERIFY_SCRIPT=""
if [ -f ".claude/verify.sh" ]; then
  VERIFY_SCRIPT=".claude/verify.sh"
elif [ -f "$PWD/.claude/verify.sh" ]; then
  VERIFY_SCRIPT="$PWD/.claude/verify.sh"
fi

[ -z "$VERIFY_SCRIPT" ] && exit 0

# Run it, capture output and exit code
VERIFY_OUTPUT=""
VERIFY_EXIT=0
VERIFY_OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1) || VERIFY_EXIT=$?

if [ "$VERIFY_EXIT" -eq 0 ]; then
  echo "[Supercharger] project-verify: passed" >&2
  exit 0
fi

# Verification failed — inject output so Claude can act on it
TRUNCATED=$(printf '%.2000s' "$VERIFY_OUTPUT")
MSG="[PROJECT VERIFY FAILED] Verification script (.claude/verify.sh) returned exit code ${VERIFY_EXIT}. Fix these before finishing:

${TRUNCATED}"

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] project-verify: FAILED (exit $VERIFY_EXIT)" >&2

exit 0
