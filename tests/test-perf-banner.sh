#!/usr/bin/env bash
# v2.23.39 — /perf must warn that avg_ms is unreliable on bash < 5 (profiler fork is
# counted; observed 10-60x over-report). On bash 5+ the fork-free clock is accurate,
# so the banner must NOT appear.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== /perf Reliability Banner Tests ==="

OUT=$(bash "$REPO_DIR/tools/hook-perf.sh" 2>/dev/null || true)

# v4.0.44: both assertions below are ABSENCE checks on bash 5+, and `|| true`
# hides a dead tool — so on ubuntu the whole file passed against a hook-perf.sh
# that produced nothing at all (verified by mutation). Prove the subject ran
# before asking what it did or did not print.
begin_test "control: hook-perf produces a report at all"
printf '%s' "$OUT" | grep -q 'Hook Performance Report' && pass \
  || fail "hook-perf produced no report, so every assertion below is vacuous"

begin_test "banner presence matches bash major version"
if [ "${BASH_VERSINFO:-0}" -lt 5 ]; then
  printf '%s' "$OUT" | grep -q "UNRELIABLE" && pass || fail "expected the bash<5 unreliability banner"
else
  printf '%s' "$OUT" | grep -q "UNRELIABLE" && fail "banner should be hidden on bash 5+" || pass
fi

begin_test "banner is suppressed in --json mode"
JOUT=$(bash "$REPO_DIR/tools/hook-perf.sh" --json 2>/dev/null || true)
if ! printf '%s' "$JOUT" | grep -q '"hooks"'; then
  fail "control: --json produced no JSON, so the leak assertion cannot fail"
elif printf '%s' "$JOUT" | grep -q "UNRELIABLE"; then
  fail "banner leaked into JSON output"
else
  pass
fi

report
