#!/usr/bin/env bash
# Claude Supercharger — Perf report (HOOK-LATENCY-PLAN Phase 3)
#
# Takes fresh perf-chain.sh measurements and the committed baseline, and emits a
# markdown table of the numbers with deltas. REPORT-ONLY by design: it never fails
# on a slow reading.
#
# That is deliberate and the plan says so (§6). GitHub runners vary enough that an
# absolute ms ceiling produces false failures and gets muted within a month, which
# is worse than no gate at all. Start by making the number visible; add a gate once
# there is enough history to know the noise floor.
#
# What it DOES fail on is a measurement that did not happen — a missing or
# unparseable input. A perf job that silently reports nothing is the same failure
# this project keeps finding: an instrument that says "fine" because it never ran.
#
# Usage:
#   bash tools/perf-report.sh --chain <chain.json> [--statusline <sl.json>]
#                             [--baseline docs/perf-baseline.json]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAIN=""; SL=""; BASELINE="$REPO/docs/perf-baseline.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --chain) CHAIN="$2"; shift 2 ;;
    --statusline) SL="$2"; shift 2 ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$CHAIN" ] || { echo "ERROR: --chain <file> is required" >&2; exit 2; }

CHAIN="$CHAIN" SL="$SL" BASELINE="$BASELINE" python3 <<'PY'
import json, os, sys

def load(path, what):
    if not path:
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        print("ERROR: %s measurement unusable (%s): %s" % (what, path, e), file=sys.stderr)
        print("       Refusing to report a perf run that did not produce numbers.", file=sys.stderr)
        sys.exit(1)

chain = load(os.environ["CHAIN"], "chain")
sl    = load(os.environ["SL"], "statusline")
base  = load(os.environ["BASELINE"], "baseline") if os.path.exists(os.environ["BASELINE"]) else None

if not chain.get("payloads"):
    print("ERROR: chain measurement has no payloads — the harness ran but measured nothing.",
          file=sys.stderr)
    sys.exit(1)

out = []
w = out.append
w("## Hook latency\n")

here = chain.get("platform", "?")
there = (base or {}).get("platform")
cross = bool(there and there != here)
if cross:
    w("> Baseline was recorded on **%s**, this run is **%s**. Deltas across platforms are "
      "indicative only — the runner difference is larger than any regression would be.\n" % (there, here))

def delta(now, was):
    if was in (None, 0):
        return "—"
    pct = (now - was) / was * 100.0
    mark = " ⚠" if abs(pct) >= 25 and not cross else ""
    return "%+.0f%%%s" % (pct, mark)

w("### PreToolUse / %s — %d hooks\n" % (chain.get("tool", "?"), chain.get("hooks", 0)))
w("| payload | felt (parallel) | chain sum (CPU) | spawn | hook work | slowest hook | vs baseline (felt) |")
w("|---|---:|---:|---:|---:|---|---:|")
for label, p in chain["payloads"].items():
    b = ((base or {}).get("payloads") or {}).get(label, {})
    w("| %s | %.1f ms | %.1f ms | %.1f ms | %.1f ms | `%s` @ %.1f ms | %s |" % (
        label, p["parallel_est_ms"], p["chain_sum_ms"],
        p.get("spawn_ms", 0.0), p.get("work_ms", 0.0),
        p["slowest_hook"], p["slowest_ms"],
        delta(p["parallel_est_ms"], b.get("parallel_est_ms"))))
if chain.get("spawn_floor_ms"):
    w("\n<sub>spawn = %.2f ms × %d hooks — starting bash and exiting, before a hook runs a line. "
      "It is the floor for hook *count*, not hook content; optimising a hook can only recover the "
      "`hook work` column.</sub>" % (chain["spawn_floor_ms"], chain.get("hooks", 0)))

if sl:
    bs = (base or {}).get("statusline", {})
    w("\n### Statusline render\n")
    w("| render | mean | min | max | vs baseline |")
    w("|---|---:|---:|---:|---:|")
    for key, lab in (("cold_render", "cold (cache miss)"), ("warm_render", "warm (cache hit)")):
        d, bd = sl[key], bs.get(key, {})
        w("| %s | %.1f ms | %.1f ms | %.1f ms | %s |" % (
            lab, d["mean_ms"], d["min_ms"], d["max_ms"], delta(d["mean_ms"], bd.get("mean_ms"))))
    if "cache_speedup" in sl:
        w("\nCache speedup: **%.2fx**" % sl["cache_speedup"])

w("\n<sub>Report-only — this job does not fail on a slow reading. "
  "felt = list-scheduling estimate over concurrent hooks; chain sum = fork/CPU pressure. "
  "Regenerate the baseline deliberately: `bash tests/perf-chain.sh --write-baseline`</sub>")

text = "\n".join(out)
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a") as f:
        f.write(text + "\n")
PY
