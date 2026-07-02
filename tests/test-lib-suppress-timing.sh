#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-suppress.sh"
SENTINEL="$HOME/.claude/supercharger/scope/.profiling"

echo "=== lib-suppress Timing Tests ==="

# v2.7.46: without a sentinel, HOOK_START_MS is 0 on bash 3.2 (no cheap clock →
# always-on timing off), but POPULATED on bash 5+ (EPOCHREALTIME → always-on
# slow-hook timing). Assert the correct state for whichever bash is running.
begin_test "timing: HOOK_START_MS reflects always-on state (no sentinel)"
result=$(
  unset HOOK_START_MS
  rm -f "$SENTINEL"
  source "$LIB"
  init_hook_suppress
  if [ -n "${EPOCHREALTIME:-}" ]; then
    [ "${HOOK_START_MS:-0}" -gt 0 ] 2>/dev/null && echo "ok"   # bash 5+: always-on
  else
    [ -n "${HOOK_START_MS+x}" ] && [ "${HOOK_START_MS:-x}" = "0" ] && echo "ok"  # bash 3.2: off
  fi
)
if [ "$result" = "ok" ]; then
  pass
else
  fail "HOOK_START_MS wrong for this bash (EPOCHREALTIME='${EPOCHREALTIME:-unset}')"
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

# v2.7.45: always-on slow-hook logging. _emit_hook_timing records only
# invocations >= threshold in auto mode, and everything in full-profiling mode.
# NB: on bash 3.2 the emit forks python for the end timestamp, so a "just now"
# start can measure ~30-50ms of fork latency — use a huge threshold so that
# noise can't exceed it; we're testing the skip path, not the clock.
begin_test "timing: emit SKIPS an invocation below threshold (auto mode)"
result=$(
  TH=$(mktemp -d); export HOME="$TH"; mkdir -p "$HOME/.claude/supercharger/scope"
  export SUPERCHARGER_PERF_THRESHOLD_MS=100000
  source "$LIB"
  HOOK_NAME=ftfast; _HOOK_PERF_FULL=0
  HOOK_START_MS=$(python3 -c 'import time;print(int(time.time()*1000))')
  _emit_hook_timing
  grep -c ftfast "$HOME/.claude/supercharger/audit/$(date +%Y-%m-%d).jsonl" 2>/dev/null || echo 0
)
[ "${result##* }" = "0" ] && pass || fail "below-threshold invocation was logged (expected skip): $result"

begin_test "timing: emit RECORDS a slow invocation above threshold (auto mode)"
result=$(
  TH=$(mktemp -d); export HOME="$TH"; mkdir -p "$HOME/.claude/supercharger/scope"
  source "$LIB"
  HOOK_NAME=ftslow; _HOOK_PERF_FULL=0
  HOOK_START_MS=$(python3 -c 'import time;print(int(time.time()*1000)-200)')
  _emit_hook_timing
  grep -c ftslow "$HOME/.claude/supercharger/audit/$(date +%Y-%m-%d).jsonl" 2>/dev/null || echo 0
)
[ "${result##* }" = "1" ] && pass || fail "slow invocation not recorded: $result"

begin_test "timing: full-profiling mode records even a fast invocation"
result=$(
  TH=$(mktemp -d); export HOME="$TH"; mkdir -p "$HOME/.claude/supercharger/scope"
  source "$LIB"
  HOOK_NAME=ftfull; _HOOK_PERF_FULL=1
  HOOK_START_MS=$(python3 -c 'import time;print(int(time.time()*1000))')
  _emit_hook_timing
  grep -c ftfull "$HOME/.claude/supercharger/audit/$(date +%Y-%m-%d).jsonl" 2>/dev/null || echo 0
)
[ "${result##* }" = "1" ] && pass || fail "full mode did not record fast invocation: $result"

report
