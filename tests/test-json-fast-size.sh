#!/usr/bin/env bash
# The fork-free JSON reader must refuse payloads it is slower at than the fork.
#
# _json_fast_str exists to avoid a jq fork, and below a few KB it does. But its
# slicing is greedy parameter expansion over the WHOLE payload — quadratic —
# while jq is flat. Measured on macOS extracting one key:
#
#      2.4 KB    12 ms vs jq 20 ms   fork-free wins
#      6.7 KB    23 ms vs jq 17 ms   crossover
#     73.9 KB  4842 ms vs jq 17 ms   280x SLOWER than the fork it replaced
#
# safety.sh calls it up to five times, so a long Bash command took the top
# security hook to 19.7s at 62KB and 102s at 126KB — past the harness's 15s
# kill, i.e. the guard was being KILLED mid-check instead of returning a verdict.
# After the gate: 3.5s at 62KB.
#
# The gate is only safe because every caller has a jq/python/grep fallback, so a
# refusal costs one fork and never a missing value. The verdict tests at the end
# are the ones that matter: a dangerous command must still be caught when it is
# long enough to take the fallback path.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=hooks/lib-json-fast.sh
. "$REPO_DIR/hooks/lib-json-fast.sh"

echo "=== lib-json-fast size gate Tests ==="

JF=$(mktemp -d)

mkpay() {  # $1=path-count $2=outfile [$3=suffix]
  python3 - "$1" "$2" "${3:-}" <<'PYEOF'
import json, sys
n = int(sys.argv[1])
cmd = "prettier --write " + " ".join("src/m%d/c%d.ts" % (i, i) for i in range(n))
if sys.argv[3]:
    cmd += " " + sys.argv[3]
json.dump({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/tmp"},
          open(sys.argv[2], "w"))
PYEOF
}

begin_test "a small payload still takes the fork-free path"
mkpay 20 "$JF/small.json"
SMALL=$(cat "$JF/small.json")
if _json_fast_str command "$SMALL"; then
  case "$_JSON_FAST_VAL" in prettier*) pass ;; *) fail "wrong value: ${_JSON_FAST_VAL:0:40}" ;; esac
else
  fail "refused a payload it should handle (${#SMALL} bytes)"
fi

begin_test "a payload past the crossover is refused, so the caller forks instead"
mkpay 2000 "$JF/big.json"
BIG=$(cat "$JF/big.json")
_json_fast_str command "$BIG" && fail "accepted ${#BIG} bytes — the quadratic path is back" || pass

begin_test "the threshold is configurable"
SUPERCHARGER_JSON_FAST_MAX=1000000 _json_fast_str command "$BIG" \
  && pass || fail "raising SUPERCHARGER_JSON_FAST_MAX did not re-enable it"

begin_test "refusing sets no stale value for the caller to read"
_json_fast_str command "$BIG" || true
[ -z "$_JSON_FAST_VAL" ] && pass || fail "left a value behind: ${_JSON_FAST_VAL:0:40}"

# --- the part that must not regress -----------------------------------------
begin_test "a LONG dangerous command is still blocked (via the fallback path)"
mkpay 2000 "$JF/danger.json" "&& rm -rf /"
bash "$REPO_DIR/hooks/safety.sh" < "$JF/danger.json" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "a dangerous command escaped once the payload got large"

begin_test "a LONG benign command is still allowed"
mkpay 2000 "$JF/benign.json"
bash "$REPO_DIR/hooks/safety.sh" < "$JF/benign.json" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "a benign command was blocked"

# The point of the gate: safety.sh must stop scaling quadratically with command
# length, because past ~45KB that ran it into the harness's 15s kill.
#
# Asserted RELATIVELY, not against a wall-clock ceiling. A first draft required
# "< 10s on a 62KB command"; that passes solo (3.5s) and fails inside the release,
# where the suite runs four jobs in parallel and the same work takes 10.1s. An
# absolute bound on a loaded machine measures the machine. Running both arms back
# to back in the same conditions cancels the load: SUPERCHARGER_JSON_FAST_MAX
# raised to infinity restores the old quadratic path, so the gated run simply has
# to be markedly faster than the ungated one.
begin_test "the size gate makes safety.sh markedly faster on a large command"
mkpay 2000 "$JF/timing.json"

_T0=$(python3 -c 'import time; print(time.time())')
SUPERCHARGER_JSON_FAST_MAX=100000000 bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1
_T1=$(python3 -c 'import time; print(time.time())')
_UNGATED=$(python3 -c 'import sys; print("%.3f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$_T0" "$_T1")

_T0=$(python3 -c 'import time; print(time.time())')
bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1
_T1=$(python3 -c 'import time; print(time.time())')
_GATED=$(python3 -c 'import sys; print("%.3f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$_T0" "$_T1")

_RATIO=$(python3 -c 'import sys; g=float(sys.argv[1]); print("%.2f" % ((float(sys.argv[2])/g) if g > 0 else 0))' "$_GATED" "$_UNGATED")
# Bound is 1.5x, not 2x. The first version required 2.0x from the macOS ratio
# (~3.4x) and duly failed on the Git Bash runner at 1.95x — the fix WAS working
# there, but the ratio compresses on Windows because a fixed ~27ms per process
# spawn dilutes the quadratic saving. A threshold calibrated on one platform and
# asserted on all is a measurement of the platform, not of the fix. 1.5x still
# separates cleanly: without the gate the two arms are the same code and land
# at ~1.0x.
_OK=$(python3 -c 'import sys; print("1" if float(sys.argv[1]) >= 1.5 else "0")' "$_RATIO")
[ "$_OK" = "1" ] && pass \
  || fail "gated ${_GATED}s vs ungated ${_UNGATED}s (${_RATIO}x) — the quadratic path is no longer being avoided"

rm -rf "$JF"

report
