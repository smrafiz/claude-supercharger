#!/usr/bin/env bash
# Claude Supercharger — Enhanced Statusline
# Registered via: settings.json → statusLine → { type: "command", command: "..." }
# Reads JSON from stdin, outputs 2-line status bar.

set -euo pipefail

INPUT=$(cat)

python3 -c "
import json, sys, subprocess, os

data = json.loads(sys.stdin.read())

model = data.get('model', {}).get('display_name', '?')
cwd = data.get('workspace', {}).get('current_dir', data.get('cwd', ''))
dirname = os.path.basename(cwd) if cwd else '?'

cost = data.get('cost', {}).get('total_cost_usd', 0) or 0
duration_ms = data.get('cost', {}).get('total_duration_ms', 0) or 0
mins = duration_ms // 60000
secs = (duration_ms % 60000) // 1000

ctx = data.get('context_window', {})
pct = int(ctx.get('used_percentage', 0) or 0)

usage = ctx.get('current_usage', {})
cache_read = usage.get('cache_read_input_tokens', 0) or 0
cache_create = usage.get('cache_creation_input_tokens', 0) or 0
cache_total = cache_read + cache_create
cache_pct = int((cache_read / cache_total * 100)) if cache_total > 0 else 0

# Colors
CYAN = '\033[36m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RED = '\033[31m'
DIM = '\033[2m'
RESET = '\033[0m'

if pct >= 90:
    bar_color = RED
elif pct >= 70:
    bar_color = YELLOW
else:
    bar_color = GREEN

filled = pct // 5
empty = 20 - filled
bar = '\u2588' * filled + '\u2591' * empty

# Git branch
branch = ''
try:
    result = subprocess.run(['git', 'branch', '--show-current'],
                          capture_output=True, text=True, timeout=2)
    if result.returncode == 0 and result.stdout.strip():
        branch = f' {DIM}|{RESET} {result.stdout.strip()}'
except Exception:
    pass

# Line 1: Model, project, git branch
line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}'

# Line 2: Context bar, cost, duration, cache hit rate
cost_fmt = f'\${cost:.2f}'
line2 = f'{bar_color}{bar}{RESET} {pct}% {DIM}|{RESET} {YELLOW}{cost_fmt}{RESET} {DIM}|{RESET} {mins}m {secs}s {DIM}|{RESET} cache {cache_pct}%'

print(line1)
print(line2)
" <<< "$INPUT"
