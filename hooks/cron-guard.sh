#!/usr/bin/env bash
# Claude Supercharger — Cron Guard
# Event: PreToolUse | Matcher: CronCreate, ScheduleWakeup
#
# CronCreate and ScheduleWakeup store a PROMPT that runs later, unattended. With
# CronCreate `durable: true` it is written to .claude/scheduled_tasks.json and outlives
# the session; RemoteTrigger (the cloud twin) already has remote-trigger-guard, this
# path was only logged (cron-discovery, async).
#   - credential-shaped text in `prompt`  -> deny (it is stored and replayed)
#   - CronCreate durable: true            -> ask  (persisted autonomous execution)
# Fields from the CC 2.1.289 schema: CronCreate {cron, prompt, recurring, durable},
# ScheduleWakeup {delaySeconds, prompt, reason}.
# Disable: SUPERCHARGER_CRON_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
check_hook_disabled "cron-guard" 2>/dev/null && exit 0
[ "${SUPERCHARGER_CRON_GUARD:-1}" = "0" ] && exit 0
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"; sc_read_input _INPUT
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || true
_CG_PATTERNS=$(printf '%s\n' "${SECRET_PATTERNS[@]:-}" 2>/dev/null || true)

RESULT=$(HOOK_INPUT="$_INPUT" PATTERNS="$_CG_PATTERNS" python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)
tool = data.get('tool_name') or ''
ti = data.get('tool_input') or {}
prompt = ti.get('prompt')
prompt = prompt if isinstance(prompt, str) else ''
for pat in (os.environ.get('PATTERNS') or '').splitlines():
    pat = pat.strip()
    if not pat:
        continue
    try:
        if re.search(pat, prompt):
            print('deny\tThis %s prompt carries credential-shaped text. It is stored and '
                  'replayed on every run, so the secret outlives this turn. Reference an '
                  'environment variable or secret store instead of the value.' % tool)
            sys.exit(0)
    except re.error:
        continue
if tool == 'CronCreate' and ti.get('durable') is True:
    sched = ti.get('cron') if isinstance(ti.get('cron'), str) else '?'
    print('ask\tCronCreate durable: true saves this prompt to .claude/scheduled_tasks.json '
          'and runs it on schedule (%s) after this session ends, with nobody watching. '
          'Confirm you want an unattended recurring agent run.' % sched)
PYEOF
) || RESULT=""

[ -z "$RESULT" ] && exit 0
_cg_decision="${RESULT%%$'\t'*}"
_cg_reason="${RESULT#*$'\t'}"
case "$_cg_decision" in
  deny) sc_decision deny "$_cg_reason" "remove the secret from the prompt"; exit 2 ;;
  ask)  sc_decision ask "$_cg_reason" "use durable: false for a session-only schedule"; exit 0 ;;
esac
exit 0
