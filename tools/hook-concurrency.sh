#!/usr/bin/env bash
# Claude Supercharger — Hook concurrency reconstructor
#
# Answers one question for a given event: do its hooks run in PARALLEL, and how
# wide? That decides whether the event's cost is the SUM (what the chain harness
# reports) or the SPAN (what a user actually waits through).
#
# It matters because the two differ by multiples. HOOK-LATENCY-PLAN §3b measured
# PreToolUse this way and found parallel execution at width ~11 — turning a 5059 ms
# sum into a 1597 ms span. That measurement was a one-off; every other event has
# been reasoned about using PreToolUse's answer, which is an assumption, not a
# result. This makes the method repeatable.
#
# Method (no hook is modified — this reads the shipped instrumentation):
#   1. Full profiling must be on, so every fire is recorded, not just >40ms ones.
#   2. Trigger the event for real, inside Claude Code. Nothing else reproduces the
#      dispatcher's own scheduling — running the hooks from a script measures a
#      script, not Claude Code.
#   3. Each audit record gives {hook, elapsed_ms, ts}, so the interval is
#      [ts - elapsed_ms, ts]. Overlap between intervals is concurrency.
#
# Usage: bash tools/hook-concurrency.sh <Event> [--since <epoch_ms>] [--date YYYY-MM-DD]
set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SUPERCHARGER_STATE:=$HOME/.claude/supercharger}"

EVENT="${1:-}"; shift || true
SINCE=0
DATE=$(date +%Y-%m-%d)
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --date)  DATE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$EVENT" ] || { echo "usage: bash tools/hook-concurrency.sh <Event> [--since <epoch_ms>] [--date YYYY-MM-DD]" >&2; exit 2; }

AUDIT="$SUPERCHARGER_STATE/audit/${DATE}.jsonl"
if [ ! -f "$AUDIT" ]; then
  echo "ABORT: no audit log at $AUDIT" >&2
  exit 3
fi

EVENT="$EVENT" AUDIT="$AUDIT" SINCE="$SINCE" REPO="$REPO" python3 <<'PY'
import json, os, sys

event, audit, since = os.environ["EVENT"], os.environ["AUDIT"], int(os.environ["SINCE"])

reg = json.load(open(os.path.join(os.environ["REPO"], "hooks", "hooks.json")))
entries = reg["hooks"].get(event)
if not entries:
    print("ABORT: %s is not registered in hooks.json" % event, file=sys.stderr)
    sys.exit(3)
want, blocking = set(), set()
for e in entries:
    for h in e.get("hooks", []):
        name = h["command"].split("/hooks/")[-1].split()[0].replace(".sh", "")
        want.add(name)
        if not (h.get("async") or h.get("asyncRewake")):
            blocking.add(name)

rows = []
for line in open(audit, errors="replace"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if "hook" not in r or "elapsed_ms" not in r:
        continue
    if r["hook"] in want and r["ts"] >= since:
        rows.append(r)

if not rows:
    print("ABORT: no timing records for %s in %s." % (event, audit), file=sys.stderr)
    print("       Full profiling must be ON (the >40ms threshold hides these hooks", file=sys.stderr)
    print("       entirely) and the event must have fired since --since.", file=sys.stderr)
    sys.exit(3)

# One fire per hook: if the event fired several times, keep the most recent burst.
# Mixing bursts would invent overlap that never happened.
rows.sort(key=lambda r: r["ts"])
latest = {}
for r in rows:
    latest[r["hook"]] = r
iv = sorted(((r["ts"] - r["elapsed_ms"], r["ts"], r["hook"]) for r in latest.values()))

pairs = overlaps = 0
for i in range(len(iv)):
    for j in range(i + 1, len(iv)):
        pairs += 1
        if iv[i][1] > iv[j][0]:
            overlaps += 1

edges = []
for s, e, _ in iv:
    edges.append((s, 1)); edges.append((e, -1))
edges.sort()
cur = width = 0
for _, d in edges:
    cur += d
    width = max(width, cur)

span = max(e for _, e, _ in iv) - min(s for s, _, _ in iv)
total = sum(e - s for s, e, _ in iv)
btotal = sum(e - s for s, e, n in iv if n in blocking)

print("Hook concurrency — %s   (%d hooks recorded of %d registered)" % (event, len(iv), len(want)))
print("")
print("  overlapping interval pairs   %d / %d" % (overlaps, pairs))
print("  wall-clock span              %d ms   <- what a user waits" % span)
print("  sum of elapsed               %d ms   <- what sequential would cost" % total)
print("  of that, blocking hooks      %d ms" % btotal)
print("  max concurrency (width)      %d" % width)
if span > 0:
    print("  speedup vs serial            %.1fx" % (total / span))
print("")
print("  %-34s %8s %8s" % ("hook", "start", "ms"))
base = min(s for s, _, _ in iv)
for s, e, n in iv:
    print("  %-34s %+8d %8d%s" % (n, s - base, e - s, "" if n in blocking else "  (async)"))
print("")
if width <= 1:
    print("SEQUENTIAL: no two hooks overlapped. The sum IS the felt cost for this event.")
else:
    print("PARALLEL at width %d. Felt cost is the SPAN (%d ms), not the sum (%d ms)." % (width, span, total))
print("Absolute ms are inflated: profiling forks python twice per hook to timestamp.")
print("The STRUCTURE — parallel or not, and how wide — is the finding; the ms are not.")
PY
