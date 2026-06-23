#!/usr/bin/env bash
# Claude Supercharger — Slash Command Expansion Guard
# Event: UserPromptExpansion | Matcher: (none)
#
# Inspects the *expanded* prompt of a user-typed slash command (custom
# `/<name>` definitions and MCP prompt resolutions) BEFORE it reaches
# Claude. A custom command like `/deploy-prod` could expand into
# arbitrary instructions including destructive shell ops — this hook
# catches that case which destructive-prompt-scanner.sh (UserPromptSubmit
# only) doesn't see because the user typed `/deploy-prod`, not the
# expanded text.
#
# Emits an additionalContext warning when the expansion contains
# destructive patterns. Cannot block expansion in this CC version;
# defense-in-depth advisory only.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

_INPUT=$(cat)

HOOK_INPUT="$_INPUT" python3 <<'PYEOF'
import json, os, re, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

# UserPromptExpansion payload carries the expanded text in `.prompt`
# alongside `.command_name`, `.command_args`, `.command_source`.
prompt = data.get('prompt') or ''
cmd = data.get('command_name') or '?'
if not prompt:
    sys.exit(0)

flags = []

if re.search(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f', prompt) or \
   re.search(r'\brm\s+-[a-zA-Z]*f[a-zA-Z]*r', prompt) or \
   re.search(r'\brm\s+--recursive\s+--force', prompt) or \
   re.search(r'\brm\s+--force\s+--recursive', prompt):
    flags.append(f'`/{cmd}` expansion contains `rm -rf` — verify the target path with the user before execution.')

if re.search(r'\b(curl|wget)\b[^\n]*\|\s*(bash|sh)\b', prompt):
    flags.append(f'`/{cmd}` expansion pipes remote content to a shell (`curl|bash` / `wget|sh`). Refuse unless the URL is explicitly approved after inspection.')

if re.search(r'\bgit\s+push\b[^\n]*(--force(?!-with-lease)|\s-f\b)', prompt):
    flags.append(f'`/{cmd}` expansion contains `git push --force` (not --force-with-lease). Confirm the branch is not protected before running.')

if re.search(r'\bgit\s+reset\b[^\n]*--hard\b', prompt):
    flags.append(f'`/{cmd}` expansion contains `git reset --hard` — destroys uncommitted work. Check `git status` first.')

if re.search(r'\b(dd\s+if=[^\s]+\s+of=/dev/|mkfs\.|>[^\n]*\/dev\/sd[a-z])', prompt):
    flags.append(f'`/{cmd}` expansion targets block devices (dd/mkfs/>/dev/sd*) — destroys the device. Refuse without explicit confirmation.')

if re.search(r'\b(DROP|TRUNCATE)\s+(TABLE|DATABASE|SCHEMA)\b', prompt, re.IGNORECASE):
    flags.append(f'`/{cmd}` expansion contains a destructive SQL statement (DROP/TRUNCATE). Confirm the target schema with the user.')

if not flags:
    sys.exit(0)

msg = f'[Supercharger] Slash command `/{cmd}` expanded into a destructive sequence:\n' + '\n'.join('  - ' + f for f in flags)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptExpansion',
        'additionalContext': msg,
    }
}))
sys.stderr.write(msg + '\n')
PYEOF

exit 0
