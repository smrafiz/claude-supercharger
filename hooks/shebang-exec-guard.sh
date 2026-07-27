#!/usr/bin/env bash
# Claude Supercharger — Shebang Exec Guard
# Event: PostToolUse | Matcher: Write, Edit, MultiEdit
#
# The Write tool creates files at mode 0644, so a freshly-written script with a
# `#!/usr/bin/env bash` shebang is NOT executable — running it (`./deploy.sh`) fails
# with "permission denied", a wasted round-trip. This WARNS (additionalContext,
# never blocks) when the file just written begins with a shebang but lacks the
# executable bit, with the exact `chmod +x` to fix it. WARN (not ASK) because many
# shebang files are meant to be sourced, not executed — this is a heads-up, not a
# gate. Reads the FINAL on-disk mode (post-write). Fail-open; disable with
# SUPERCHARGER_SHEBANG_EXEC_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_SHEBANG_EXEC_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
# Fast-path: a shebang has to be somewhere in the payload.
case "$_INPUT" in *'#!'*) : ;; *) exit 0 ;; esac
check_hook_disabled "shebang-exec-guard" 2>/dev/null && exit 0
hook_profile_skip "shebang-exec-guard" 2>/dev/null && exit 0

_SB_OUT=$(mktemp 2>/dev/null) || _SB_OUT="${TMPDIR:-/tmp}/shebang.$$"
HOOK_INPUT="$_INPUT" python3 > "$_SB_OUT" 2>/dev/null <<'PYEOF'
import os, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ""
if not path or not os.path.isfile(path):
    sys.exit(0)
try:
    with open(path, "r", errors="replace") as f:
        first = f.readline()
except Exception:
    sys.exit(0)
if not first.startswith("#!"):
    sys.exit(0)
try:
    mode = os.stat(path).st_mode
except Exception:
    sys.exit(0)
if mode & 0o111:                       # already executable → nothing to say
    sys.exit(0)

interp = first[2:].strip()[:60] or "a shebang"
print(interp)
PYEOF
_INTERP=$(cat "$_SB_OUT" 2>/dev/null); rm -f "$_SB_OUT" 2>/dev/null
[ -z "$_INTERP" ] && exit 0

_FP=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
_MSG="[not executable] The file just written starts with a shebang (${_INTERP}) but is mode 0644 — running it directly (e.g. ./$(basename "$_FP")) will fail with 'permission denied'. Run: chmod +x $_FP  (ignore this if you source the file instead of executing it). (Disable: SUPERCHARGER_SHEBANG_EXEC_GUARD=0)"
_JSON=$(printf '%s' "$_MSG" | python3 -c "import sys,json;print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.stdin.read()}}))" 2>/dev/null || true)
[ -z "$_JSON" ] && exit 0
printf '%s\n' "$_JSON"
echo "[Supercharger] shebang-exec-guard: shebang script written without +x — ${_FP}" >&2
exit 0
