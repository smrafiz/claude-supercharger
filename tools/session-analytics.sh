#!/usr/bin/env bash
# Claude Supercharger — Session Analytics
# Usage: bash tools/session-analytics.sh [--days N] [--projects PATH]

set -euo pipefail

DAYS=7
PROJECTS_DIR="$HOME/.claude/projects"
SCOPE_DIR="$HOME/.claude/supercharger/scope"
SHOW_SUBAGENTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days|-d)       DAYS="$2"; shift 2 ;;
    --projects|-p)   PROJECTS_DIR="$2"; shift 2 ;;
    --subagents|-s)  SHOW_SUBAGENTS=true; shift ;;
    --help|-h)
      echo "Usage: bash tools/session-analytics.sh [--days N] [--projects PATH] [--subagents]"
      echo "  --days N        Lookback window in days (default: 7)"
      echo "  --projects PATH Override projects directory (default: ~/.claude/projects/)"
      echo "  --subagents     Show per-agent cost breakdown from subagent JSONL data"
      exit 0 ;;
    *) shift ;;
  esac
done

SESSION_SKIP=false
if [ ! -d "$PROJECTS_DIR" ]; then
  if [ "$SHOW_SUBAGENTS" = false ]; then
    echo "No session data found"
    exit 0
  fi
  SESSION_SKIP=true
fi

# Collect all JSONL files across all project dirs (maxdepth 1 per project = skip subagent subdirs)
FILE_LIST=""
if [ "$SESSION_SKIP" = false ]; then
  while IFS= read -r -d '' proj_dir; do
    proj_slug=$(basename "$proj_dir")
    while IFS= read -r -d '' f; do
      FILE_LIST="${FILE_LIST}${proj_slug}|${f}"$'\n'
    done < <(find "$proj_dir" -maxdepth 1 -name "*.jsonl" -not -empty -print0 2>/dev/null)
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

if [ -z "$FILE_LIST" ] && [ "$SHOW_SUBAGENTS" = false ]; then
  echo "No session data found"
  exit 0
fi

if [ -n "$FILE_LIST" ]; then
SUPERCHARGER_FILE_LIST="$FILE_LIST" SUPERCHARGER_DAYS="$DAYS" python3 << 'PYEOF'
import os, json, sys, time
from datetime import datetime

PRICE = {
    'input':       3.00,
    'cache_write': 3.75,
    'cache_read':  0.30,
    'output':     15.00,
}

days      = int(os.environ.get('SUPERCHARGER_DAYS', '7'))
file_raw  = os.environ.get('SUPERCHARGER_FILE_LIST', '')
cutoff    = time.time() - days * 86400

def slug_to_name(slug):
    path = slug.replace('-', '/')
    return os.path.basename(path.rstrip('/')) or slug

def parse_session(path):
    t = dict(input=0, cache_write=0, cache_read=0, output=0, turns=0)
    ts_start = ''
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
                            inp  = u.get('input_tokens', 0)
                            cw   = u.get('cache_creation_input_tokens', 0)
                            cr   = u.get('cache_read_input_tokens', 0)
                            out  = u.get('output_tokens', 0)
                            if inp + cw + cr + out > 0:
                                t['input']       += inp
                                t['cache_write'] += cw
                                t['cache_read']  += cr
                                t['output']      += out
                                t['turns']       += 1
                except:
                    pass
    except:
        pass
    return t, ts_start

def total_cost(t):
    return (t['input']       / 1e6 * PRICE['input'] +
            t['cache_write'] / 1e6 * PRICE['cache_write'] +
            t['cache_read']  / 1e6 * PRICE['cache_read'] +
            t['output']      / 1e6 * PRICE['output'])

def cache_savings(t):
    return t['cache_read'] / 1e6 * (PRICE['input'] - PRICE['cache_read'])

def cache_pct(t):
    denom = t['cache_read'] + t['input']
    return int(t['cache_read'] / denom * 100) if denom > 0 else 0

def ts_to_date(ts):
    if not ts:
        return 'unknown'
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00')).strftime('%Y-%m-%d')
    except:
        return ts[:10]

def new_row():
    return dict(input=0, cache_write=0, cache_read=0, output=0, turns=0, sessions=0, cost=0.0, saved=0.0)

def add_to(row, t, cost, saved):
    for k in ('input', 'cache_write', 'cache_read', 'output', 'turns'):
        row[k] += t[k]
    row['sessions'] += 1
    row['cost']     += cost
    row['saved']    += saved

by_date    = {}
by_project = {}

for line in file_raw.splitlines():
    line = line.strip()
    if not line or '|' not in line:
        continue
    slug, path = line.split('|', 1)
    try:
        if os.path.getmtime(path) < cutoff:
            continue
    except OSError:
        continue
    t, ts_start = parse_session(path)
    if t['turns'] == 0:
        continue
    date = ts_to_date(ts_start)
    name = slug_to_name(slug)
    cost = total_cost(t)
    saved = cache_savings(t)
    if date not in by_date:
        by_date[date] = new_row()
    add_to(by_date[date], t, cost, saved)
    if name not in by_project:
        by_project[name] = new_row()
    add_to(by_project[name], t, cost, saved)

