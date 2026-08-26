#!/usr/bin/env bash
# Claude Supercharger — Env Exec Guard
# Event: PreToolUse | Matcher: Bash
#
# Setting a code-injecting environment variable causes arbitrary code execution on
# the NEXT process spawn — the `git status` / `npm test` that runs afterwards looks
# benign, so this sidesteps every command-pattern guard. `export LD_PRELOAD=/tmp/x.so
# && git log`, `NODE_OPTIONS='--require /tmp/x.js' npm test`, `export BASH_ENV=/tmp/p.sh`,
# `export GIT_SSH_COMMAND='sh -c …'`. safety.sh covers reverse shells / persistence
# files but NOT the env-preload exec class. ASKS (LD_LIBRARY_PATH / NODE_OPTIONS have
# legit dev uses), value-shape gated so benign forms pass (NODE_OPTIONS=
# --max-old-space-size, LD_LIBRARY_PATH=/usr/local/lib). Asks once per var per
# session. Advisory + fail-open; disable with SUPERCHARGER_ENV_EXEC_GUARD=0.
# Disable: SUPERCHARGER_ENV_EXEC_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_ENV_EXEC_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Fast-path: one of the code-injecting var names must be present.
case "$_INPUT" in
  *LD_PRELOAD*|*DYLD_INSERT_LIBRARIES*|*LD_LIBRARY_PATH*|*DYLD_LIBRARY_PATH*|*NODE_OPTIONS*|*BASH_ENV*|*PYTHONSTARTUP*|*PYTHONPATH*|*PERL5OPT*|*RUBYOPT*|*PROMPT_COMMAND*|*GIT_SSH_COMMAND*|*GIT_SSH*|*GIT_EXTERNAL_DIFF*|*ENV=*) : ;;
  *) exit 0 ;;
esac

check_hook_disabled "env-exec-guard" 2>/dev/null && exit 0
hook_profile_skip "env-exec-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

_EE_OUT=$(mktemp 2>/dev/null) || _EE_OUT="${TMPDIR:-/tmp}/envexec.$$"
CMD_IN="$CMD" python3 > "$_EE_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys

cmd = os.environ.get("CMD_IN", "")

# per-var value policy: what makes the assignment dangerous.
POLICY = {
    # Any non-empty value is an exec vector (preloaded lib / auto-sourced file).
    "LD_PRELOAD": "any", "DYLD_INSERT_LIBRARIES": "any",
    "BASH_ENV": "any", "ENV": "any", "PYTHONSTARTUP": "any",
    # Command-injection-shaped value only (a plain `ssh -i key` / `history -a` passes).
    "PROMPT_COMMAND": "shaped",
    # v2.29.31: these three name a PROGRAM git will execute, so the value is a
    # command by definition -- `GIT_SSH_COMMAND=id git fetch` runs id, with no shell
    # gadget for the "shaped" test to find. "shaped" was too permissive: it only
    # caught values carrying $( , a pipe, or a script suffix. The legitimate value is
    # always some form of ssh, so the honest test is "does the first token invoke
    # ssh". Found by diffing against kenryu42/cc-safety-net (git.ssh-env).
    "GIT_SSH_COMMAND": "ssh-exec", "GIT_SSH": "ssh-exec",
    "GIT_EXTERNAL_DIFF": "ssh-exec",
    "NODE_OPTIONS": "node", "PERL5OPT": "perl", "RUBYOPT": "ruby",
    "LD_LIBRARY_PATH": "writable", "DYLD_LIBRARY_PATH": "writable",
    "PYTHONPATH": "writable",
}
# Command-injection shape — deliberately NOT a bare `/` or `~` (those are ordinary
# paths, e.g. GIT_SSH_COMMAND='ssh -i ~/.ssh/id'); a script suffix or a shell gadget.
SHAPED = re.compile(r'(^\s*!|\$\(|`|;|\||&&|\bsh\s+-c\b|\bbash\s+-c\b|\bzsh\s+-c\b|'
                    r'\bnode\s+-e\b|\bpython3?\s+-c\b|\.(so|sh|py|js|rb|pl|dylib|bash|zsh)\b)')
WRITABLE = re.compile(r'(/tmp|/var/tmp|/dev/shm|(^|:)~|(^|:)\.(/|:|$)|\$TMPDIR|\.(so|dylib)\b)')
NODE = re.compile(r'(--(require|import)\b|(^|\s)-r\s)')
PERL = re.compile(r'(^|[\s"\'])-[Me]')
RUBY = re.compile(r'(^|[\s"\'])-[re]')

def dangerous(policy, val):
    v = val.strip()
    if not v:
        return False
    if policy == "any":     return True
    if policy == "shaped":  return bool(SHAPED.search(v))
    if policy == "ssh-exec":
        # Anything shell-shaped is dangerous regardless of the program named.
        if SHAPED.search(v):
            return True
        # Otherwise: flag unless the program actually is ssh. `ssh -i ~/.ssh/id`,
        # `/usr/bin/ssh -o X=y` and `ssh.exe` all pass; `id`, `/tmp/x`, `curl` do not.
        first = v.split()[0] if v.split() else ""
        base = first.rsplit("/", 1)[-1].rsplit("\\", 1)[-1].lower()
        if base.endswith(".exe"):
            base = base[:-4]
        return base != "ssh"
    if policy == "writable":return bool(WRITABLE.search(v))
    if policy == "node":    return bool(NODE.search(v))
    if policy == "perl":    return bool(PERL.search(v))
    if policy == "ruby":    return bool(RUBY.search(v))
    return False

names = "|".join(sorted(POLICY, key=len, reverse=True))
# VAR=value  (optionally `export VAR=`); value = quoted or up to whitespace.
rx = re.compile(r'\b(' + names + r')=("[^"]*"|\'[^\']*\'|\S*)')
hit = None
for m in rx.finditer(cmd):
    var, raw = m.group(1), m.group(2)
    if raw[:1] in ('"', "'") and raw[-1:] == raw[:1]:
        raw = raw[1:-1]
    if dangerous(POLICY[var], raw):
        hit = (var, raw)
        break

if hit:
    print("%s\t%s" % (hit[0], hit[1][:80]))
PYEOF
_RESULT=$(cat "$_EE_OUT" 2>/dev/null); rm -f "$_EE_OUT" 2>/dev/null
[ -z "$_RESULT" ] && exit 0

_VAR="${_RESULT%%$'\t'*}"

SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.envexec-seen-${SID}"
if [ -f "$_SEEN" ] && grep -qxF "$_VAR" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_VAR" >> "$_SEEN" 2>/dev/null || true

_MSG="This sets the environment variable ${_VAR} to a code-loading value — the shell/interpreter will execute it on the NEXT process it spawns (a later git/npm/python command), which sidesteps command-level guards. Common exec/persistence vector (LD_PRELOAD, NODE_OPTIONS --require, BASH_ENV, GIT_SSH_COMMAND…). Confirm it's an intended, trusted value. (Disable: SUPERCHARGER_ENV_EXEC_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] env-exec-guard: ASK on code-injecting env var (${_VAR})" >&2
exit 0
