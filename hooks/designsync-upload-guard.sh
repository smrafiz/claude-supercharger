#!/usr/bin/env bash
# Claude Supercharger — DesignSync Upload Guard
# Event: PreToolUse | Matcher: DesignSync
#
# DesignSync had no guards — found by the coverage-diff sweep that also produced
# the Monitor bypass (v2.29.7) and the RemoteTrigger gap (v2.29.8). It is an
# egress primitive and belongs to the family that already covers every other one:
#   artifact-publish-guard   Artifact
#   bulk-exfil-guard         Bash,Monitor,PowerShell
#   mcp-egress-guard         mcp__*
#   sendmessage-guard        SendMessage
#   webfetch-egress-guard    WebFetch
#
# It is the WORST case in that family, for a reason stated in the tool's own
# description: write_files takes a `localPath`, and the tool "reads from disk,
# encodes, and uploads" so that "contents never enter your context". Every other
# secret check we own runs on text that passed through the session — output
# scanners, the commit guard, the artifact guard. This content does not. If a
# .env or a private key is uploaded here, there is no other layer that could
# notice, because nothing ever sees the bytes.
#
# So the check reads the file itself, exactly as artifact-publish-guard does for
# the file it is about to publish, and DENIES on a credential match. Deny rather
# than warn, for the same asymmetry: an upload to a shared project is not
# reversible by us, and other org members can read it.
#
# Scope is deliberately narrow — only write_files, the one method that moves
# local bytes outward. The read methods (list_projects, get_project, list_files,
# get_file) send nothing and are untouched, as are finalize_plan and the asset
# registration calls.
#
# NOT covered here, and not implied to be: delete_files removes files from a
# shared remote project, which is destructive but not exfiltration. Left for a
# separate decision rather than folded in silently.
#
# Disable: SUPERCHARGER_DESIGNSYNC_GUARD=0

set -euo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
check_hook_disabled "designsync-upload-guard" 2>/dev/null && exit 0
[ "${SUPERCHARGER_DESIGNSYNC_GUARD:-1}" = "0" ] && exit 0

# Fork-free stdin read (v2.26.35 convention).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Fast path: only write_files moves bytes outward.
case "$_INPUT" in *write_files*) ;; *) exit 0 ;; esac

# Single source of truth, shared with output-secrets-scanner, commit-guard and
# artifact-publish-guard. Add a pattern THERE, never here (v2.9.8 parity drift).
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || true
_DS_PATTERNS=$(printf '%s\n' "${SECRET_PATTERNS[@]:-}" 2>/dev/null || true)

RESULT=$(HOOK_INPUT="$_INPUT" PATTERNS="$_DS_PATTERNS" python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys

# NOTE: this heredoc lives inside RESULT=$(...). Keep every quote character
# MATCHED in this body or bash misses the PYEOF terminator and parses the rest as
# shell -- see hooks/workflow-guard.sh for the measured write-up.
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)

ti = data.get('tool_input') or {}
if ti.get('method') != 'write_files':
    sys.exit(0)

files = ti.get('files')
if not isinstance(files, list) or not files:
    sys.exit(0)

pats = []
for p in (os.environ.get('PATTERNS') or '').splitlines():
    p = p.strip()
    if not p:
        continue
    try:
        pats.append(re.compile(p))
    except re.error:
        continue
if not pats:
    sys.exit(0)

cwd = data.get('cwd') or (data.get('workspace') or {}).get('current_dir') or os.getcwd()
localdir = ti.get('localDir') or cwd

MAX_BYTES = 262144      # same bound artifact-publish-guard uses
MAX_FILES = 128         # see the unscanned-tail branch below

def hit(text):
    return any(r.search(text) for r in pats)

flagged = None
scanned = 0

for ent in files[:MAX_FILES]:
    if not isinstance(ent, dict):
        continue
    # Inline content still passes through the session, but scan it anyway so the
    # two shapes of the same call cannot disagree about what counts as a secret.
    d = ent.get('data')
    if isinstance(d, str) and ent.get('encoding') != 'base64' and hit(d):
        flagged = (ent.get('path') or 'inline data', 'inline data')
        break

    lp = ent.get('localPath')
    if not isinstance(lp, str) or not lp:
        continue
    full = lp if os.path.isabs(lp) else os.path.join(localdir, lp)
    try:
        with open(full, 'rb') as fh:
            blob = fh.read(MAX_BYTES)
    except Exception:
        continue                      # unreadable or absent - fail open
    scanned += 1
    if hit(blob.decode('utf-8', 'replace')):
        flagged = (ent.get('path') or lp, full)
        break

def emit(decision, reason):
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': decision,
        'permissionDecisionReason': reason,
    }}))

if flagged:
    remote, local = flagged
    emit('deny',
         'Refusing to upload %s: it contains what looks like a credential. '
         'DesignSync reads this file straight from disk and uploads it, so its '
         'contents never pass through the session - no output scanner, commit '
         'guard or artifact check can see them, and this hook is the only layer '
         'that could notice. The project is readable by other org members and '
         'the upload is not reversible from here. Remove the secret, or exclude '
         'the file from the plan.' % local)
    sys.exit(0)

# No silent caps: if the call carries more entries than were scanned, say so
# rather than return a clean verdict that only covered part of the batch.
if len(files) > MAX_FILES:
    emit('ask',
         'This DesignSync call uploads %d files; only the first %d were scanned '
         'for credentials. The rest were not checked, and their contents never '
         'enter the session, so nothing else will check them either. Confirm you '
         'want to upload the unscanned remainder.' % (len(files), MAX_FILES))
PYEOF
) || RESULT=""

if [ -n "$RESULT" ]; then
  printf '%s\n' "$RESULT"
  case "$RESULT" in
    *'"deny"'*)
      SCOPE_DIR="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}/scope"
      mkdir -p "$SCOPE_DIR" 2>/dev/null || true
      printf '[%s] credentials — secret in DesignSync upload — write_files\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        >> "$SCOPE_DIR/.blocked-commands" 2>/dev/null || true
      ;;
  esac
fi
exit 0
