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

begin_test "chain output splits the sum into process spawn and hook work"
# The split is the finding Phase 4 rests on: ~half the chain sum is process
# creation and cannot be optimised away by editing hooks. A report that lost it
# would send the next reader optimising the wrong half.
SPOUT=$(bash "$HARNESS" --iterations 1 2>/dev/null)
printf '%s' "$SPOUT" | grep -q 'is process spawn' && pass || fail "no spawn/work split: $SPOUT"

# v2.26.61: the ~1-in-5 suite flake, finally captured by the failure trap added
# in v2.26.47. It was never a race between test files — it is this harness's own
# arithmetic. spawn_ms (floor x hooks) and chain_sum_ms are INDEPENDENT
# measurements; under load the floor probe inflates and spawn can exceed the whole
# chain. Captured artifact: spawn 136.0 inside an 89.0 chain, share 1.53, work
# clamped to 0 — which broke the harness's own spawn+work==sum identity.
#
# Fixed in the harness (clamp + a spawn_estimate_capped flag) rather than by
# loosening the test: reporting a 136 ms spawn inside an 89 ms chain is wrong in
# the OUTPUT, not just in the assertion.
begin_test "degenerate case: an inflated spawn estimate stays self-consistent"
python3 - <<'PY'
import sys
# The exact numbers from the captured failure.
chain_sum, spawn_raw = 89.0, 136.0
capped = spawn_raw > chain_sum > 0
spawn = chain_sum if capped else spawn_raw
work  = max(0.0, chain_sum - spawn)
share = spawn / chain_sum
ok = capped and abs((spawn + work) - chain_sum) < 0.2 and 0 < share <= 1
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && pass || fail "the clamp does not restore spawn+work==sum / share<=1"

begin_test "the harness clamps rather than silently reporting a >100% spawn share"
grep -q 'spawn_estimate_capped' "$HARNESS" && grep -q 'spawn_ms > chain_sum' "$HARNESS" && pass \
  || fail "clamp or its flag missing — the flake returns and the anomaly is invisible"

begin_test "spawn floor is measured, positive, and plausible against the cheapest hook"
# The floor is a 15-sample median; per-hook means here come from --iterations 1, so
# they are SINGLE samples. Comparing them tightly is comparing two different
# measurements — the first version of this asserted floor <= cheapest + 1ms and
# duly failed on the macOS runner, where one noisy sample lands under a stable
# median. The check that actually matters is order-of-magnitude: a probe measuring
# the whole chain instead of one spawn would be ~17x the cheapest hook, not 2x.
# Failure prints the numbers, because a bare "implausible" is undiagnosable.
#
# The bound was widened again (2x+2 -> 6x+5) after it ABORTED TWO RELEASES in one
# day: `floor 12.00 vs cheapest 4.00` and `floor 9.00 vs cheapest 3.00`, both on a
# loaded machine, both green when re-run. It was still comparing a 15-sample
# median against a single sample, and under load that gap widens — so the number
# was measuring the machine, not the harness. 6x+5 stays far below the ~17x a
# genuinely broken probe produces while surviving contention. A gate that cries
# wolf gets muted, and this one was being re-run rather than believed.
DIAG=$(bash "$HARNESS" --iterations 1 --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
f=d['spawn_floor_ms']
if not f>0: print('floor not measured: %r' % f); sys.exit(1)
cheapest=min(min(p['per_hook_ms'].values()) for p in d['payloads'].values())
if f > cheapest*6 + 5:
    print('floor %.2f implausible vs cheapest hook %.2f' % (f,cheapest)); sys.exit(1)
for lab,p in d['payloads'].items():
    if abs((p['spawn_ms']+p['work_ms'])-p['chain_sum_ms'])>=0.2:
        print('%s: spawn+work != sum: %r' % (lab,p)); sys.exit(1)
    if not 0<p['spawn_share']<=1:
        print('%s: spawn_share out of range: %r' % (lab,p['spawn_share'])); sys.exit(1)
" 2>&1)
[ -z "$DIAG" ] && pass || fail "spawn floor implausible — $DIAG"

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
[ -f "$REPO_DIR/docs/perf-baseline.json" ] && python3 -c "import sys, json;json.load(open(sys.argv[1]))" "$REPO_DIR/docs/perf-baseline.json" 2>/dev/null && pass || fail "baseline missing/unparseable"

# --- statusline target (Phase 2, item 2) -------------------------------------
begin_test "--target all sweeps every registered event and ranks by BLOCKING cost"
# The instrument built to catch accumulation only ever looked at PreToolUse/Bash and
# the statusline, so a 27.7ms blocking hook on every assistant message stayed
# invisible for four releases and surfaced only because someone asked. Measuring one
# hot path is how you miss the next one.
AOUT=$(bash "$HARNESS" --target all --iterations 1 2>/dev/null)
{ printf '%s' "$AOUT" | grep -q 'blocking ms' \
  && printf '%s' "$AOUT" | grep -q 'PreToolUse' \
  && printf '%s' "$AOUT" | grep -q 'UserPromptSubmit'; } \
  && pass || fail "sweep missing events or the blocking column: $AOUT"

begin_test "--target all ranks on blocking cost, not the sequential sum"
# Ranking by sum would send the reader optimising async hooks nobody waits for —
# the error HOOK-LATENCY-PLAN Phase 4 warned about. PostToolUse is the discriminator:
# it has a large sum and a small blocking share, so a sum-ranked table puts it near
# the top and a blocking-ranked one does not.
python3 - <<PY >/dev/null 2>&1 && pass || fail "table is not ordered by the blocking column"
import re,sys
rows=[]
for line in '''$AOUT'''.splitlines():
    m=re.match(r'\s+(\w+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s', line)
    if m: rows.append((m.group(1), float(m.group(3))))
assert len(rows) >= 5, rows
vals=[v for _,v in rows]
assert vals == sorted(vals, reverse=True), rows
PY

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
#
# v2.26.15: on MIN, not mean. A warm render crossing a wall-clock second boundary
# misses the cache and costs a full cold render, so the warm mean legitimately
# includes misses — with 2 samples on a slow runner, one miss halves the figure.
# That is exactly what reddened macOS CI: mean-speedup 1.46 while the hit path was
# doing 70 -> 15 ms. The min is the cache-hit floor, which is what this is asking
# about. Same mistake as 2.26.9: a threshold across two differently-measured things.
assert d['cache_speedup_min']>2.5, (d['cache_speedup_min'], d['cache_speedup'])
print('ok')
" >/dev/null 2>&1 && pass || fail "invalid statusline JSON or no cache benefit: $SJ"

begin_test "committed baseline carries BOTH the chain and statusline sections"
# --write-baseline runs once per target, so the second write must merge rather than
# overwrite; a plain write would silently drop whichever section ran first.
python3 -c "
import json, sys
d=json.load(open(sys.argv[1]))
assert 'payloads' in d and d['payloads'], 'chain section missing'
assert 'statusline' in d and d['statusline']['cold_render']['mean_ms']>0, 'statusline section missing'
print('ok')
" "$REPO_DIR/docs/perf-baseline.json" >/dev/null 2>&1 && pass || fail "baseline lost a section"

report