# Grand totals (sum from by_date to avoid double-count)
grand = new_row()
for r in by_date.values():
    for k in ('input', 'cache_write', 'cache_read', 'output', 'turns', 'sessions'):
        grand[k] += r[k]
    grand['cost']  += r['cost']
    grand['saved'] += r['saved']

if grand['sessions'] == 0:
    print('No session data found')
    sys.exit(0)

label = f"last {days} day{'s' if days != 1 else ''}"

# ── Section 1: Daily Rollup ──────────────────────────────────────────
print()
print(f"  Daily Summary — {label}")
print(f"  {'─'*55}")
print(f"  {'Date':<12}  {'Sessions':>8}   {'Turns':>5}    {'Cost':>6}  {'Saved':>7}   {'Cache%':>6}")
print(f"  {'─'*11}  {'─'*8}   {'─'*5}    {'─'*6}  {'─'*7}   {'─'*6}")

for date in sorted(by_date.keys(), reverse=True):
    r   = by_date[date]
    pct = cache_pct(r)
    print(f"  {date:<12}  {r['sessions']:>8}   {r['turns']:>5}    ${r['cost']:>5.2f}  ${r['saved']:>6.2f}   {pct:>5}%")

print(f"  {'─'*11}  {'─'*8}   {'─'*5}    {'─'*6}  {'─'*7}   {'─'*6}")
print(f"  {'TOTAL':<12}  {grand['sessions']:>8}   {grand['turns']:>5}    ${grand['cost']:>5.2f}  ${grand['saved']:>6.2f}   {cache_pct(grand):>5}%")
print()

# ── Section 2: Per-Project Breakdown ────────────────────────────────
if not by_project:
    sys.exit(0)

W = max((len(n) for n in by_project), default=10) + 2
W = max(W, 20)

print(f"  Per-Project — {label}")
print(f"  {'─'*(W + 42)}")
print(f"  {'Project':<{W}}  {'Sessions':>8}   {'Turns':>5}    {'Cost':>6}   {'Cache%':>6}")
print(f"  {'─'*W}  {'─'*8}   {'─'*5}    {'─'*6}   {'─'*6}")

for name in sorted(by_project.keys(), key=lambda n: by_project[n]['cost'], reverse=True):
    r   = by_project[name]
    pct = cache_pct(r)
    print(f"  {name:<{W}}  {r['sessions']:>8}   {r['turns']:>5}    ${r['cost']:>5.2f}   {pct:>5}%")

print(f"  {'─'*W}  {'─'*8}   {'─'*5}    {'─'*6}   {'─'*6}")
print(f"  {'TOTAL':<{W}}  {grand['sessions']:>8}   {grand['turns']:>5}    ${grand['cost']:>5.2f}   {cache_pct(grand):>5}%")
print()
PYEOF
fi  # end: if FILE_LIST non-empty

if [ "$SHOW_SUBAGENTS" = true ]; then
  SUPERCHARGER_SCOPE_DIR="$SCOPE_DIR" python3 << 'SUBPYEOF'
import os, json, glob, sys
from collections import defaultdict

scope_dir = os.environ.get('SUPERCHARGER_SCOPE_DIR', '')
pattern   = os.path.join(scope_dir, '.subagent-costs-*.jsonl')
files     = glob.glob(pattern)

if not files:
    print("  No subagent data found")
    sys.exit(0)

agents = defaultdict(lambda: dict(calls=0, tokens=0, cost_usd=0.0, duration_s=0.0))

for fpath in files:
    try:
        with open(fpath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    name = d.get('agent_name') or d.get('agent_id', 'unknown')
                    agents[name]['calls']      += 1
                    agents[name]['tokens']     += d.get('tokens', 0)
                    agents[name]['cost_usd']   += d.get('cost_usd', 0.0)
                    agents[name]['duration_s'] += d.get('duration_s', 0.0)
                except:
                    pass
    except:
        pass

if not agents:
    print("  No subagent data found")
    sys.exit(0)

W = max((len(n) for n in agents), default=10) + 2
W = max(W, 14)

def fmt_tokens(n):
    return f"{n//1000}K" if n >= 1000 else str(n)

print()
print(f"  Subagent Cost Breakdown")
print(f"  {'─'*(W + 42)}")
print(f"  {'Agent':<{W}}  {'Calls':>5}   {'Tokens':>7}    {'Cost':>7}   {'Avg Time':>8}")
print(f"  {'─'*W}  {'─'*5}   {'─'*7}    {'─'*7}   {'─'*8}")

total_calls = 0
total_tokens = 0
total_cost = 0.0

for name in sorted(agents.keys(), key=lambda n: agents[n]['cost_usd'], reverse=True):
    r    = agents[name]
    avg  = r['duration_s'] / r['calls'] if r['calls'] else 0
    tok  = fmt_tokens(r['tokens'])
    total_calls  += r['calls']
    total_tokens += r['tokens']
    total_cost   += r['cost_usd']
    print(f"  {name:<{W}}  {r['calls']:>5}   {tok:>7}    ${r['cost_usd']:>6.2f}   {avg:>7.0f}s")

print(f"  {'─'*W}  {'─'*5}   {'─'*7}    {'─'*7}   {'─'*8}")
print(f"  {'Total':<{W}}  {total_calls:>5}   {fmt_tokens(total_tokens):>7}    ${total_cost:>6.2f}")
print()
SUBPYEOF
fi
