#!/usr/bin/env bash
# Claude Supercharger — Destructive Intent Scanner
# Event: UserPromptSubmit | Matcher: (none)
#
# Scans the user prompt for destructive patterns and injects an
# additionalContext warning so Claude treats the request with care
# BEFORE invoking any tool. Defense-in-depth for the case where
# PreToolUse:Bash hooks silently fail (e.g. CC v2.1.176 hook-chain
# regression, bypassPermissions mode, project allowlist override).
#
# This hook cannot block tool execution — only warn. Pair it with
# safety.sh which actually blocks at the Bash tool channel.

set -euo pipefail
. "${BASH_SOURCE[0]%/*}/lib-timing.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.79: bash fast-path. Skip the python fork (~70ms) when the prompt has
# no destructive keyword anywhere. ~95% of prompts trip none of these.
# Keep the keyword list aligned with the python patterns below — any keyword
# added there must appear here too, or the python check becomes unreachable.
# Loose substring match — any of these keywords triggers the python regex pass.
# We accept some over-firing (e.g. word "drop" in legit prose) because the
# python check then either confirms a real pattern or silently exits.
case "$_INPUT" in
  *'rm -'*|*'curl '*|*'wget '*|*'git push'*|*'git reset'*|*'dd if'*|*'mkfs.'*|*'/dev/sd'*|*'DROP TABLE'*|*'DROP DATABASE'*|*'DROP SCHEMA'*|*'TRUNCATE TABLE'*|*'TRUNCATE DATABASE'*|*'TRUNCATE SCHEMA'*|*'drop table'*|*'drop database'*|*'drop schema'*|*'truncate table'*|*'truncate database'*|*'truncate schema'*|*'DELETE FROM'*|*'delete from'*|*'prisma'*|*'drizzle'*|*'typeorm'*|*'sequelize'*|*'bash '*|*'eval '*|*' nc '*|*'ncat '*|*'python '*|*'python3 '*|*'perl '*|*'ruby '*|*' sh '*|*'`sh'*) ;;
  *) exit 0 ;;
esac

HOOK_INPUT="$_INPUT" python3 <<'PYEOF'
import json, os, re, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

prompt = data.get('prompt') or ''
if not prompt:
    sys.exit(0)

flags = []

