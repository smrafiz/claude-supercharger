#!/usr/bin/env bash
# Claude Supercharger — Enhanced Statusline
# Registered via: settings.json → statusLine → { type: "command", command: "..." }
# Reads JSON from stdin, outputs 2-line status bar.

set -euo pipefail

_INPUT=$(cat)
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"

SL_INPUT="$_INPUT" SL_LIB_DIR="$LIB_DIR" python3 <<'PYEOF'
import json, subprocess, os, sys, time
sys.path.insert(0, os.environ.get('SL_LIB_DIR', ''))

try:
 raw = os.environ.get('SL_INPUT', '') or '{}'
 try:
     data = json.loads(raw) if raw.strip() else {}
 except Exception:
     data = {}
 if not isinstance(data, dict):
     data = {}

 model = (data.get('model') or {}).get('display_name', '?')
 cwd = (data.get('workspace') or {}).get('current_dir', data.get('cwd', '') or '')
 dirname = os.path.basename(cwd) if cwd else '?'

 cost_data = data.get('cost') or {}
 cost = cost_data.get('total_cost_usd', 0) or 0
 duration_ms = cost_data.get('total_duration_ms', 0) or 0
 # v2.7.35: computed from the real uncommitted diff below (see git section),
 # NOT cost.total_lines_added/removed — that's CC's cumulative session edit
 # count, which never resets and reads misleadingly like a git stat.
 lines_added = 0
 lines_removed = 0
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

 # v2.7.35: real uncommitted diff (staged + unstaged vs HEAD) — current WIP size,
 # 0 when the tree is clean. Replaces CC's cumulative-session edit count.
 try:
     dr = subprocess.run(['git', 'diff', 'HEAD', '--numstat'],
                         capture_output=True, text=True, timeout=2, cwd=cwd or None)
     if dr.returncode == 0:
         for ln in dr.stdout.splitlines():
             p = ln.split('\t')
             if len(p) >= 2 and p[0].isdigit() and p[1].isdigit():
                 lines_added += int(p[0]); lines_removed += int(p[1])
 except Exception:
     pass

 # Stack detection — scoped by project directory hash
 stack = ''
 try:
     import hashlib
     from detect_stack import detect_stack
     proj_hash = hashlib.md5(cwd.encode()).hexdigest()[:8] if cwd else 'default'
     cache_path = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', f'.stack-cache-{proj_hash}')
     if os.path.isfile(cache_path):
         with open(cache_path) as f:
             cached = f.read().strip()
         if cached:
             stack = f' {DIM}|{RESET} ' + cached
     elif cwd:
         s = detect_stack(cwd)
         if s['detected']:
             parts = list(s['language'])
             if s['framework']:
                 parts.append(s['framework'][0])
             stack = f' {DIM}|{RESET} ' + ', '.join(parts)
 except Exception:
     pass

 session_id = data.get('session_id') or 'default'

 # Active agent — prefer supercharger classification over native CC agent type
 agent = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     agent_name = ''
     for fname in (f'.agent-dispatched-{session_id}', f'.agent-classified-{session_id}'):
         fpath = os.path.join(scope, fname)
         if os.path.isfile(fpath):
             with open(fpath) as f:
                 agent_name = f.read().strip()
             if agent_name:
                 break
     if not agent_name:
         # Fallback: native CC agent field (e.g. subagent context)
         agent_name = (data.get('agent') or {}).get('name', '')
     if agent_name:
         agent_name = ' '.join(w.capitalize() for w in agent_name.replace('-', ' ').replace('_', ' ').split())
         agent = f' {DIM}|{RESET} {DIM}Agent:{RESET} {CYAN}{agent_name}{RESET}'
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

 # Economy tier
 eco = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     tier_file = os.path.join(scope, '.economy-tier')
     tier_file_fresh = os.path.isfile(tier_file) and (time.time() - os.path.getmtime(tier_file) < 604800)  # 7 days
     if os.path.isfile(tier_file):
         with open(tier_file) as f:
             tier = f.read().strip().lower()
         if tier:
             eco = f' {DIM}|{RESET} {DIM}Eco: {tier.capitalize()}{RESET}'
     if not eco and not tier_file_fresh:
         # Fallback: scan economy.md — only if .economy-tier is missing or very stale
         economy_md = os.path.join(os.path.expanduser('~'), '.claude', 'rules', 'economy.md')
         if os.path.isfile(economy_md):
             with open(economy_md) as f:
                 for ln in f:
                     if ln.startswith('### Active Tier:'):
                         tier = ln.split(':', 1)[1].strip().split()[0]
                         eco = f' {DIM}|{RESET} {DIM}Eco: {tier}{RESET}'
                         break
 except Exception:
     pass

 # Memory restore indicator (shown 5 min after compaction)
 mem = ''
 try:
     mem_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.memory-restored')
     if os.path.isfile(mem_file):
         if time.time() - os.path.getmtime(mem_file) < 300:
             mem = f' {DIM}|{RESET} {CYAN}Mem: Restored{RESET}'
 except Exception:
     pass

 # Scan alert indicator (shown 2 min after scanner fires)
 scan = ''
 try:
     scan_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', f'.scan-alert-{session_id}')
     if os.path.isfile(scan_file):
         if time.time() - os.path.getmtime(scan_file) < 120:
             with open(scan_file) as f:
                 scan_type = f.read().strip().capitalize()
             scan = f' {DIM}|{RESET} \033[33m\u26a0 Scan: {scan_type}{RESET}'
 except Exception:
     pass

 # Line 1: Model, project, branch, stack, eco, mem, scan, agent, mcp, lines
 line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}{stack}{eco}{mem}{scan}{agent}{mcp}{lines}'

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

 # v2.7.35: dropped the "N in / N out" segment — `in` just duplicated the context
 # figure and `out` was a tiny low-signal number. Context bar + cache% cover it.
 tok_seg = ''

 # Cache health coloring
 if cache_total == 0:
     cache_str = f'{DIM}cache: n/a{RESET}'
 elif cache_read == 0:
     cache_str = f'{DIM}cache: warming{RESET}'
 elif cache_pct < 50:
     cache_str = f'{RED}cache {cache_pct}%{RESET} {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 elif cache_pct < 70:
     cache_str = f'{YELLOW}cache {cache_pct}%{RESET} {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 elif cache_saved > 0:
     cache_str = f'cache {cache_pct}% {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 else:
     cache_str = f'cache {cache_pct}%'

 # v2.7.37: per-session token + cost totals for the unified line-3 block. Main
 # tokens from budget-cap's .main-tokens-<session>; sub tokens+cost from
 # .subagent-costs-<session> (deduped by agent_id, new-tokens basis).
 _main_tok = 0
 _sub_tok = 0
 _sub_cost = 0.0
 try:
     _scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     _mtf = os.path.join(_scope, f'.main-tokens-{session_id}')
     if os.path.isfile(_mtf):
         with open(_mtf) as _f:
             _main_tok = int((json.load(_f) or {}).get('new_tokens', 0) or 0)
     _stf = os.path.join(_scope, f'.subagent-costs-{session_id}.jsonl')
     if os.path.isfile(_stf):
         _by = {}
         with open(_stf) as _f:
             for _ln in _f:
                 _ln = _ln.strip()
                 if not _ln:
                     continue
                 try:
                     _r = json.loads(_ln)
                 except Exception:
                     continue
                 _aid = _r.get('agent_id', '?')
                 _c = float(_r.get('cost_usd', 0) or 0)
                 _nw = (int(_r.get('input_tokens', 0) or 0) + int(_r.get('cache_write_tokens', 0) or 0)
                        + int(_r.get('output_tokens', 0) or 0)) or int(_r.get('total_tokens', 0) or 0)
                 if _aid not in _by or _c >= _by[_aid][0]:
                     _by[_aid] = (_c, _nw)
         _sub_tok = sum(_t for _c, _t in _by.values())
         _sub_cost = sum(_c for _c, _t in _by.values())
 except Exception:
     pass

 # Rate limits (isolated — must not crash line 2)
 rl_str = ''
 try:
     if rl_5h_pct and float(rl_5h_pct) > 0:
         rl_color = RED if rl_5h_pct >= 80 else YELLOW if rl_5h_pct >= 50 else DIM
         reset_label = ''
         if rl_5h_reset and float(rl_5h_reset) > 0:
             remaining = max(0, int(float(rl_5h_reset) - time.time()))
             rh, rm = remaining // 3600, (remaining % 3600) // 60
             reset_label = f' (resets: {rh}h {rm}m)' if rh > 0 else f' (resets: {rm}m)'
         # Burn rate projection
         burn_proj = ''
         try:
             scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
             cost_file = os.path.join(scope, '.session-cost')
             if os.path.isfile(cost_file) and float(rl_5h_pct) > 0:
                 with open(cost_file) as f:
                     sc = json.load(f)
                 start_str = sc.get('first_updated', '') or sc.get('last_updated', '')
                 if start_str:
                     import calendar
                     st = calendar.timegm(time.strptime(start_str, '%Y-%m-%dT%H:%M:%SZ'))
                     elapsed = (time.time() - st) / 60
                     if elapsed >= 5:
                         burn = float(rl_5h_pct) / elapsed
                         if burn > 0:
                             ttx = int((100 - float(rl_5h_pct)) / burn)
                             if ttx < 120:
                                 burn_proj = f' · ~{ttx}m left at this pace'
         except Exception:
             burn_proj = ''
         rl_str = f' {DIM}|{RESET} {rl_color}Session: {float(rl_5h_pct):.0f}%{reset_label}{burn_proj}{RESET}'
         if rl_7d_pct and float(rl_7d_pct) > 0:
             rl_str += f' {DIM}· Weekly: {float(rl_7d_pct):.0f}%{RESET}'
 except Exception:
     rl_str = ''

 # Plan-aware cost label.
 # Auto-detect: Anthropic API users have no weekly limit — only subscribers do.
 # If rl_7d_pct > 0, this is a subscriber (Max/Pro/Team) and the cost line is
 # API-equivalent burn, not invoiced. Override via .supercharger.json:
 #   {"plan": "max"|"pro"|"team"|"subscription"} → forces equiv label
 #   {"plan": "api"}                             → forces Cost label
 cost_label = 'Cost:'
 cost_suffix = ''
 _plan_override = ''
 try:
     _search = cwd or os.getcwd()
     for _ in range(5):
         _cfg = os.path.join(_search, '.supercharger.json')
         if os.path.isfile(_cfg):
             with open(_cfg) as _f:
                 _plan_override = (json.load(_f).get('plan') or '').lower()
             break
         _parent = os.path.dirname(_search)
         if _parent == _search:
             break
         _search = _parent
 except Exception:
     pass

 _is_subscriber = False
 if _plan_override == 'api':
     _is_subscriber = False
 elif _plan_override in ('max', 'pro', 'team', 'subscription'):
     _is_subscriber = True
 else:
     try:
         _is_subscriber = float(rl_7d_pct or 0) > 0
     except Exception:
         _is_subscriber = False

 if _is_subscriber:
     cost_label = 'Tokens:'
     cost_suffix = ' equiv'

 # Line 2: context bar + tokens
 cost_fmt = f'${cost:.2f}{cost_suffix}'
 pct_ctx = f'{pct}% ({ctx_str})' if ctx_str else f'{pct}%'
 # Duration (v2.7.37: on line 2 now, alongside context/cache/rate-limits)
 if mins >= 60:
     dur_str = f'{mins // 60}h {mins % 60}m'
 else:
     dur_str = f'{mins}m {secs}s'

 # Line 2 — "where am I": context, cache, elapsed time, rate limits.
 # v2.7.38: line 2 = context | time | cache; rate limits (Session/Weekly) move to line 3.
 line2 = f'{bar_color}{bar}{RESET} {DIM}Context:{RESET} {pct_ctx} {DIM}|{RESET} {DIM}Time:{RESET} {dur_str} {DIM}|{RESET} {cache_str}'

 # Budget cap display (cost line)
 budget_str = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     cost_file = os.path.join(scope, '.session-cost')
     if os.path.isfile(cost_file):
         with open(cost_file) as f:
             sc = json.load(f)
         sc_cost = sc.get('total_usd', 0)
         cap = float(os.environ.get('SESSION_BUDGET_CAP', '0') or '0')
         if cap > 0:
             budget_str = f' {DIM}|{RESET} {DIM}Budget:{RESET} {YELLOW}${sc_cost:.2f}/${cap:.2f}{RESET}'
 except Exception:
     budget_str = ''

 # v2.7.37: unified line 3 — Claude + subagents, tokens AND cost together, with
 # the combined total. `equiv` (plan-equivalent $) is shown once, on the total.
 # CC does not fold subagent spend into its parent cost, so main + sub is a true
 # sum. Main tokens come from budget-cap's per-session accumulator (0 until it
 # runs a turn, then climbs).
 _tcost = cost + _sub_cost
 _ttok = _main_tok + _sub_tok
 if _sub_tok > 0 or _sub_cost > 0:
     line3 = (f'{DIM}{cost_label}{RESET} {DIM}main{RESET} {fmt_tokens(_main_tok)}{DIM}/{RESET}{YELLOW}${cost:.2f}{RESET}'
              f' {DIM}· sub{RESET} {fmt_tokens(_sub_tok)}{DIM}/{RESET}{YELLOW}${_sub_cost:.2f}{RESET}'
              f' {DIM}· total{RESET} {fmt_tokens(_ttok)}{DIM}/{RESET}{YELLOW}${_tcost:.2f}{cost_suffix}{RESET}{budget_str}{rl_str}')
 else:
     line3 = f'{DIM}{cost_label}{RESET} {fmt_tokens(_main_tok)}{DIM}/{RESET}{YELLOW}${cost:.2f}{cost_suffix}{RESET}{budget_str}{rl_str}'

 print(line1)
 try:
     print(line2)
 except Exception:
     print('')
 try:
     print(line3)
 except Exception:
     print('')
except Exception as e:
 print(f'[statusline error: {e}]')
 print('')
 print('')
 print('')
PYEOF
