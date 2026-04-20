#!/usr/bin/env bash
# Claude Supercharger — Session Token Report
# Usage: bash tools/token-report.sh [--sessions N] [--project PATH]
# Shows token breakdown and cost for recent sessions.

set -euo pipefail

SESSIONS=5
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sessions|-n) SESSIONS="$2"; shift 2 ;;
    --project|-p)  PROJECT_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash tools/token-report.sh [--sessions N] [--project PATH]"
      echo "  --sessions N    Show last N sessions (default: 5)"
      echo "  --project PATH  Project dir to report on (default: current dir)"
      exit 0 ;;
    *) shift ;;
  esac
done

[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(pwd)"

PROJECT_SLUG=$(printf '%s' "$PROJECT_DIR" | tr '/' '-')
SESSION_DIR="$HOME/.claude/projects/$PROJECT_SLUG"

if [ ! -d "$SESSION_DIR" ]; then
  echo "No session data found for: $PROJECT_DIR"
  echo "Expected: $SESSION_DIR"
  exit 1
fi

# Top-level JSONL only (exclude subagent dirs), sorted by mtime
JSONL_FILES=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -not -empty 2>/dev/null \
  | xargs ls -t 2>/dev/null \
  | head -"$SESSIONS")

if [ -z "$JSONL_FILES" ]; then
  echo "No session files found in $SESSION_DIR"
  exit 1
fi

SUPERCHARGER_JSONL_FILES="$JSONL_FILES" python3 << 'PYEOF'
import os, json
from datetime import datetime

PRICE = {
    'input':        3.00,
    'cache_write':  3.75,
    'cache_read':   0.30,
    'output':      15.00,
}

files = [l.strip() for l in os.environ.get('SUPERCHARGER_JSONL_FILES', '').split('\n') if l.strip()]

def parse_session(path):
    totals = dict(input=0, cache_write=0, cache_read=0, output=0, turns=0)
    ts_start = model = ''
    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                    ts = d.get('timestamp', '')
                    if ts and not ts_start:
                        ts_start = ts
                    if d.get('type') == 'assistant':
                        u = d.get('message', {}).get('usage', {})
                        if u:
                            totals['input']       += u.get('input_tokens', 0)
                            totals['cache_write'] += u.get('cache_creation_input_tokens', 0)
                            totals['cache_read']  += u.get('cache_read_input_tokens', 0)
                            totals['output']      += u.get('output_tokens', 0)
                            totals['turns']       += 1
                            if not model:
                                model = d.get('message', {}).get('model', '')
                except Exception:
                    pass
    except Exception:
        pass
    return totals, ts_start, model

def total_cost(t):
    return (t['input'] / 1e6 * PRICE['input'] +
            t['cache_write'] / 1e6 * PRICE['cache_write'] +
            t['cache_read']  / 1e6 * PRICE['cache_read'] +
            t['output']      / 1e6 * PRICE['output'])

def cache_savings(t):
    return t['cache_read'] / 1e6 * (PRICE['input'] - PRICE['cache_read'])

def fmtk(n):
    if n >= 1_000_000: return f'{n/1_000_000:.1f}M'
    if n >= 1_000:     return f'{n/1_000:.0f}k'
    return str(n)

def fmtd(ts):
    if not ts: return '?'
    try: return datetime.fromisoformat(ts.replace('Z','+00:00')).strftime('%m-%d %H:%M')
    except: return ts[:16]

W = 36
print()
print(f"  {'Session':<{W}}  {'Date':<12}  {'Turns':>5}  {'Input':>7}  {'CacheW':>7}  {'CacheR':>8}  {'Output':>7}  {'Cost':>7}  {'Saved':>7}")
print(f"  {'-'*W}  {'-'*12}  {'-'*5}  {'-'*7}  {'-'*7}  {'-'*8}  {'-'*7}  {'-'*7}  {'-'*7}")

agg = dict(input=0, cache_write=0, cache_read=0, output=0, turns=0)
agg_cost = agg_saved = 0.0

for path in files:
    t, ts, model = parse_session(path)
    if t['turns'] == 0:
        continue
    sid = os.path.basename(path).replace('.jsonl', '')[:W]
    c = total_cost(t)
    s = cache_savings(t)
    print(f"  {sid:<{W}}  {fmtd(ts):<12}  {t['turns']:>5}  {fmtk(t['input']):>7}  {fmtk(t['cache_write']):>7}  {fmtk(t['cache_read']):>8}  {fmtk(t['output']):>7}  ${c:>6.2f}  ${s:>6.2f}")
    for k in agg: agg[k] += t[k]
    agg_cost  += c
    agg_saved += s

print(f"  {'-'*W}  {'-'*12}  {'-'*5}  {'-'*7}  {'-'*7}  {'-'*8}  {'-'*7}  {'-'*7}  {'-'*7}")
print(f"  {'TOTAL':<{W}}  {'':12}  {agg['turns']:>5}  {fmtk(agg['input']):>7}  {fmtk(agg['cache_write']):>7}  {fmtk(agg['cache_read']):>8}  {fmtk(agg['output']):>7}  ${agg_cost:>6.2f}  ${agg_saved:>6.2f}")

cache_pct = agg['cache_read'] / max(agg['cache_read'] + agg['input'], 1) * 100
print()
print(f"  Cache hit rate : {cache_pct:.0f}% of input served from cache")
print(f"  Cache savings  : ${agg_saved:.2f} (would cost ${agg_cost + agg_saved:.2f} without caching)")
print()
PYEOF
