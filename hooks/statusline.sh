#!/usr/bin/env bash
# Claude Supercharger — Enhanced Statusline
# Registered via: settings.json → statusLine → { type: "command", command: "..." }
# Reads JSON from stdin, outputs 2-line status bar.

set -euo pipefail

# v2.9.2: honor the global kill-switch. When `/sc off` deactivates Supercharger,
# render NOTHING so the status bar looks like plain Claude Code. The statusLine
# command is re-run each turn, so this takes effect immediately; `/sc on` (removes
# the flag) brings the statusline back on the next render. This is why the toggle
# doesn't need to touch the settings.json statusLine key.
# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

[ -f "$SUPERCHARGER_STATE/scope/.supercharger-disabled" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"

# --- v2.23.45: whole-line render cache -------------------------------------
# Measured: a render costs ~45ms, and it is almost entirely INTERPRETER STARTUP
# (bash + one python3) — not work; the expensive git lookups are already cached
# ~3s inside the python. Claude Code re-runs the statusLine on a 300ms debounce,
# so a burst pays that startup 3-4x/second for a line that barely changes.
# Serve a cached line within the same wall-clock second: repeat renders skip
# python entirely (~45ms -> ~10ms). Worst-case staleness is <1s on a status
# display whose git data is already 3s-stale by design.
# Everything here is a bash builtin — no fork on the cache-hit path, or the
# cache would cost as much as it saves. Fail-open: any problem renders normally.
# Extract "key": "value" tolerating any whitespace after the colon (json.dumps
# emits `"k": "v"`, compact encoders emit `"k":"v"` — must handle both). All
# parameter expansion: no subshell, since $(...) would fork and defeat the point.
_SL_SID=""; _SL_CWD=""
_SL_R="${_INPUT#*\"session_id\"}"
if [ "$_SL_R" != "$_INPUT" ]; then
  _SL_R="${_SL_R#*:}"; _SL_R="${_SL_R#"${_SL_R%%[![:space:]]*}"}"
  case "$_SL_R" in \"*) _SL_R="${_SL_R#\"}"; _SL_SID="${_SL_R%%\"*}" ;; esac
fi
_SL_R="${_INPUT#*\"cwd\"}"
if [ "$_SL_R" != "$_INPUT" ]; then
  _SL_R="${_SL_R#*:}"; _SL_R="${_SL_R#"${_SL_R%%[![:space:]]*}"}"
  case "$_SL_R" in \"*) _SL_R="${_SL_R#\"}"; _SL_CWD="${_SL_R%%\"*}" ;; esac
fi
# $EPOCHSECONDS is fork-free (bash 5+); `date` is one cheap fork on bash 3.2.
_SL_NOW="${EPOCHSECONDS:-}"; [ -z "$_SL_NOW" ] && _SL_NOW=$(date +%s 2>/dev/null || echo 0)
_SL_STAMP="${_SL_NOW}|${_SL_CWD}"
_SL_CACHE=""
case "$_SL_SID" in
  ''|*[!A-Za-z0-9._-]*) : ;;                       # no/unsafe session id -> no cache
  *) _SL_CACHE="$SUPERCHARGER_STATE/scope/.statusline-cache-$_SL_SID" ;;
esac
if [ -n "$_SL_CACHE" ] && [ -r "$_SL_CACHE" ]; then
  _SL_ALL=""
  IFS= read -r -d '' _SL_ALL < "$_SL_CACHE" 2>/dev/null || true
  if [ -n "$_SL_ALL" ] && [ "${_SL_ALL%%$'\n'*}" = "$_SL_STAMP" ]; then
    printf '%s' "${_SL_ALL#*$'\n'}"
    exit 0
  fi
fi

_SL_OUT=$(SL_INPUT="$_INPUT" SL_LIB_DIR="$LIB_DIR" python3 <<'PYEOF' || true
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

 # v2.7.42 perf: the branch + uncommitted-diff (2 git forks, ~37ms) run on EVERY
 # render — including CC's rapid refresh timer. Cache them in a per-repo scope
 # file. The diff can't key on .git mtime (unstaged edits don't touch it), so the
 # key includes a ~3s time bucket: recompute at most once per bucket, serve cached
 # values to the intervening renders. Staleness is bounded at ~3s (fine for a WIP
 # gauge); branch is always fresh (HEAD mtime is in the key too).
 branch = ''
 import time as _t
 try:
     _gdir = os.path.join(cwd or '.', '.git')
     _sig = []
     for _f in ('HEAD', 'index'):
         try: _sig.append(str(int(os.path.getmtime(os.path.join(_gdir, _f)))))
         except Exception: pass
     _key = '|'.join(_sig) + '|' + str(int(_t.time()) // 3)
     _cf = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope',
                        '.statusline-git-' + __import__('hashlib').md5((cwd or '.').encode()).hexdigest()[:8])
     _cached = None
     try:
         with open(_cf) as _f:
             _c = json.load(_f)
         if _c.get('key') == _key:
             _cached = _c
     except Exception:
         _cached = None
     if _cached is not None:
         _br = _cached.get('branch', '')
         if _br:
             branch = f' {DIM}|{RESET} {_br}'
         lines_added += int(_cached.get('added', 0) or 0)
         lines_removed += int(_cached.get('removed', 0) or 0)
     else:
         _br = ''
         try:
             _r = subprocess.run(['git', 'branch', '--show-current'],
                                 capture_output=True, text=True, timeout=2, cwd=cwd or None)
             if _r.returncode == 0:
                 _br = _r.stdout.strip()
         except Exception:
             pass
         _add = _rem = 0
         try:
             _dr = subprocess.run(['git', 'diff', 'HEAD', '--numstat'],
                                  capture_output=True, text=True, timeout=2, cwd=cwd or None)
             if _dr.returncode == 0:
                 for _ln in _dr.stdout.splitlines():
                     _p = _ln.split('\t')
                     if len(_p) >= 2 and _p[0].isdigit() and _p[1].isdigit():
                         _add += int(_p[0]); _rem += int(_p[1])
         except Exception:
             pass
         if _br:
             branch = f' {DIM}|{RESET} {_br}'
         lines_added += _add; lines_removed += _rem
         try:
             with open(_cf + '.tmp', 'w') as _f:
                 json.dump({'key': _key, 'branch': _br, 'added': _add, 'removed': _rem}, _f)
             os.replace(_cf + '.tmp', _cf)
         except Exception:
             pass
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

 # Memory restore indicator (shown 5 min after compaction). v2.7.47: per-session
 # file — a global one lit the badge in every concurrent session, not just the
 # one that actually compacted.
 mem = ''
 try:
     mem_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', f'.memory-restored-{session_id}')
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

 # Autopilot indicator — time-boxed auto-approve window (/sc-autopilot).
 # Shown while active (global or this-session flag) so an open window is never silent.
 auto = ''
 try:
     _ap_scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     _ap_files = [os.path.join(_ap_scope, '.autopilot-until')]
     if session_id:
         _ap_files.append(os.path.join(_ap_scope, f'.autopilot-until-{session_id}'))
     _ap_now = int(time.time())
     _ap_best = 0
     for _apf in _ap_files:
         try:
             with open(_apf) as f:
                 _u = int((f.read().strip() or '0'))
         except Exception:
             continue
         if _u - _ap_now > _ap_best:
             _ap_best = _u - _ap_now
     if _ap_best > 0:
         auto = f' {DIM}|{RESET} \033[33m⚡ Autopilot: {_ap_best // 60}m left{RESET}'
 except Exception:
     pass

 # Read-only indicator — time-boxed "look, don't touch" window (/sc-readonly).
 ro = ''
 try:
     _ro_scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     _ro_files = [os.path.join(_ro_scope, '.readonly-until')]
     if session_id:
         _ro_files.append(os.path.join(_ro_scope, f'.readonly-until-{session_id}'))
     _ro_now = int(time.time())
     _ro_best = 0
     for _rof in _ro_files:
         try:
             with open(_rof) as f:
                 _u = int((f.read().strip() or '0'))
         except Exception:
             continue
         if _u - _ro_now > _ro_best:
             _ro_best = _u - _ro_now
     if _ro_best > 0:
         ro = f' {DIM}|{RESET} \033[33m🔒 Read-only: {_ro_best // 60}m left{RESET}'
 except Exception:
     pass

 # Strict-mode indicator — time-boxed "ask me everything" window (/sc-strict).
 st = ''
 try:
     _st_scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     _st_files = [os.path.join(_st_scope, '.strict-until')]
     if session_id:
         _st_files.append(os.path.join(_st_scope, f'.strict-until-{session_id}'))
     _st_now = int(time.time())
     _st_best = 0
     for _stf in _st_files:
         try:
             with open(_stf) as f:
                 _u = int((f.read().strip() or '0'))
         except Exception:
             continue
         if _u - _st_now > _st_best:
             _st_best = _u - _st_now
     if _st_best > 0:
         st = f' {DIM}|{RESET} \033[33m🛡 Strict: {_st_best // 60}m left{RESET}'
 except Exception:
     pass

 # Line 1: Model, project, branch, stack, eco, mem, scan, autopilot, read-only, strict, agent, mcp, lines
 line1 = f'{CYAN}[{model}]{RESET} {dirname}{branch}{stack}{eco}{mem}{scan}{auto}{ro}{st}{agent}{mcp}{lines}'

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
                 # v2.7.39: content tokens = input + output (exclude ALL cache),
                 # same basis as main. Legacy rows w/o breakdown fall back to total.
                 _nw = (int(_r.get('input_tokens', 0) or 0) + int(_r.get('output_tokens', 0) or 0)) \
                       or int(_r.get('total_tokens', 0) or 0)
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
)
[ -n "$_SL_OUT" ] || exit 0
printf '%s\n' "$_SL_OUT"
# Store for the rest of this wall-clock second. Write to a temp then mv, so a
# concurrent render never reads a half-written line. Failures are ignored.
if [ -n "$_SL_CACHE" ]; then
  { printf '%s\n%s\n' "$_SL_STAMP" "$_SL_OUT" > "$_SL_CACHE.$$" && mv -f "$_SL_CACHE.$$" "$_SL_CACHE"; } 2>/dev/null \
    || rm -f "$_SL_CACHE.$$" 2>/dev/null || true
fi
