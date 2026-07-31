#!/usr/bin/env bash
# Perf report (HOOK-LATENCY-PLAN Phase 3).
#
# The CI job that calls this is report-only, so nothing about a slow number can
# fail. That makes the failure mode obvious: a perf job that measures nothing and
# says nothing still goes green. These assertions pin the one thing that must NOT
# pass quietly — an absent or unusable measurement.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPORT="$REPO_DIR/tools/perf-report.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

echo "=== Perf Report Tests ==="

# Synthetic inputs, not a live harness run: this test is about the report's
# handling of its inputs, and running the real chain here would add seconds to the
# suite for coverage tests/test-perf-chain.sh already provides.
cat > "$TD/chain.json" <<'EOS'
{"event":"PreToolUse","tool":"Bash","hooks":17,"iterations":5,"platform":"Linux",
 "payloads":{"fast-pathed":{"chain_sum_ms":70.0,"parallel_est_ms":8.0,"parallel_width":11,
   "slowest_hook":"budget-cap.sh","slowest_ms":7.2,"per_hook_ms":{"budget-cap.sh":7.2}}}}
EOS
cat > "$TD/sl.json" <<'EOS'
{"target":"statusline","iterations":10,"platform":"Linux",
 "cold_render":{"mean_ms":40.0,"min_ms":38.0,"max_ms":42.0,"samples":10},
 "warm_render":{"mean_ms":8.0,"min_ms":7.0,"max_ms":9.0,"samples":10},
 "cache_speedup":5.0}
EOS
cat > "$TD/base.json" <<'EOS'
{"event":"PreToolUse","tool":"Bash","hooks":17,"iterations":5,"platform":"Linux",
 "payloads":{"fast-pathed":{"chain_sum_ms":70.0,"parallel_est_ms":8.0,"parallel_width":11,
   "slowest_hook":"budget-cap.sh","slowest_ms":7.2,"per_hook_ms":{"budget-cap.sh":7.2}}},
 "statusline":{"cold_render":{"mean_ms":40.0},"warm_render":{"mean_ms":8.0}}}
EOS

begin_test "perf-report: emits a markdown table for chain and statusline"
OUT=$(bash "$REPORT" --chain "$TD/chain.json" --statusline "$TD/sl.json" --baseline "$TD/base.json" 2>&1)
{ printf '%s' "$OUT" | grep -q 'Hook latency' \
  && printf '%s' "$OUT" | grep -q 'budget-cap.sh' \
  && printf '%s' "$OUT" | grep -q 'Statusline render' \
  && printf '%s' "$OUT" | grep -q 'Cache speedup'; } && pass || fail "incomplete report: $OUT"

begin_test "perf-report: computes a delta against the baseline"
sed 's/"parallel_est_ms":8.0/"parallel_est_ms":16.0/' "$TD/chain.json" > "$TD/slow.json"
OUT=$(bash "$REPORT" --chain "$TD/slow.json" --baseline "$TD/base.json" 2>&1)
printf '%s' "$OUT" | grep -q '+100%' && pass || fail "expected a +100% delta: $OUT"

begin_test "perf-report: a doubled reading is flagged but does NOT fail the job"
bash "$REPORT" --chain "$TD/slow.json" --baseline "$TD/base.json" >/dev/null 2>&1
RC=$?
OUT=$(bash "$REPORT" --chain "$TD/slow.json" --baseline "$TD/base.json" 2>&1)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q '⚠'; then pass
else fail "report-only contract broken: rc=$RC (want 0), warn-marker present=$(printf '%s' "$OUT" | grep -c '⚠')"; fi

begin_test "perf-report: cross-platform deltas are labelled and not flagged"
# A baseline from a dev mac against an ubuntu runner differs by more than any
# regression would; marking that as a warning would train people to ignore the mark.
sed 's/"platform":"Linux"/"platform":"Darwin"/' "$TD/base.json" > "$TD/base-mac.json"
OUT=$(bash "$REPORT" --chain "$TD/slow.json" --baseline "$TD/base-mac.json" 2>&1)
{ printf '%s' "$OUT" | grep -q 'indicative only' \
  && ! printf '%s' "$OUT" | grep -q '⚠'; } && pass || fail "cross-platform handling wrong: $OUT"

begin_test "perf-report: FAILS when the measurement is missing"
bash "$REPORT" --chain "$TD/nope.json" --baseline "$TD/base.json" >/dev/null 2>&1
[ "$?" -ne 0 ] && pass || fail "a perf run that produced no numbers must not report success"

begin_test "perf-report: FAILS when the measurement is unparseable"
printf 'not json {' > "$TD/bad.json"
bash "$REPORT" --chain "$TD/bad.json" --baseline "$TD/base.json" >/dev/null 2>&1
[ "$?" -ne 0 ] && pass || fail "unparseable input must not report success"

begin_test "perf-report: FAILS when the harness ran but measured nothing"
printf '{"event":"PreToolUse","tool":"Bash","hooks":0,"payloads":{}}' > "$TD/empty.json"
bash "$REPORT" --chain "$TD/empty.json" --baseline "$TD/base.json" >/dev/null 2>&1
[ "$?" -ne 0 ] && pass || fail "an empty payload set must not report success"

begin_test "perf-report: the CI job invokes it with both measurements"
# Guards the wiring, not the script: a job that silently stopped passing
# --statusline would drop half the report and every assertion above would still pass.
CI="$REPO_DIR/.github/workflows/ci.yml"
{ grep -q 'perf-report.sh' "$CI" && grep -q 'perf-chain.sh --iterations' "$CI" \
  && grep -q 'target statusline' "$CI"; } && pass || fail "ci.yml perf job not wired to both measurements"

report