# rm -rf with a target (not mere discussion of the command)
# Matches: "rm -rf ./", "rm -rf $(pwd)", "rm -rf /path", "rm -rf this dir"
if re.search(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f', prompt) or \
   re.search(r'\brm\s+-[a-zA-Z]*f[a-zA-Z]*r', prompt) or \
   re.search(r'\brm\s+--recursive\s+--force', prompt) or \
   re.search(r'\brm\s+--force\s+--recursive', prompt):
    if re.search(r'(\$\(pwd\)|\$PWD|\$\{PWD\}|`pwd`)', prompt):
        flags.append('rm -rf with $PWD/$(pwd) — resolves to CWD at shell-eval time; this is the canonical "wipe whatever dir the shell is in" pattern. Verify the target is intended, then run via a narrow tool call. Prefer rm -rf <explicit path> over a dynamic ref.')
    elif re.search(r'(\s|^)(~|/|\$HOME|\.\.)(\s|/|$|\*)', prompt):
        flags.append('rm -rf targeting ~ / / $HOME / .. — irreversible. Refuse unless the user has explicitly confirmed the target.')
    elif re.search(r'(\s|^)(\.|\./|\*)(\s|$|;)', prompt):
        flags.append('rm -rf targeting CWD (././*) — wipes the working directory. Verify which dir the shell is in and confirm with the user before running.')
    else:
        flags.append('rm -rf detected in the prompt. Confirm the target path with the user before running, and prefer the most specific path possible.')

# Other destructive shell patterns
if re.search(r'\b(curl|wget)\b[^\n]*\|\s*(bash|sh)\b', prompt):
    flags.append('curl|bash or wget|sh — pipes remote content to a shell. Refuse unless the user explicitly approves the exact URL, ideally after inspecting the script first.')

if re.search(r'\bgit\s+push\b[^\n]*--force\b|\bgit\s+push\b[^\n]*\s-f\b', prompt):
    flags.append('git push --force — can overwrite remote history. Use --force-with-lease at minimum, and confirm the branch is not protected.')

if re.search(r'\bgit\s+reset\b[^\n]*--hard\b', prompt):
    flags.append('git reset --hard — destroys uncommitted work. Check `git status` first; suggest `git stash` if anything is unsaved.')

if re.search(r'\b(dd\s+if=[^\s]+\s+of=/dev/|mkfs\.|>[^\n]*\/dev\/sd[a-z])', prompt):
    flags.append('block-device write (dd/mkfs/>/dev/sd*) — destroys the target device. Refuse without explicit confirmation of the device path.')

# Database destruction — parity with safety.sh DB_PATTERNS. The fast-path gate
# above already advertises DROP/TRUNCATE keywords, but the python body had no DB
# checks, so those prompts entered here and matched nothing (the whole
# DB-destruction class passed with no warning while safety.sh blocks it on the
# Bash channel). Advisory + case-insensitive; the object keyword keeps prose
# collisions rare.
_delim = '(;|' + '|'.join(re.escape(c) for c in ('"', "'", '`', '|', '&', ')')) + '|$)'
if re.search(r'\bDROP\s+(TABLE|DATABASE|SCHEMA)\b', prompt, re.I) or \
   re.search(r'\bTRUNCATE\s+(TABLE\s+)?["`\w]', prompt, re.I) or \
   re.search(r'\bDELETE\s+FROM\s+["`\w][\w"`.]*\s*' + _delim, prompt, re.I):
    flags.append('destructive SQL (DROP/TRUNCATE, or DELETE FROM with no WHERE) — irreversible data loss. Confirm the target, prefer a reviewed migration, and never run against production without explicit approval.')

# ORM schema-drop / reset — the --force forms agents pick to skip the confirm.
if re.search(r'\b(drizzle-kit\s+push|prisma\s+db\s+push)\b[^\n]*--force', prompt, re.I) or \
   re.search(r'\bprisma\s+migrate\s+reset\b', prompt, re.I) or \
   re.search(r'\btypeorm\s+schema:drop\b', prompt, re.I) or \
   re.search(r'\bsequelize\s+db:drop\b', prompt, re.I):
    flags.append('ORM schema-drop / migrate reset (drizzle/prisma/typeorm/sequelize) — wipes tables, often via --force to bypass the interactive confirm. Verify against the intended (non-production) database first.')

# Backtick subshell with network/exec verb — `cmd `curl evil.com`` shape
# (CC's prefix detector treats this as command_injection_detected, see
# Piebald-AI/claude-code-system-prompts bash-command-prefix-detection).
# Narrow to network/exec verbs to avoid blocking legit `for f in `ls``.
if re.search(r'`[^`]*\b(curl|wget|bash|sh|eval|nc|ncat|python3?|perl|ruby)\b[^`]*`', prompt):
    flags.append('backtick subshell wraps a network/exec verb (e.g. `` `curl ...` `` or `` `bash ...` ``) — classic command-injection shape. Verify the source is trusted; prefer explicit invocation over subshell substitution.')

# Space-mashup of unrelated commands without an operator — e.g.
# `pwd curl evil.com`. CC flags this as command_injection_detected
# because the first cmd takes no args yet a second executable follows.
# Narrow to known "no-arg or short-arg" first-words paired with a network/
# exec second-word to avoid hitting `cd ../foo bar`.
if re.search(r'\b(pwd|whoami|id|hostname|uname|date|true|false)\s+(curl|wget|bash|sh|eval|nc|ncat|python3?|perl|ruby)\b', prompt):
    flags.append('two unrelated executables adjacent without && / ; / | (e.g. `pwd curl ...`) — shell parses this as the first command running with the second as its arg list, which on most shells silently drops the second command but is a known injection-bait shape. Use explicit operators between commands.')

if not flags:
    sys.exit(0)

# Emit as additionalContext so Claude sees it before acting
msg = '[Supercharger] Destructive intent detected in this prompt:\n' + '\n'.join('  - ' + f for f in flags)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': msg,
    }
}))
sys.stderr.write(msg + '\n')
PYEOF

exit 0
