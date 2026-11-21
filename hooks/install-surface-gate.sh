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
case "$_INPUT" in
  *install*|*"npm ci"*|*"npm i "*|*yarn*|*"bun "*|*cargo*|*setup.py*) : ;;
  *) exit 0 ;;
esac

: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
HOOK_INPUT="$_INPUT" SC_STATE="$SUPERCHARGER_STATE" python3 - <<'PYEOF' 2>/dev/null
import json, os, re, subprocess, sys, time

try:
    d = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)
if d.get('tool_name') not in ('Bash', 'Monitor', 'PowerShell'):
    sys.exit(0)
ti = d.get('tool_input') or {}
cmd = ti.get('command') or ti.get('script') or ''
cwd = d.get('cwd') or os.getcwd()

kinds = set()
if re.search(r'\b(npm|pnpm|yarn|bun)\s+(i|install|ci|add)\b|^\s*yarn\s*$', cmd): kinds.add('node')
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

def read(rel):
    p = os.path.join(cwd, rel)
    try:
        with open(p, 'r', errors='replace') as f:
            return f.read(65536)
    except Exception:
        return None

found = []
if 'node' in kinds:
    t = read('package.json')
    if t:
        try:
            sc = (json.loads(t).get('scripts') or {})
        except Exception:
            sc = {}
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
    base = os.environ.get('SC_STATE') or ''
    if base:
        os.makedirs(base, exist_ok=True)
        with open(os.path.join(base, 'install-surface.jsonl'), 'a') as f:
            for fn, why in found:
                f.write(json.dumps({'ts': int(time.time()), 'cwd': cwd, 'file': fn, 'why': why}) + '\n')
PYEOF
exit 0
