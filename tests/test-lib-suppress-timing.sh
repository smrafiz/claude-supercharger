#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-suppress.sh"
SENTINEL="$HOME/.claude/supercharger/scope/.profiling"

echo "=== lib-suppress Timing Tests ==="

begin_test "timing: HOOK_START_MS is set after sourcing lib-suppress"
result=$(
  unset HOOK_START_MS
  rm -f "$SENTINEL"
  source "$LIB"
  init_hook_suppress
  if [ -n "${HOOK_START_MS+x}" ] && [ "${HOOK_START_MS:-x}" = "0" ] 2>/dev/null; then
    echo "ok"
  fi
)
if [ "$result" = "ok" ]; then
  pass
else
  fail "HOOK_START_MS not set or not 0 when no sentinel"
fi

begin_test "timing: HOOK_START_MS is numeric"
result=$(
  unset HOOK_START_MS
  rm -f "$SENTINEL"
  source "$LIB"
  init_hook_suppress
  echo "${HOOK_START_MS:-}"
)
if [[ "$result" =~ ^[0-9]+$ ]]; then
  pass
else
  fail "HOOK_START_MS='$result' does not match ^[0-9]+$"
fi

begin_test "timing: HOOK_START_MS is populated when profiling is active"
result=$(
  unset HOOK_START_MS
  mkdir -p "$(dirname "$SENTINEL")"
  touch "$SENTINEL"
  source "$LIB"
  init_hook_suppress
  rm -f "$SENTINEL"
  if [ "${HOOK_START_MS:-0}" -gt 0 ] 2>/dev/null; then
    echo "ok"
  fi
)
if [ "$result" = "ok" ]; then
  pass
else
  fail "HOOK_START_MS not >0 when sentinel present"
fi

report
