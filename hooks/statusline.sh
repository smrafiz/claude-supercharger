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

input_tok = usage.get('input_tokens', 0) or 0
output_tok = usage.get('output_tokens', 0) or 0
total_tok = input_tok + output_tok

# Accumulate session totals (deduplicate re-renders)
session_tok_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.session-tokens')
session_in = 0
session_out = 0
last_in = 0
last_out = 0
try:
    if os.path.isfile(session_tok_file):
        with open(session_tok_file) as f:
            for line in f:
                k, v = line.strip().split('=', 1)
                if k == 'in': session_in = int(v)
                elif k == 'out': session_out = int(v)
                elif k == 'last_in': last_in = int(v)
                elif k == 'last_out': last_out = int(v)
    if input_tok != last_in or output_tok != last_out:
        session_in += input_tok
        session_out += output_tok
        with open(session_tok_file, 'w') as f:
            f.write(f'in={session_in}\nout={session_out}\nlast_in={input_tok}\nlast_out={output_tok}\n')
except Exception:
    session_in = input_tok
    session_out = output_tok
session_total = session_in + session_out

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

# Stack detection
stack = ''
try:
    if cwd:
        import json as _json
        stack_parts = []
        pkg = os.path.join(cwd, 'package.json')
        if os.path.isfile(pkg):
            with open(pkg) as f:
                pdata = _json.load(f)
            deps = {}
            deps.update(pdata.get('dependencies', {}))
            deps.update(pdata.get('devDependencies', {}))
            if 'typescript' in deps or os.path.isfile(os.path.join(cwd, 'tsconfig.json')):
                stack_parts.append('TypeScript')
            for fw, label in [('next','Next.js'),('react','React'),('vue','Vue'),('@angular/core','Angular'),('svelte','Svelte')]:
                if fw in deps:
                    stack_parts.append(label)
                    break
        elif os.path.isfile(os.path.join(cwd, 'requirements.txt')) or os.path.isfile(os.path.join(cwd, 'pyproject.toml')):
            stack_parts.append('Python')
        elif os.path.isfile(os.path.join(cwd, 'Cargo.toml')):
            stack_parts.append('Rust')
        elif os.path.isfile(os.path.join(cwd, 'go.mod')):
            stack_parts.append('Go')
        elif os.path.isfile(os.path.join(cwd, 'wp-config.php')) or os.path.isfile(os.path.join(cwd, 'functions.php')):
            stack_parts.append('WordPress')
        if stack_parts:
            stack = f' {DIM}|{RESET} ' + ', '.join(stack_parts)
except Exception:
    pass

# Active agent
agent = ''
try:
    route_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.agent-route')
    if os.path.isfile(route_file):
        with open(route_file) as f:
            agent_name = f.read().strip()
        if agent_name:
            agent = f' {DIM}|{RESET} {CYAN}Agent: {agent_name}{RESET}'
except Exception:
    pass

# Line 1: Model, project, git branch, stack, agent
line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}{stack}{agent}'

# Line 2: Context bar, cost, duration, cache hit rate
cost_fmt = f'\${cost:.2f}'

# Token display
def fmt_tokens(n):
    if n >= 1_000_000:
        return f'{n/1_000_000:.1f}M'
    elif n >= 1_000:
        return f'{n/1_000:.1f}K'
    return str(n)

tok_session = f'{fmt_tokens(session_total)}' if session_total > 0 else '0'
tok_prompt = f'{fmt_tokens(total_tok)}' if total_tok > 0 else '0'
tok_str = f' {DIM}|{RESET} session: {tok_session} tok {DIM}|{RESET} prompt: {tok_prompt} tok'

line2 = f'{bar_color}{bar}{RESET} {pct}% {DIM}|{RESET} {YELLOW}{cost_fmt}{RESET}{tok_str} {DIM}|{RESET} {mins}m {secs}s {DIM}|{RESET} cache {cache_pct}%'

print(line1)
print(line2)
" <<< "$INPUT"
