#!/usr/bin/env bash
# Claude Supercharger — File Lease (concurrent-session write guard)
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit
# Advisory guard for the concurrent-edit half of the scope-file-session-scoping
# bug class: two live Claude sessions editing the SAME project file collide.
# On each Write/Edit, this records the caller as the lease-holder for that file.
# If a *different* live session holds a fresh lease on it, the caller gets a
# non-blocking additionalContext warning ("another session is editing X") so the
# model can wait or move on — it never denies (fail-safe, advisory only).
# Leases expire after SUPERCHARGER_FILE_LEASE_TTL seconds (default 900), so a
# crashed/ended session never locks a file forever.
# Disable: SUPERCHARGER_FILE_LEASE=0

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_FILE_LEASE:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
LEASE_DIR="$SCOPE_DIR/.file-leases"
mkdir -p "$LEASE_DIR" 2>/dev/null || true

# One python fork: parse payload, resolve abspath, read/refresh the lease, and
# emit the warning envelope only on a live peer conflict. All failure paths
# fail-open (exit 0, no output): missing session_id/file_path, malformed JSON, IO.
OUT=$(printf '%s\n' "$_INPUT" | LEASE_DIR="$LEASE_DIR" TTL="${SUPERCHARGER_FILE_LEASE_TTL:-900}" PYTHONUTF8=1 python3 -S -c "
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

lease_dir = os.environ['LEASE_DIR']
try:
    ttl = int(os.environ.get('TTL', '900') or 900)
except Exception:
    ttl = 900
now = int(time.time())
key = hashlib.sha256(abspath.encode('utf-8', 'replace')).hexdigest()[:32]
lease = os.path.join(lease_dir, key)

holder, ts = '', 0
try:
    with open(lease) as f:
        holder, _, raw = f.read().strip().partition('\t')
    ts = int(raw or 0)
except Exception:
    holder, ts = '', 0

conflict = bool(holder) and holder != sid and (now - ts) < ttl

# Refresh the lease to the current caller (atomic replace).
try:
    tmp = lease + '.tmp.' + sid
    with open(tmp, 'w') as f:
        f.write('%s\t%d' % (sid, now))
    os.replace(tmp, lease)
except Exception:
    pass

if conflict:
    ago = max(0, (now - ts)) // 60
    when = 'just now' if ago == 0 else ('%dm ago' % ago)
    msg = ('[LEASE] %s is being edited by another active Claude session '
           '(lease held %s). Concurrent edits may collide — consider waiting or '
           'editing a different file.' % (os.path.basename(abspath), when))
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': msg}}))
    print(msg, file=sys.stderr)
" 2>/dev/null)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
exit 0
