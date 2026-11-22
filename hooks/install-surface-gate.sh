#!/usr/bin/env bash
# Claude Supercharger — Install Surface Gate (LOG-ONLY)
# Event: PreToolUse | Matcher: Bash, Monitor, PowerShell
#
# install-script-guard and pth-persistence-guard fire when the session WRITES a manifest.
# A cloned repo's package.json / setup.py / build.rs is never written here, so nothing read
# it before `npm i`, `pip install .` or `cargo build` ran it. This looks at those files for
# a project that is not yours (last commit by someone else, or no git) and appends what it
# found to $SUPERCHARGER_STATE/install-surface.jsonl. It never asks, never blocks, prints
# nothing: a month of real findings decides whether it should ask. Design:
# docs/INSTALL-BUILD-GATE-DESIGN.md. Disable: SUPERCHARGER_INSTALL_SURFACE=0
set -uo pipefail
[ "${SUPERCHARGER_INSTALL_SURFACE:-1}" = 0 ] && exit 0
. "${BASH_SOURCE[0]%/*}/lib-suppress.sh" 2>/dev/null || true
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh" 2>/dev/null || exit 0
. "${BASH_SOURCE[0]%/*}/lib-deny.sh" 2>/dev/null || exit 0
sc_read_input _INPUT
check_hook_disabled "install-surface-gate" 2>/dev/null && exit 0

# Fork-free gate: most Bash calls stop here. Superset of the commands the scan handles.
# 2026-11-22 (#353 review): the payload test only pre-filters; the command itself must
# name an install (a cwd called installer-tools no longer starts python), and `npm i` at
# the end of a command, `npm|pnpm|yarn add` count.
case "$_INPUT" in
  *install*|*npm*|*pnpm*|*yarn*|*bun*|*cargo*|*setup.py*) : ;;
  *) exit 0 ;;
esac
. "${BASH_SOURCE[0]%/*}/lib-json-fast.sh" 2>/dev/null || exit 0
# _json_fast_str matches the key at any depth (unique keys only); _json_get takes only
# top-level keys and would fork jq for every command naming npm.
if _json_fast_str command "$_INPUT"; then _ISG_CMD="$_JSON_FAST_VAL"
else _ISG_CMD=$(printf '%s' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null) || exit 0; fi
_ISG_RX='(^|[;&|(`[:space:]])((npm|pnpm|yarn|bun)[[:space:]]+(i|install|ci|add)([[:space:];&|)]|$)|yarn[[:space:]]*($|[;&|)])|pip[0-9.]*[[:space:]]+install|-m[[:space:]]+pip[[:space:]]+install|setup\.py[[:space:]]+(install|develop|build)|cargo[[:space:]]+(build|run|test|check|install))'
[[ "$_ISG_CMD" =~ $_ISG_RX ]] || exit 0

: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
HOOK_INPUT="$_INPUT" SC_STATE="$SUPERCHARGER_STATE" python3 - <<'PYEOF' >/dev/null 2>&1
import json, os, re, stat, subprocess, sys, time

try:
    d = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)
if d.get('tool_name') not in ('Bash', 'Monitor', 'PowerShell'):
    sys.exit(0)
ti = d.get('tool_input') or {}
cmd = ti.get('command') or ti.get('script') or ''

def native(p):
    # Git Bash hands native Windows Python MSYS paths (/tmp/x, /d/a/x) it cannot open.
    if p and not os.path.exists(p):
        try:
            r = subprocess.run(['cygpath', '-m', p], capture_output=True, text=True, timeout=3).stdout.strip()
            if r:
                return r
        except Exception:
            pass
    return p

cwd = native(d.get('cwd') or os.getcwd())
# 2026-11-22 (#353 review): `cd <dir> && npm i` installs <dir>, not the session cwd.
_cd = re.match(r'\s*(?:cd|pushd)\s+("[^"]+"|\'[^\']+\'|[^\s;&|]+)\s*(?:&&|;)', cmd)
if _cd:
    _d = _cd.group(1).strip('"\'')
    if _d == '~' or _d.startswith('~/'):  # $HOME first: expanduser reads USERPROFILE on Windows
        _d = (os.environ.get('HOME') or os.path.expanduser('~')) + _d[1:]
    # native(_d) before the join: Windows joins C:/cwd + /tmp/x into C:/tmp/x.
    cwd = native(os.path.normpath(os.path.join(cwd, native(_d))))

kinds = set()
if re.search(r'\b(npm|pnpm|yarn|bun)\s+(i|install|ci|add)\b|(^|[;&|]\s*)yarn\s*($|[;&|])', cmd): kinds.add('node')
if re.search(r'\bpip3?\s+install\b|setup\.py\s+(install|develop|build)|-m\s+pip\s+install', cmd): kinds.add('python')
if re.search(r'\bcargo\s+(build|run|test|check|install)\b', cmd): kinds.add('rust')
if not kinds or not os.path.isdir(cwd):
    sys.exit(0)

