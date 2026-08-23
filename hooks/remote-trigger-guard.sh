#!/usr/bin/env bash
# Claude Supercharger — Remote Trigger (cloud routine) Guard
# Event: PreToolUse | Matcher: RemoteTrigger
#
# RemoteTrigger had NO guards at all — found by the coverage-diff sweep that also
# found the Monitor shell bypass (v2.29.7). It is the cloud sibling of the Cron*
# tools, which DO have a hook (cron-discovery), so this was a straight parity
# gap: we guarded the local scheduler and left the remote one open.
#
# What makes it worth a guard rather than a discovery log is the consequence.
# Every other channel Supercharger protects executes HERE, where our PreToolUse
# hooks run. A routine created through this tool executes LATER, in the cloud,
# with repository access and the user's OAuth token attached in-process — where
# not one Supercharger guard runs. Creating one is therefore a decision to move
# work outside the enforcement layer entirely, and that is the user's call to
# make, not the agent's.
#
# Two checks, both parity with guards that already exist on other channels:
#
# (A) CREDENTIALS INTO A PERSISTED CLOUD OBJECT -> deny. The routine body holds
#     the prompt and config the cloud run will use, and it is STORED remotely,
#     so a secret here outlives the session that leaked it. Same shared
#     SECRET_PATTERNS list as sendmessage-guard and output-secrets-scanner —
#     one list, or the channels drift on what counts as a secret.
#
# (B) AUTONOMOUS EXECUTION OUTSIDE THE HARNESS -> ask. create, update, run and
#     create_webhook_trigger each cause code to run unattended later.
#     create_webhook_trigger is called out separately in the reason text because
#     it wires an EXTERNAL event source (a GitHub event, say) to fire the
#     routine: after that, something outside this machine decides when the agent
#     runs. The read actions (list, get, list_runs, get_run_log) inspect state
#     and are passed through untouched.
#
# Behavior: deny on (A), ask on (B), passthrough otherwise. Never blocks reads.
# Disable: SUPERCHARGER_REMOTE_TRIGGER_GUARD=0

set -euo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
check_hook_disabled "remote-trigger-guard" 2>/dev/null && exit 0
[ "${SUPERCHARGER_REMOTE_TRIGGER_GUARD:-1}" = "0" ] && exit 0

# Fork-free stdin read (v2.26.35 convention).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Secret patterns come from the shared list, never a local copy.
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || true
_RT_PATTERNS=$(printf '%s\n' "${SECRET_PATTERNS[@]:-}" 2>/dev/null || true)

RESULT=$(HOOK_INPUT="$_INPUT" PATTERNS="$_RT_PATTERNS" python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys

# NOTE: this heredoc lives inside RESULT=$(...). Keep every quote character
# MATCHED in this body or bash misses the PYEOF terminator and parses the rest as
# shell -- see hooks/workflow-guard.sh for the measured write-up.
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)

ti = data.get('tool_input') or {}
action = ti.get('action')
if not isinstance(action, str) or not action:
    sys.exit(0)

READ_ONLY = {'list', 'get', 'list_runs', 'get_run_log'}
MUTATING = {'create', 'update', 'run', 'create_webhook_trigger'}

if action in READ_ONLY:
    sys.exit(0)

# ── (A) credentials into a stored cloud object ────────────────────────────────
# Scan the whole body as text: the routine prompt, environment hints and any
# nested filter all end up persisted server-side.
body = ti.get('body')
haystack = ''
if body is not None:
    try:
        haystack = json.dumps(body, ensure_ascii=False)
    except Exception:
        haystack = str(body)

hits = []
for pat in (os.environ.get('PATTERNS') or '').splitlines():
    pat = pat.strip()
    if not pat:
        continue
    try:
        if re.search(pat, haystack):
            hits.append(pat)
    except re.error:
        continue

if hits:
    reason = ('This routine body carries credential-shaped text. It would be '
              'stored server-side and replayed on every future run, so the '
              'secret outlives this session. Reference a secret store from the '
              'routine instead of inlining the value.')
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': reason,
    }}))
    sys.exit(0)

if action not in MUTATING:
    sys.exit(0)

# ── (B) work scheduled outside the enforcement layer ──────────────────────────
if action == 'create_webhook_trigger':
    what = ('wire an external event source to fire a cloud routine. After this, '
            'something outside this machine decides when the agent runs')
elif action == 'run':
    what = 'start a cloud routine run now'
elif action == 'update':
    what = 'change what an existing cloud routine does on its next run'
else:
    what = 'create a cloud routine that runs unattended on a schedule'

reason = ('RemoteTrigger "%s" would %s. That run happens in the cloud with '
          'repository access, where no Supercharger guard applies — safety, '
          'git-safety and the secret scanners all run in THIS session only. '
          'Confirm you want work moved outside the enforcement layer.' % (action, what))
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'ask',
    'permissionDecisionReason': reason,
}}))
PYEOF
) || RESULT=""

if [ -n "$RESULT" ]; then
  printf '%s\n' "$RESULT"
fi
exit 0
