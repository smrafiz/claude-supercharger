#!/usr/bin/env bash
# Claude Supercharger — Enhanced Statusline
# Registered via: settings.json → statusLine → { type: "command", command: "..." }
# Reads JSON from stdin, outputs 2-line status bar.

set -euo pipefail

INPUT=$(cat)

SL_INPUT="$INPUT" python3 <<'PYEOF'
import json, sys, subprocess, os

try:
 data = json.loads(os.environ.get('SL_INPUT', '{}'))

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

 # Total context = all input tokens (cached + uncached) + output tokens
 # input_tokens only counts non-cached; cache_read + cache_create are the rest
 all_input = input_tok + cache_read + cache_create
 total_tok = all_input + output_tok

 # Derive max context window from percentage
 ctx_used = total_tok
 ctx_max = int(ctx_used / (pct / 100)) if pct > 0 else 0

 # Cache savings: cache_read tokens cost ~10x less than regular input
 cache_saved = int(cache_read * 0.9) if cache_read > 0 else 0


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

 # Stack detection — read from cache written by project-config.sh (SessionStart)
 stack = ''
 try:
     cache_path = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.stack-cache')
     if os.path.isfile(cache_path):
         with open(cache_path) as f:
             cached = f.read().strip()
         if cached:
             stack = f' {DIM}|{RESET} ' + cached
     elif cwd:
         # Fallback: inline detection when cache is absent
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

 # Active agent — prefer .agent-dispatched (actual dispatch) over .agent-classified (router guess)
 agent = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     agent_name = ''
     for fname in ('.agent-dispatched', '.agent-classified'):
         fpath = os.path.join(scope, fname)
         if os.path.isfile(fpath):
             with open(fpath) as f:
                 agent_name = f.read().strip()
             if agent_name:
                 break
     if agent_name:
         agent = f' {DIM}|{RESET} {CYAN}Agent: {agent_name}{RESET}'
 except Exception:
     pass

 # Line 1: Model, project, git branch, stack, agent
 line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}{stack}{agent}'

 # Line 2: Context bar, tokens, cost, duration, cache
 cost_fmt = f'${cost:.2f}'

 # Token display
 def fmt_tokens(n):
     if n >= 1_000_000:
         return f'{n/1_000_000:.1f}M'
     elif n >= 1_000:
         return f'{n/1_000:.1f}K'
     return str(n)

 # Context: used/total tokens
 if ctx_max > 0:
     ctx_str = f'{fmt_tokens(ctx_used)}/{fmt_tokens(ctx_max)}'
 elif ctx_used > 0:
     ctx_str = fmt_tokens(ctx_used)
 else:
     ctx_str = ''

 # Token breakdown: input (all) + output
 if total_tok > 0:
     tok_seg = f' {DIM}|{RESET} {fmt_tokens(all_input)} in {DIM}/{RESET} {fmt_tokens(output_tok)} out'
 else:
     tok_seg = ''

 # Cache: hit rate + tokens saved
 if cache_total == 0:
     cache_str = f'{DIM}cache: n/a{RESET}'
 elif cache_read == 0:
     cache_str = f'{DIM}cache: warming{RESET}'
 elif cache_saved > 0:
     cache_str = f'cache {cache_pct}% {DIM}(saved ~{fmt_tokens(cache_saved)}){RESET}'
 else:
     cache_str = f'cache {cache_pct}%'

 # Line 2: bar pct (used/max) | in / out | $cost | Xm Ys | cache
 pct_ctx = f'{pct}% ({ctx_str})' if ctx_str else f'{pct}%'
 line2 = f'{bar_color}{bar}{RESET} {pct_ctx}{tok_seg} {DIM}|{RESET} {YELLOW}{cost_fmt}{RESET} {DIM}|{RESET} {mins}m {secs}s {DIM}|{RESET} {cache_str}'

 print(line1)
 print(line2)
except Exception as e:
 print(f'[statusline error: {e}]')
 print('')
PYEOF
