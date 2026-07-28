#!/usr/bin/env bash
# v2.23.39 — /perf must warn that avg_ms is unreliable on bash < 5 (profiler fork is
# counted; observed 10-60x over-report). On bash 5+ the fork-free clock is accurate,
# so the banner must NOT appear.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== /perf Reliability Banner Tests ==="

OUT=$(bash "$REPO_DIR/tools/hook-perf.sh" 2>/dev/null || true)

begin_test "banner presence matches bash major version"
if [ "${BASH_VERSINFO:-0}" -lt 5 ]; then
  printf '%s' "$OUT" | grep -q "UNRELIABLE" && pass || fail "expected the bash<5 unreliability banner"
else
  printf '%s' "$OUT" | grep -q "UNRELIABLE" && fail "banner should be hidden on bash 5+" || pass
fi

begin_test "banner is suppressed in --json mode"
JOUT=$(bash "$REPO_DIR/tools/hook-perf.sh" --json 2>/dev/null || true)
printf '%s' "$JOUT" | grep -q "UNRELIABLE" && fail "banner leaked into JSON output" || pass

report
