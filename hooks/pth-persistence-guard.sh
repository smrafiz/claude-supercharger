#!/usr/bin/env bash
# Claude Supercharger — .pth Persistence Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# CPython executes any line in a `.pth` file that starts with `import ` — every
# time the interpreter starts, with no explicit import, for any `.pth` dropped in
# site-packages/dist-packages. A code-bearing `.pth` (`import os;os.system("curl|sh")`)
# is therefore a startup-persistence / RCE primitive that SURVIVES package
# uninstall (the "Hades" .pth-worm class, 2026). install-script-guard covers
# package.json/setup.py lifecycle scripts but not `.pth`. DENY on a `.pth` import
# line carrying a shell/network primitive (never a legit editable-install use);
# ASK on the softer exec forms (exec/eval/__import__, rare in old editable pth).
# Legit `.pth` files list bare paths, or `import sys; sys.path...` finders — both
# pass. Fail-open; disable with SUPERCHARGER_PTH_GUARD=0.
# Disable: SUPERCHARGER_PTH_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_PTH_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
case "$_INPUT" in *.pth*) : ;; *) exit 0 ;; esac
check_hook_disabled "pth-persistence-guard" 2>/dev/null && exit 0

_PTH_OUT=$(mktemp 2>/dev/null) || _PTH_OUT="${TMPDIR:-/tmp}/pthguard.$$"
HOOK_INPUT="$_INPUT" python3 > "$_PTH_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ti.get("notebook_path") or ""
if not path.replace("\\", "/").rsplit("/", 1)[-1].endswith(".pth"):
    sys.exit(0)

content = ti.get("content") or ti.get("new_string") or ""
if not content and isinstance(ti.get("edits"), list):
    content = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
if not content:
    sys.exit(0)

# Shell/network exec primitives — never appear in a legitimate .pth (which does
# path manipulation / import finders only).
DENY = re.compile(
    r'os\.system|os\.popen|\bsubprocess\b|\bPopen\b|\bsocket\.|\bpty\.|/dev/tcp|'
    r'\burllib\b|\brequests\.|\bhttplib\b|(^|[^a-zA-Z])(curl|wget|nc|bash|sh)\b|'
    r'base64\.b64decode', re.I)
# Softer exec forms — rare-but-possible in old setuptools editable pth → ASK.
ASK = re.compile(r'\bexec\(|\beval\(|__import__\(|\bcompile\(')

verdict = None
for line in content.splitlines():
    if not re.match(r'^\s*import\s', line):   # only import-lines are executed by CPython
        continue
    rest = line
    if DENY.search(rest):
        verdict = ("DENY", rest.strip()[:80]); break
    if ASK.search(rest) and verdict is None:
        verdict = ("ASK", rest.strip()[:80])

if verdict:
    print("%s\t%s" % verdict)
PYEOF
_RESULT=$(cat "$_PTH_OUT" 2>/dev/null); rm -f "$_PTH_OUT" 2>/dev/null
[ -z "$_RESULT" ] && exit 0

_VERDICT="${_RESULT%%$'\t'*}"

if [ "$_VERDICT" = "DENY" ]; then
  _MSG="Blocked: this .pth file contains an 'import' line that runs a shell/network command. CPython executes every 'import'-prefixed line in a .pth on interpreter startup (no import needed), so this is a persistence/RCE backdoor that survives package uninstall. A legitimate .pth lists paths or a sys.path finder — not os.system/subprocess/socket. (Disable: SUPERCHARGER_PTH_GUARD=0)"
  RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] pth-persistence-guard: DENY code-bearing .pth" >&2
  exit 2
fi

_MSG="This .pth file has an 'import' line that runs code (exec/eval/__import__). CPython executes 'import'-prefixed .pth lines on every interpreter startup — an easily-missed persistence channel. Confirm it is an intended editable-install shim and not injected. (Disable: SUPERCHARGER_PTH_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] pth-persistence-guard: ASK exec-bearing .pth" >&2
exit 0
