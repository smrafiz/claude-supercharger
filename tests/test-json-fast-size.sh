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

# v2.29.6: the ROUNDS were never the problem - the CLOCK was. This measured each
# arm by forking python twice to read time.time(), six forks per round, on the
# same contended runner whose contention it was trying to average out. On Git
# Bash a process spawn is ~27ms and highly variable under load, so the
# instrument's own cost was comparable to the effect being measured. It has been
# hardened twice already - the bound cut 2.0x -> 1.5x, then a single sample
# replaced by a median of three - and it flaked again on the v2.29.5 run at a
# point where nothing in the JSON path had changed at all.
#
# EPOCHREALTIME is a bash 5 builtin and costs no fork, which is the same clock
# hooks/lib-timing.sh already uses for its own timing. macOS ships bash 3.2 and
# has no such variable, so it keeps the python clock - and macOS is not where
# this flakes. Rounds go 3 -> 5 because they are nearly free once the forks are
# gone.
_now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    # EPOCHREALTIME is "seconds.microseconds", but the separator follows the
    # locale: under a comma-decimal locale the dot removal above leaves a comma
    # and the arithmetic would silently produce nonsense. Verified numeric before
    # it is trusted, with the python clock as the fallback either way.
    _er="${EPOCHREALTIME/./}"
    case "$_er" in
      ''|*[!0-9]*) : ;;
      *) echo $(( _er / 1000 )); return ;;
    esac
  fi
  python3 -c 'import time; print(int(time.time()*1000))'
}

# v2.29.13: one DISCARDED warm-up round before measuring. Without it the first
# measured round pays cold start on BOTH arms - page cache, bash and python
# startup, safety.sh's own first-run work - which compresses that round's ratio
# toward 1.0 and drags a 5-sample median under the bound. The v2.29.12 run failed
# at a median of 1.49x while its LAST round measured 2221ms vs 600ms, i.e. 3.7x:
# the fix was working perfectly and the early rounds were measuring startup.
_now_ms >/dev/null
SUPERCHARGER_JSON_FAST_MAX=100000000 bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1
bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1

_RATIOS=""
for _round in 1 2 3 4 5; do
  _T0=$(_now_ms)
  SUPERCHARGER_JSON_FAST_MAX=100000000 bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1
  _T1=$(_now_ms)
  _UNGATED_MS=$(( _T1 - _T0 ))

  _T0=$(_now_ms)
  bash "$REPO_DIR/hooks/safety.sh" < "$JF/timing.json" >/dev/null 2>&1
  _T1=$(_now_ms)
  _GATED_MS=$(( _T1 - _T0 ))

  # Integer hundredths, so no fork is needed to divide. A zero-length gated arm
  # would be a clock too coarse to measure with; skip that round rather than
  # score it as 0.00 and drag the median down.
  if [ "$_GATED_MS" -gt 0 ]; then
    _RATIOS="$_RATIOS $(( _UNGATED_MS * 100 / _GATED_MS ))"
  fi
done

_RATIO=$(python3 -c 'import sys,statistics; v=[int(x) for x in sys.argv[1].split()]; print("%.2f" % (statistics.median(v)/100) if v else "0.00")' "$_RATIOS")
# Bound is 1.5x, not 2x. The first version required 2.0x from the macOS ratio
# (~3.4x) and duly failed on the Git Bash runner at 1.95x — the fix WAS working
# there, but the ratio compresses on Windows because a fixed ~27ms per process
# spawn dilutes the quadratic saving. A threshold calibrated on one platform and
# asserted on all is a measurement of the platform, not of the fix. 1.5x still
# separates cleanly: without the gate the two arms are the same code and land
# at ~1.0x.
_OK=$(python3 -c 'import sys; print("1" if float(sys.argv[1]) >= 1.5 else "0")' "$_RATIO")
[ "$_OK" = "1" ] && pass \
  || fail "median ${_RATIO}x over rounds [${_RATIOS# } in hundredths] — the quadratic path is no longer being avoided (last round: gated ${_GATED_MS}ms vs ungated ${_UNGATED_MS}ms)"

rm -rf "$JF"

report
