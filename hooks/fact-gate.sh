#!/usr/bin/env bash
# Claude Supercharger — Fact Gate (first-touch investigation gate)
# Event: PreToolUse | Matcher: Edit,Write,MultiEdit,NotebookEdit
# OPT-IN, default OFF. On the FIRST edit of a given file in a session it denies
# ONCE with a demand to state facts — who imports/calls this file, the affected
# APIs/schemas, and the user's verbatim instruction — forcing a pause before a
# blind first edit, then allows the retry. Subsequent edits of the same file
# pass silently. Per-session, sha-keyed, TTL-expiring. Fully fail-open.
#
# Distinct from confidence-gate (probabilistic score from tool history) and
# human-approval-gate (asks the USER): this is a deterministic first-touch
# investigation gate that makes Claude recite context before it edits.
#
# Enable:  SUPERCHARGER_FACT_GATE=1   (default: unset/0 → this hook exits at once)
# TTL:     SUPERCHARGER_FACT_GATE_TTL (default 1800s — re-demand after 30 min)

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# Default OFF — this is a friction feature, opt-in only. Zero cost otherwise.
[ "${SUPERCHARGER_FACT_GATE:-0}" = "1" ] || exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
SCOPE_DIR="$SUPERCHARGER_STATE/scope"

OUT=$(printf '%s\n' "$_INPUT" | SCOPE_DIR="$SCOPE_DIR" TTL="${SUPERCHARGER_FACT_GATE_TTL:-1800}" PYTHONUTF8=1 python3 -c "
import sys, json, os, re, time, hashlib

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

sid = re.sub(r'[^a-zA-Z0-9_-]', '', str(d.get('session_id') or ''))[:64]
ti = d.get('tool_input') or {}
fp = ti.get('file_path') or ti.get('notebook_path') or ''
if not sid or not fp:
    sys.exit(0)

cwd = d.get('cwd') or os.getcwd()
try:
    abspath = os.path.normpath(fp if os.path.isabs(fp) else os.path.join(cwd, fp))
except Exception:
    sys.exit(0)

# Exempt Supercharger/Claude control files — gating config or memory writes is noise.
base = os.path.basename(abspath)
low = abspath.replace('\\\\', '/').lower()
if ('/.claude/' in low or base in ('.supercharger.json', 'settings.json', 'settings.local.json')
        or '/supercharger/scope/' in low or low.endswith('supercharger-memory.md')):
    sys.exit(0)

scope_dir = os.environ['SCOPE_DIR']
try:
    ttl = int(os.environ.get('TTL', '1800') or 1800)
except Exception:
    ttl = 1800
now = int(time.time())
gate_dir = os.path.join(scope_dir, '.fact-gate-' + sid)
key = hashlib.sha256(abspath.encode('utf-8', 'replace')).hexdigest()[:32]
marker = os.path.join(gate_dir, key)

# Already gated this file this session and still fresh -> allow silently.
try:
    ts = int(os.stat(marker).st_mtime)
    if (now - ts) < ttl:
        sys.exit(0)
except Exception:
    pass

# First touch (or stale): stamp the marker so the retry passes, then deny once.
try:
    os.makedirs(gate_dir, exist_ok=True)
    with open(marker, 'w') as f:
        f.write(str(now))
except Exception:
    # Can't persist the marker -> can't guarantee the retry passes -> fail-open.
    sys.exit(0)

msg = ('[FACT-GATE] First edit of ' + base + ' this session. Before editing, state: '
       '(1) what imports/calls this file and what breaks if its contract changes, '
       '(2) the APIs/types/schemas this change touches, '
       '(3) the user\'s request in their own words. '
       'Then re-issue the same edit — it will proceed.')
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'deny',
    'permissionDecisionReason': msg,
}}))
print(msg, file=sys.stderr)
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
# permissionDecision:deny must exit 2 so CC blocks the tool and surfaces the reason.
exit 2
