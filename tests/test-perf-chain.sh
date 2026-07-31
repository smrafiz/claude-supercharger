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

# --- statusline target (Phase 2, item 2) -------------------------------------
begin_test "--target statusline reports cold and warm renders"
SOUT=$(bash "$HARNESS" --target statusline --iterations 2 2>/dev/null)
{ printf '%s' "$SOUT" | grep -q "cold (miss)" && printf '%s' "$SOUT" | grep -q "warm (hit)"; } \
  && pass || fail "missing cold/warm rows: $SOUT"

begin_test "--target statusline --json reports a cache speedup over real renders"
SJ=$(bash "$HARNESS" --target statusline --iterations 2 --json 2>/dev/null)
printf '%s' "$SJ" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['target']=='statusline', d
for k in ('cold_render','warm_render'):
    assert d[k]['mean_ms']>0, (k,d[k])
    assert d[k]['samples']==2, (k,d[k])
# The cache must actually be doing something. Asserting a floor rather than an exact
# figure: the point is that the warm path skips python3 entirely, which is worth
# multiples, not percent. A regression that quietly disables the cache lands here.
assert d['cache_speedup']>1.5, d['cache_speedup']
print('ok')
" >/dev/null 2>&1 && pass || fail "invalid statusline JSON or no cache benefit: $SJ"

begin_test "committed baseline carries BOTH the chain and statusline sections"
# --write-baseline runs once per target, so the second write must merge rather than
# overwrite; a plain write would silently drop whichever section ran first.
python3 -c "
import json
d=json.load(open('$REPO_DIR/docs/perf-baseline.json'))
assert 'payloads' in d and d['payloads'], 'chain section missing'
assert 'statusline' in d and d['statusline']['cold_render']['mean_ms']>0, 'statusline section missing'
print('ok')
" >/dev/null 2>&1 && pass || fail "baseline lost a section"

report
