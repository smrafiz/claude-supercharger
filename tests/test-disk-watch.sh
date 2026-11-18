#!/usr/bin/env bash
# disk-watch.sh (2026-11-17, from tsrmehmet/memokit's check-disk.sh): after a Bash
# call, tell Claude when free disk space dropped by a lot since the previous call,
# or sits under a floor. SUPERCHARGER_DF_KB is the test seam for the measured value.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/disk-watch.sh"
echo "=== disk-watch ==="

D=$(mktemp -d); trap 'rm -rf "$D"' EXIT; mkdir -p "$D/scope"
GB=1048576
# post <free_kb> [event] [session] → hook stdout
post() {
  printf '{"hook_event_name":"%s","tool_name":"Bash","session_id":"%s","cwd":"/tmp","tool_input":{"command":"x"}}' "${2:-PostToolUse}" "${3:-s1}" \
    | SUPERCHARGER_STATE="$D" SUPERCHARGER_DF_KB="$1" bash "$H" 2>/dev/null
}

begin_test "first call only records: silent"
[ -z "$(post $((100*GB)))" ] && pass || fail "spoke on first call"

begin_test "a small drop is silent"
[ -z "$(post $((99*GB)))" ] && pass || fail "warned on 1 GB"

begin_test "a drop of 10 GB since the last call is reported to Claude"
out=$(post $((89*GB)))
[[ "$out" == *additionalContext* && "$out" == *"10 GB"* && "$out" == *PostToolUse* ]] && pass || fail "no drop warning: $out"

begin_test "a failed command reports under PostToolUseFailure"
post $((89*GB)) >/dev/null
out=$(post $((70*GB)) PostToolUseFailure)
[[ "$out" == *'"PostToolUseFailure"'* ]] && pass || fail "wrong event: $out"

begin_test "sessions keep separate baselines"
[ -z "$(post $((50*GB)) PostToolUse s2)" ] && pass || fail "s2 compared against s1's baseline"

begin_test "under the 5 GB floor: warned"
out=$(post $((4*GB)) PostToolUse s3)
[[ "$out" == *"4 GB free"* ]] && pass || fail "no floor warning: $out"

begin_test "under the floor again within 10 minutes: silent"
[ -z "$(post $((4*GB)) PostToolUse s3)" ] && pass || fail "floor warning repeated"

begin_test "SUPERCHARGER_DISK_DROP_GB raises the drop threshold"
post $((100*GB)) PostToolUse s4 >/dev/null
[ -z "$(SUPERCHARGER_DISK_DROP_GB=20 post $((89*GB)) PostToolUse s4)" ] && pass || fail "custom threshold ignored"

begin_test "non-Bash tools are ignored"
out=$(printf '{"hook_event_name":"PostToolUse","tool_name":"Read","session_id":"s5","cwd":"/tmp"}' | SUPERCHARGER_STATE="$D" SUPERCHARGER_DF_KB=1 bash "$H" 2>/dev/null)
[ -z "$out" ] && pass || fail "Read triggered: $out"

report
