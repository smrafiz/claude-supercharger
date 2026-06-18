#!/usr/bin/env bash
# Claude Supercharger — Shell-Escape Advisor Hook
# Event: UserPromptSubmit | Matcher: (none)
#
# Claude Code's `! <cmd>` prompt prefix runs commands directly in the user's
# shell, bypassing PreToolUse:Bash hooks. Supercharger cannot block these —
# they never reach the Bash tool channel. This hook scans user prompts for
# dangerous `! rm -rf …` patterns and emits an advisory warning to stderr
# before the shell executes them. Advisory only; the shell still runs the
# command.

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

prompt = data.get('prompt') or ''
if not prompt or not prompt.lstrip().startswith('!'):
    sys.exit(0)

body = prompt.lstrip()[1:].lstrip()
if not body:
    sys.exit(0)

flagged = []

# rm -rf with recursive + force flags on dangerous targets
_has_rm = re.search(r'(^|\s|;|&&|\|\|)(sudo\s+)?rm(\s|$)', body) is not None
_has_recursive = re.search(r'(^|\s)-[a-zA-Z]*r[a-zA-Z]*(\s|$)|--recursive(\s|$)', body) is not None
_has_force = re.search(r'(^|\s)-[a-zA-Z]*f[a-zA-Z]*(\s|$)|--force(\s|$)', body) is not None
if _has_rm and _has_recursive and _has_force:
    if re.search(r'(\s|^)(~|/|\$HOME|\.\.)(\s|/|$|\*)', body):
        flagged.append('`! rm -rf` targeting ~, /, $HOME, or .. — irreversible. Shell escapes bypass Supercharger.')
    elif re.search(r'(\s|^)(\.|\./|\*)(\s|$)', body):
        flagged.append('`! rm -rf` targeting CWD (. / ./ / *) — wipes the working directory. Shell escapes bypass Supercharger.')
    elif re.search(r'(\s)/[A-Za-z][^\s]*', body):
        flagged.append('`! rm -rf` on an absolute path — shell escapes bypass Supercharger guardrails; verify the target before submitting.')
    else:
        flagged.append('`! rm -rf` — shell escapes bypass Supercharger guardrails; verify the target before submitting.')

# Other high-risk patterns in shell-escape
if re.search(r'\b(curl|wget)\b[^\n]*\|\s*(bash|sh)\b', body):
    flagged.append('`! curl|bash` or `! wget|sh` — pipes remote content to a shell. Shell escapes bypass Supercharger.')
if re.search(r'\bgit\s+push\b[^\n]*--force\b|\bgit\s+push\b[^\n]*\s-f\b', body):
    flagged.append('`! git push --force` — shell escapes bypass Supercharger; force-push can overwrite remote history.')
if re.search(r'\bgit\s+reset\b[^\n]*--hard\b', body):
    flagged.append('`! git reset --hard` — shell escapes bypass Supercharger; destroys uncommitted work.')

for msg in flagged:
    sys.stderr.write('[Supercharger] ' + msg + '\n')
PYEOF

exit 0
