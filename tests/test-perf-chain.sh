#!/usr/bin/env bash
# Smoke test for the hook-chain latency harness (HOOK-LATENCY-PLAN Phase 1).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HARNESS="$REPO_DIR/tests/perf-chain.sh"
echo "=== Perf-Chain Harness Tests ==="

begin_test "runs and prints a chain-sum for both payloads (PreToolUse/Bash)"
OUT=$(bash "$HARNESS" --iterations 1 2>/dev/null)
{ printf '%s' "$OUT" | grep -q "fast-pathed" && printf '%s' "$OUT" | grep -q "non-fast-pathed" \
  && printf '%s' "$OUT" | grep -q "chain sum ="; } && pass || fail "missing chain-sum output: $OUT"

begin_test "--json emits valid JSON with per-hook means + slowest"
JOUT=$(bash "$HARNESS" --iterations 1 --json 2>/dev/null)
printf '%s' "$JOUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['tool']=='Bash' and d['event']=='PreToolUse', d
assert d['hooks']>0, d
for lab in ('fast-pathed','non-fast-pathed'):
    p=d['payloads'][lab]
    assert p['chain_sum_ms']>0, p
    assert p['slowest_hook'].endswith('.sh'), p
    assert len(p['per_hook_ms'])==d['hooks'], (len(p['per_hook_ms']), d['hooks'])
print('ok')
" >/dev/null 2>&1 && pass || fail "invalid/incomplete JSON: $JOUT"

begin_test "an event with no registered hooks exits non-zero"
bash "$HARNESS" --event NoSuchEvent --iterations 1 >/dev/null 2>&1 && fail "should exit non-zero" || pass

begin_test "committed baseline exists and parses"
[ -f "$REPO_DIR/docs/perf-baseline.json" ] && python3 -c "import json;json.load(open('$REPO_DIR/docs/perf-baseline.json'))" 2>/dev/null && pass || fail "baseline missing/unparseable"

report