def git(*a):
    try:
        return subprocess.run(['git', '-C', cwd, *a], capture_output=True, text=True, timeout=3).stdout.strip()
    except Exception:
        return ''

# Your own project stays quiet: tracked, and the last commit is by you.
if os.path.exists(os.path.join(cwd, '.git')):
    last, me = git('log', '-1', '--format=%ae'), git('config', 'user.email')
    if last and me and last == me:
        sys.exit(0)

NET = re.compile(r'\b(curl|wget|nc|ncat)\b|\bnode\s+-e\b|\bpython3?\s+-c\b|base64|\beval\b|\|\s*(ba)?sh\b|https?://')
PYX = re.compile(r'os\.system|subprocess|urllib|requests\.|\bexec\(|\beval\(|base64|socket')
RSX = re.compile(r'Command::new|std::process|TcpStream|reqwest|curl')

CAP = 65536


# A regular file only, read up to `cap` bytes: a package.json symlinked to a FIFO or a
# device must not hang the hook (2026-11-22, #353 review).
def read(rel, cap=CAP):
    p = os.path.join(cwd, rel)
    try:
        if not stat.S_ISREG(os.stat(p).st_mode):
            return None
        with open(p, 'r', errors='replace') as f:
            return f.read(cap)
    except Exception:
        return None


def size(rel):
    try:
        return os.stat(os.path.join(cwd, rel)).st_size
    except Exception:
        return 0

found = []
if 'node' in kinds:
    t = read('package.json', 1 << 20)
    if t:
        try:
            sc = json.loads(t).get('scripts') or {}
            if not isinstance(sc, dict):
                sc = {}
        except Exception:
            # Over the cap or not JSON: never logged as clean. The lifecycle keys are
            # still read by regex, and the file is noted as unparsed.
            sc = dict(re.findall(r'"(preinstall|install|postinstall|prepare)"\s*:\s*"((?:[^"\\]|\\.)*)"', t))
            found.append(('package.json', 'not parsed (%d bytes): lifecycle scripts read by pattern only' % size('package.json')))
        for k in ('preinstall', 'install', 'postinstall', 'prepare'):
            if isinstance(sc.get(k), str) and NET.search(sc[k]):
                found.append(('package.json', 'lifecycle %s reaches the network or evals code' % k))
    if os.path.exists(os.path.join(cwd, '.pnpmfile.cjs')):
        found.append(('.pnpmfile.cjs', 'pnpm runs this file during install'))
    for y in ('.yarnrc', '.yarnrc.yml'):
        t = read(y)
        if t and re.search(r'yarnPath|yarn-path', t):
            found.append((y, 'yarnPath runs a vendored script as the package manager'))
    if os.path.exists(os.path.join(cwd, 'binding.gyp')):
        found.append(('binding.gyp', 'node-gyp runs its actions during install'))
if 'python' in kinds:
    t = read('setup.py')
    if t and PYX.search(t):
        found.append(('setup.py', 'runs code (subprocess/network/exec) at install time'))
if 'rust' in kinds:
    t = read('build.rs')
    if t and RSX.search(t):
        found.append(('build.rs', 'build script spawns a process or reaches the network'))
    for c in ('.cargo/config.toml', '.cargo/config'):
        t = read(c)
        if t and re.search(r'rustc-wrapper|runner\s*=|linker\s*=', t):
            found.append((c, 'cargo config swaps the compiler, linker or runner'))

if found:
    base = native(os.environ.get('SC_STATE') or '')
    if base:
        os.makedirs(base, exist_ok=True)
        # The same finding once per session (2026-11-22, #353 review): a repeated
        # `npm i` in one project is one fact, not ten log rows.
        sid = re.sub(r'[^\w.-]', '', str(d.get('session_id') or 'default'))[:80] or 'default'
        seen_p = os.path.join(base, 'install-surface-seen-%s' % sid)
        try:
            with open(seen_p) as f:
                seen = set(f.read().splitlines())
        except Exception:
            seen = set()
        new = [(fn, why) for fn, why in dict.fromkeys(found) if json.dumps([cwd, fn, why]) not in seen]
        if new:
            with open(os.path.join(base, 'install-surface.jsonl'), 'a') as f:
                for fn, why in new:
                    f.write(json.dumps({'ts': int(time.time()), 'cwd': cwd, 'file': fn, 'why': why}) + '\n')
            with open(seen_p, 'a') as f:
                for fn, why in new:
                    f.write(json.dumps([cwd, fn, why]) + '\n')
PYEOF
exit 0
