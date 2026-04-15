#!/usr/bin/env bash
# Claude Supercharger — Enhanced Statusline
# Registered via: settings.json → statusLine → { type: "command", command: "..." }
# Reads JSON from stdin, outputs 2-line status bar.

set -euo pipefail

INPUT=$(cat)

SL_INPUT="$INPUT" python3 <<'PYEOF'
import json, subprocess, os, time

try:
 raw = os.environ.get('SL_INPUT', '') or '{}'
 data = json.loads(raw) if raw.strip() else {}
 if not isinstance(data, dict):
     data = {}

 model = (data.get('model') or {}).get('display_name', '?')
 cwd = (data.get('workspace') or {}).get('current_dir', data.get('cwd', '') or '')
 dirname = os.path.basename(cwd) if cwd else '?'

 cost_data = data.get('cost') or {}
 cost = cost_data.get('total_cost_usd', 0) or 0
 duration_ms = cost_data.get('total_duration_ms', 0) or 0
 lines_added = cost_data.get('total_lines_added', 0) or 0
 lines_removed = cost_data.get('total_lines_removed', 0) or 0
 mins = duration_ms // 60000
 secs = (duration_ms % 60000) // 1000

 ctx = data.get('context_window') or {}
 pct = int(ctx.get('used_percentage', 0) or 0)

 # Use official context_window_size if available (exact), else derive
 ctx_max = ctx.get('context_window_size', 0) or 0

 # Cumulative session totals
 session_input = ctx.get('total_input_tokens', 0) or 0
 session_output = ctx.get('total_output_tokens', 0) or 0

 # Current context usage (last API call)
 usage = ctx.get('current_usage') or {}
 cache_read = usage.get('cache_read_input_tokens', 0) or 0
 cache_create = usage.get('cache_creation_input_tokens', 0) or 0
 cache_total = cache_read + cache_create
 cache_pct = int((cache_read / cache_total * 100)) if cache_total > 0 else 0

 input_tok = usage.get('input_tokens', 0) or 0
 output_tok = usage.get('output_tokens', 0) or 0

 # Context used = input only (matches used_percentage calculation per docs)
 # used_percentage = input_tokens + cache_creation + cache_read
 ctx_used = input_tok + cache_read + cache_create

 # For display: show session cumulative in/out
 display_input = session_input if session_input > 0 else ctx_used
 display_output = session_output if session_output > 0 else output_tok

 # Fallback: derive max from percentage if not provided
 if ctx_max == 0 and pct > 0 and ctx_used > 0:
     ctx_max = int(ctx_used / (pct / 100))

 cache_saved = int(cache_read * 0.9) if cache_read > 0 else 0

 # Rate limits (Pro/Max subscribers only)
 rate_limits = data.get('rate_limits') or {}
 five_hour = rate_limits.get('five_hour') or {}
 seven_day = rate_limits.get('seven_day') or {}
 rl_5h_pct = five_hour.get('used_percentage', 0) or 0
 rl_5h_reset = five_hour.get('resets_at', 0) or 0
 rl_7d_pct = seven_day.get('used_percentage', 0) or 0

 # Colors
 CYAN = '\033[36m'
 GREEN = '\033[32m'
 YELLOW = '\033[33m'
 RED = '\033[31m'
 DIM = '\033[2m'
 BOLD = '\033[1m'
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

 # Stack detection — scoped by project directory hash
 stack = ''
 try:
     import hashlib
     proj_hash = hashlib.md5(cwd.encode()).hexdigest()[:8] if cwd else 'default'
     cache_path = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', f'.stack-cache-{proj_hash}')
     if os.path.isfile(cache_path):
         with open(cache_path) as f:
             cached = f.read().strip()
         if cached:
             stack = f' {DIM}|{RESET} ' + cached
     elif cwd:
         stack_parts = []
         pkg = os.path.join(cwd, 'package.json')
         if os.path.isfile(pkg):
             with open(pkg) as f:
                 pdata = json.load(f)
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

 session_id = data.get('session_id') or 'default'

 # Active agent
 agent = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     # Prefer native agent field, fallback to scope files
     native_agent = (data.get('agent') or {}).get('name', '')
     if native_agent:
         agent = f' {DIM}|{RESET} {CYAN}{native_agent}{RESET}'
     else:
         for fname in (f'.agent-dispatched-{session_id}', f'.agent-classified-{session_id}'):
             fpath = os.path.join(scope, fname)
             if os.path.isfile(fpath):
                 with open(fpath) as f:
                     agent_name = f.read().strip()
                 if agent_name:
                     agent = f' {DIM}|{RESET} {CYAN}{agent_name}{RESET}'
                     break
 except Exception:
     pass

 # Active MCP server
 mcp = ''
 try:
     mcp_path = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', f'.active-mcp-{session_id}')
     if os.path.isfile(mcp_path):
         mtime = os.path.getmtime(mcp_path)
         if time.time() - mtime < 60:
             with open(mcp_path) as f:
                 mcp_name = f.read().strip()
             if mcp_name:
                 mcp = f' {DIM}|{RESET} {GREEN}MCP: {mcp_name}{RESET}'
 except Exception:
     pass

 # Lines changed
 lines = ''
 if lines_added > 0 or lines_removed > 0:
     lines = f' {DIM}|{RESET} {GREEN}+{lines_added}{RESET}{DIM}/{RESET}{RED}-{lines_removed}{RESET}'

 # Line 1: Model, project, branch, stack, agent, mcp, lines
 line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}{stack}{agent}{mcp}{lines}'

 # Token display
 def fmt_tokens(n):
     if n >= 1_000_000:
         return f'{n/1_000_000:.1f}M'
     elif n >= 1_000:
         return f'{n/1_000:.1f}K'
     return str(n)

 # Context: used/max
 if ctx_max > 0:
     ctx_str = f'{fmt_tokens(ctx_used)}/{fmt_tokens(ctx_max)}'
 elif ctx_used > 0:
     ctx_str = fmt_tokens(ctx_used)
 else:
     ctx_str = ''

 # Token breakdown (session cumulative)
 if display_input > 0 or display_output > 0:
     tok_seg = f' {DIM}|{RESET} {fmt_tokens(display_input)} in {DIM}/{RESET} {fmt_tokens(display_output)} out'
 else:
     tok_seg = ''

 # Cache
 if cache_total == 0:
     cache_str = f'{DIM}cache: n/a{RESET}'
 elif cache_read == 0:
     cache_str = f'{DIM}cache: warming{RESET}'
 elif cache_saved > 0:
     cache_str = f'cache {cache_pct}% {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 else:
     cache_str = f'cache {cache_pct}%'

 # Rate limits (isolated — must not crash line 2)
 rl_str = ''
 try:
     if rl_5h_pct and float(rl_5h_pct) > 0:
         rl_color = RED if rl_5h_pct >= 80 else YELLOW if rl_5h_pct >= 50 else DIM
         reset_str = ''
         if rl_5h_reset and float(rl_5h_reset) > 0:
             remaining = max(0, int(float(rl_5h_reset) - time.time()))
             rh, rm = remaining // 3600, (remaining % 3600) // 60
             reset_str = f' {DIM}({rh}h{rm}m){RESET}' if rh > 0 else f' {DIM}({rm}m){RESET}'
         rl_str = f' {DIM}|{RESET} {DIM}limits{RESET} {rl_color}5hr {float(rl_5h_pct):.0f}% used{RESET}{reset_str}'
         if rl_7d_pct and float(rl_7d_pct) > 0:
             rl_str += f' {DIM}· 7day {float(rl_7d_pct):.0f}% used{RESET}'
 except Exception:
     rl_str = ''

 # Line 2: context bar + tokens
 cost_fmt = f'${cost:.2f}'
 pct_ctx = f'{pct}% ({ctx_str})' if ctx_str else f'{pct}%'
 line2 = f'{bar_color}{bar}{RESET} {DIM}ctx{RESET} {pct_ctx}{tok_seg} {DIM}|{RESET} {cache_str}'

 # Line 3: cost + duration + rate limits
 dur_str = f'{mins}h {secs}m' if mins >= 60 else f'{mins}m {secs}s'
 line3 = f'{DIM}cost{RESET} {YELLOW}{cost_fmt}{RESET} {DIM}|{RESET} {DIM}time{RESET} {dur_str}{rl_str}'

 print(line1)
 print(line2)
 print(line3)
except Exception as e:
 print(f'[statusline error: {e}]')
 print('')
 print('')
PYEOF
