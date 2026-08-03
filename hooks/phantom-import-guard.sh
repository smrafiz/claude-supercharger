#!/usr/bin/env bash
# Claude Supercharger — Phantom Import Guard
# Event: PostToolUse | Matcher: Write, Edit, MultiEdit
#
# Catches a hallucinated LOCAL relative import (`./services/email` when the file is
# `./services/mailer.ts`, or Python `from .services.email import x` with no such
# module) the moment it's written — before the next compile/run wastes a round-trip.
# WARN only (additionalContext) — never blocks. Scoped to `./` and `../` relative
# imports (path aliases like `@/…` and bare packages need a resolver, so they're
# skipped), and only fires when NO candidate file/dir resolves at all — the strong
# typo/hallucination signal. Barrel `index.*`/`__init__.py` and every real
# extension are resolved before flagging, to keep false positives low.
# Fail-open; disable with SUPERCHARGER_PHANTOM_IMPORT_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_PHANTOM_IMPORT_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: needs an import/require/from keyword AND a relative marker.
case "$_INPUT" in *import*|*require*|*from*) : ;; *) exit 0 ;; esac
check_hook_disabled "phantom-import-guard" 2>/dev/null && exit 0
hook_profile_skip "phantom-import-guard" 2>/dev/null && exit 0

_PI_OUT=$(mktemp 2>/dev/null) || _PI_OUT="${TMPDIR:-/tmp}/phantomimp.$$"
HOOK_INPUT="$_INPUT" python3 > "$_PI_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ""
if not path or not os.path.isabs(path):
    sys.exit(0)
base = path.rsplit("/", 1)[-1].lower()
ext = "." + base.rsplit(".", 1)[-1] if "." in base else ""
JS = ext in (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs")
PY = ext == ".py"
if not (JS or PY):
    sys.exit(0)

content = ti.get("content") or ti.get("new_string") or ""
if not content and isinstance(ti.get("edits"), list):
    content = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
if not content:
    sys.exit(0)

d0 = os.path.dirname(path)
missing = []

def js_resolves(spec):
    target = os.path.normpath(os.path.join(d0, spec))
    exts = ["", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".json", ".d.ts"]
    for e in exts:
        if os.path.isfile(target + e):
            return True
    if os.path.isdir(target):
        for idx in ("index.ts", "index.tsx", "index.js", "index.jsx", "index.mjs", "index.cjs"):
            if os.path.isfile(os.path.join(target, idx)):
                return True
        return True   # a dir with some other entry — don't flag
    return False

if JS:
    seen = set()
    for m in re.finditer(r'''(?:from|import|require\(|import\()\s*['"](\.[^'"]+)['"]''', content):
        spec = m.group(1)
        if spec in seen:
            continue
        seen.add(spec)
        if not js_resolves(spec):
            missing.append(spec)

def py_resolves(dots, modpath):
    up = len(dots) - 1           # one dot = current pkg, two = parent, …
    d = d0
    for _ in range(up):
        d = os.path.dirname(d)
    parts = modpath.split(".") if modpath else []
    target = os.path.join(d, *parts) if parts else d
    if os.path.isfile(target + ".py") or os.path.isdir(target) or os.path.isfile(os.path.join(target, "__init__.py")):
        return True
    # `from .pkg import name` — `name` may be the module; only flag if pkg itself is gone
    return False

if PY:
    seen = set()
    for m in re.finditer(r'^\s*from\s+(\.+)([a-zA-Z0-9_.]*)\s+import\s', content, re.M):
        dots, modpath = m.group(1), m.group(2)
        key = dots + modpath
        if key in seen:
            continue
        seen.add(key)
        if not py_resolves(dots, modpath):
            missing.append(dots + modpath)

if missing:
    print("; ".join(missing[:4]))
PYEOF
_MISS=$(cat "$_PI_OUT" 2>/dev/null); rm -f "$_PI_OUT" 2>/dev/null
[ -z "$_MISS" ] && exit 0

_MSG="[phantom import] The file references relative import(s) that do not resolve to a file on disk: ${_MISS}. Likely a hallucinated filename or wrong relative depth — verify the path (or the module exists) before this fails at compile/run time. (Disable: SUPERCHARGER_PHANTOM_IMPORT_GUARD=0)"
_JSON=$(printf '%s' "$_MSG" | python3 -c "import sys,json;print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.stdin.read()}}))" 2>/dev/null || true)
[ -z "$_JSON" ] && exit 0
printf '%s\n' "$_JSON"
echo "[Supercharger] phantom-import-guard: unresolved relative import(s) — ${_MISS}" >&2
exit 0
