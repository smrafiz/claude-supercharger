#!/usr/bin/env bash
# Claude Supercharger — Hook Performance Profiler
# Usage: bash tools/hook-perf.sh [--slow] [--days N] [--json]

set -euo pipefail

DAYS=1
SLOW=0
JSON=0
AUDIT_DIR="$HOME/.claude/supercharger/audit"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slow)       SLOW=1; shift ;;
    --json)       JSON=1; shift ;;
    --days|-d)    DAYS="$2"; shift 2 ;;
    --audit)      AUDIT_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash tools/hook-perf.sh [--slow] [--days N] [--json] [--audit DIR]"
      echo "  --slow        Only show hooks averaging >50ms"
      echo "  --days N      Lookback window in days (default: 1)"
      echo "  --json        Machine-readable JSON output"
      echo "  --audit DIR   Override audit directory"
      exit 0 ;;
    *) shift ;;
  esac
done

# Enable profiling sentinel for future hook invocations
PROFILING_FILE="$HOME/.claude/supercharger/scope/.profiling"
mkdir -p "$(dirname "$PROFILING_FILE")"
touch "$PROFILING_FILE"

# Clean up on exit
trap 'rm -f "$PROFILING_FILE"' EXIT

SUPERCHARGER_AUDIT_DIR="$AUDIT_DIR" \
SUPERCHARGER_DAYS="$DAYS" \
SUPERCHARGER_SLOW="$SLOW" \
SUPERCHARGER_JSON="$JSON" \
python3 << 'PYEOF'
import os, sys, json, glob, time
from collections import defaultdict

audit_dir = os.environ.get('SUPERCHARGER_AUDIT_DIR', '')
days      = int(os.environ.get('SUPERCHARGER_DAYS', '1'))
slow_only = os.environ.get('SUPERCHARGER_SLOW', '0') == '1'
json_out  = os.environ.get('SUPERCHARGER_JSON', '0') == '1'

cutoff = time.time() - days * 86400

# Accumulate: hook -> [elapsed_ms, ...]
totals = defaultdict(list)

if os.path.isdir(audit_dir):
    for path in glob.glob(os.path.join(audit_dir, '*.jsonl')):
        try:
            if os.path.getmtime(path) < cutoff:
                continue
        except OSError:
            continue
        try:
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                        hook = d.get('hook', '')
                        elapsed = d.get('elapsed_ms')
                        if hook and elapsed is not None:
                            totals[hook].append(float(elapsed))
                    except (json.JSONDecodeError, TypeError, ValueError):
                        pass
        except OSError:
            pass

if not totals:
    if json_out:
        print(json.dumps({
            "hooks": [],
            "total_overhead_s": 0,
            "total_calls": 0,
            "avg_per_call_ms": 0
        }))
    else:
        label = f"last {days} day{'s' if days != 1 else ''}"
        print(f"Hook Performance Report ({label})")
        print("No hook timing data found")
    sys.exit(0)

# Build rows
rows = []
for hook, samples in totals.items():
    calls    = len(samples)
    avg_ms   = sum(samples) / calls
    total_ms = sum(samples)
    total_s  = round(total_ms / 1000, 1)
    rows.append({
        "hook":    hook,
        "calls":   calls,
        "avg_ms":  round(avg_ms),
        "total_s": total_s,
        "_total_ms": total_ms,
    })

if slow_only:
    rows = [r for r in rows if r["avg_ms"] > 50]

rows.sort(key=lambda r: r["_total_ms"], reverse=True)

total_calls = sum(r["calls"] for r in rows)
total_ms    = sum(r["_total_ms"] for r in rows)
total_s     = round(total_ms / 1000, 1)
avg_per_call= round(total_ms / total_calls) if total_calls else 0

if json_out:
    out = {
        "hooks": [
            {"hook": r["hook"], "calls": r["calls"], "avg_ms": r["avg_ms"], "total_s": r["total_s"]}
            for r in rows
        ],
        "total_overhead_s": total_s,
        "total_calls":      total_calls,
        "avg_per_call_ms":  avg_per_call,
    }
    print(json.dumps(out))
    sys.exit(0)

# Text output
label = f"last {days} day{'s' if days != 1 else ''}"
W = max((len(r["hook"]) for r in rows), default=10)
W = max(W, 30)

SEP = "─" * (W + 30)
print()
print(f"Hook Performance Report ({label})")
print(SEP)
print(f"{'Hook':<{W}}  {'Calls':>6}  {'Avg(ms)':>8}  {'Total(s)':>9}")
print(SEP)

for r in rows:
    print(f"{r['hook']:<{W}}  {r['calls']:>6}  {r['avg_ms']:>8}  {r['total_s']:>9}")

print(SEP)
print(f"Total hook overhead: {total_s}s across {total_calls} calls (avg {avg_per_call}ms/call)")
print()
PYEOF
