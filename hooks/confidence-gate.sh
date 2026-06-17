#!/usr/bin/env bash
# Claude Supercharger — Confidence Gate
# Event: PreToolUse | Matcher: Edit,Write,Bash
# Computes confidence score from recent tool history + signal flags;
# allows, warns, or denies tool calls based on three-tier thresholds.
# Disable: SUPERCHARGER_CONFIDENCE=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_CONFIDENCE:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# v2.6.37: bash fast-path. The matcher in lib/hooks.sh restricts to
# Edit,Write,Bash, but Claude Code may still invoke this hook with other tools
# during testing or schema drift. Cheap substring check before forking python
# saves ~40ms when the gate isn't applicable.
case "$_INPUT" in
  *'"tool_name":"Edit"'*|*'"tool_name":"Write"'*|*'"tool_name":"Bash"'*) ;;
  *) exit 0 ;;
esac

# Pre-resolve init_hook_suppress and disable checks. These need PROJECT_DIR
# from the payload — pluck it with bash substring scan to avoid an extra fork.
PROJECT_DIR=$( (printf '%s\n' "$_INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/') 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "confidence-gate" && exit 0
hook_profile_skip "confidence-gate" && exit 0

# v2.6.37: one python3 fork does everything — stdin parse, tool gate,
# destructive-pattern check (Bash only), reads scope files (.tool-history,
# .repetition-flag, .read-history), computes score, emits JSON. Was 7 forks
# (3 jq + 1 python destructive + 1 jq session + 1 jq file + 1 python score
# + 1 python json wrap). ~60ms → ~40ms.
TIER="${SUPERCHARGER_TIER:-standard}"
RESULT=$(HOOK_INPUT="$_INPUT" \
         SCOPE_DIR="$HOME/.claude/supercharger/scope" \
         TIER="$TIER" \
         HOOK_SUPPRESS="$HOOK_SUPPRESS" \
         python3 <<'PYEOF' 2>/dev/null || true
import json, os, re, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    d = json.loads(raw)
except Exception:
    sys.exit(0)

tool = d.get('tool_name') or ''
if tool not in ('Edit', 'Write', 'Bash'):
    sys.exit(0)

session_id = d.get('session_id') or 'default'
session_id = re.sub(r'[^a-zA-Z0-9_-]', '', str(session_id))[:64] or 'default'

tool_input = d.get('tool_input') or {}

# Bash destructive-pattern gate — skip non-destructive commands fast.
if tool == 'Bash':
    cmd = tool_input.get('command') or ''
    if not cmd:
        sys.exit(0)
    patterns = (
        r'(?:^|[\s;&|`])(?:/[a-z/]*?)?rm\s+-[a-zA-Z]*r[a-zA-Z]*[\s/]',
        r'(?:^|[\s;&|`])rm\s+-[a-zA-Z]*r[a-zA-Z]*\s*--\s',
        r'\brm\s+--recursive\b',
        r'\bgit\s+push\s+.*--force\b',
        r'\bgit\s+reset\s+--hard\b',
        r'\bgit\s+clean\s+-[a-zA-Z]*f',
        r'\bdrop\s+(table|database|schema)\b',
        r'\bterraform\s+destroy\b',
        r'\bdocker\s+system\s+prune\b',
        r'\bnpm\s+publish\b',
        r'\b(aws|gcloud)\s+.*delete\b',
    )
    if not any(re.search(p, cmd, re.IGNORECASE) for p in patterns):
        sys.exit(0)

scope_dir = os.environ.get('SCOPE_DIR', '')
target_file = tool_input.get('file_path') or ''

# Repetition flag
rep = int(os.path.isfile(os.path.join(scope_dir, f'.repetition-flag-{session_id}')))

# Read-before-write violation (Edit only)
rbw = 0
if tool == 'Edit' and target_file:
    rh = os.path.join(scope_dir, '.read-history')
    if not os.path.isfile(rh):
        rbw = 1
    else:
        try:
            with open(rh) as f:
                if not any(line.startswith(target_file + '\t') for line in f):
                    rbw = 1
        except Exception:
            rbw = 1

# Failures in last 5 entries of session tool-history
fail = 0
candidates = (
    os.path.join(scope_dir, f'.tool-history-{session_id}'),
    os.path.join(scope_dir, '.tool-history'),
)
history = next((p for p in candidates if os.path.isfile(p)), None)
if history:
    try:
        with open(history) as f:
            # tail -5 equivalent: deque of size 5
            from collections import deque
            tail = deque(f, maxlen=5)
        needle = f'"session_id": "{session_id}"'
        fail = sum(1 for line in tail if needle in line and '"success": false' in line)
    except Exception:
        fail = 0

score = max(0.0, min(1.0, 1.0 - 0.20 * fail - 0.30 * rbw - 0.20 * rep))
score_str = f'{score:.2f}'
above_07 = score >= 0.7
above_04 = score >= 0.4

if above_07:
    sys.exit(0)

reasons = []
if fail > 0:
    reasons.append(f'{fail} recent failures')
if rbw:
    reasons.append('read-before-write violation')
if rep:
    reasons.append('repetition flagged')
reason_str = ', '.join(reasons)

tier = os.environ.get('TIER', 'standard')
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

if tier == 'minimal':
    msg = f'[conf:{score_str}→warn]' if above_04 else f'[conf:{score_str}→deny]'
elif tier == 'lean':
    msg = f'confidence {score_str}: {reason_str}'
else:
    if above_04:
        msg = f'Confidence gate: {score_str} (warn)\n  {reason_str}\nProceed with caution.'
    else:
        msg = f'Confidence gate denied {tool} call (score {score_str}):\n  {reason_str}'

if above_04:
    print(json.dumps({'systemMessage': msg, 'suppressOutput': suppress}))
else:
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': msg,
        }
    }))
PYEOF
)

[ -n "$RESULT" ] && printf '%s\n' "$RESULT"
exit 0
