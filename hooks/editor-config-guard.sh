#!/usr/bin/env bash
# Claude Supercharger — Editor Config Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# The `.claude/settings.json` hook-injection / `.mcp.json` stdio-server primitive
# has been ported to EVERY sibling AI/editor config that auto-executes on
# folder-open or session load — the repo guards `.claude`/root `.mcp.json` but not
# the neighbours (Contagious-Interview `tasks.json` vector, Miasma / Mini-Shai-Hulud
# worms 2026; MCPoison CVE-2025-54136, Windsurf CVE-2026-30615). A write an agent is
# tricked into making runs code on the next open:
#   .vscode/tasks.json  →  runOptions.runOn = "folderOpen"  (silent exec on open)
#   .vscode/mcp.json / .cursor/mcp.json / .gemini/settings.json  →  a stdio server
#       { "command": …, "args": … }  launches a local process on load
# ASKS (devs legitimately write tasks.json and MCP configs) — gated on the auto-RUN
# keys (`folderOpen` / a stdio `command`), so a plain build-task or remote-only
# (url) MCP config passes. `.cursor/rules/*.mdc` is intentionally NOT here — that's
# instruction-poisoning, already covered by memory-write-guard. Asks once per file
# per session. Fail-open; disable with SUPERCHARGER_EDITOR_CONFIG_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_EDITOR_CONFIG_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: bail unless a target filename or auto-run key could be present.
case "$_INPUT" in
  *tasks.json*|*mcp.json*|*.gemini*|*folderOpen*|*mcpServers*) : ;;
  *) exit 0 ;;
esac
check_hook_disabled "editor-config-guard" 2>/dev/null && exit 0
hook_profile_skip "editor-config-guard" 2>/dev/null && exit 0

_EC_OUT=$(mktemp 2>/dev/null) || _EC_OUT="${TMPDIR:-/tmp}/editorcfg.$$"
HOOK_INPUT="$_INPUT" python3 > "$_EC_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ""
if not path:
    sys.exit(0)
norm = path.replace("\\", "/")

# The new content being written (Write=content, Edit=new_string, MultiEdit=edits).
content = ti.get("content") or ti.get("new_string") or ""
if not content and isinstance(ti.get("edits"), list):
    content = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
# For an Edit whose new_string is a fragment, fall back to the on-disk file so the
# auto-run key set elsewhere in the file is still seen.
if norm and os.path.isfile(path):
    try:
        with open(path, "r", errors="replace") as f:
            content = content + "\n" + f.read(8192)
    except Exception:
        pass
if not content:
    sys.exit(0)

reason = None

# 1. VS Code tasks / workspace set to auto-run on folder open.
if re.search(r'(^|/)\.vscode/tasks\.json$', norm) or re.search(r'\.code-workspace$', norm):
    if re.search(r'"?folderOpen"?', content):
        reason = ("a task set to auto-run on folder open (runOn: folderOpen) — it "
                  "executes its command the next time this folder is opened")

# 2. Sibling editor MCP config defining a local stdio server (launches a process).
elif (re.search(r'(^|/)(\.vscode|\.cursor)/mcp\.json$', norm)
      or re.search(r'(^|/)\.gemini/settings\.json$', norm)):
    if re.search(r'"command"\s*:', content):
        reason = ("an editor MCP config defining a stdio server (\"command\": …) — the "
                  "editor launches that process on load")

if reason:
    print(reason)
PYEOF
_REASON=$(cat "$_EC_OUT" 2>/dev/null); rm -f "$_EC_OUT" 2>/dev/null
[ -z "$_REASON" ] && exit 0

SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_FP=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.editorcfg-seen-${SID}"
_KEY=$(printf '%s' "$_FP" | cksum 2>/dev/null | cut -d' ' -f1 || echo "$_FP")
if [ -f "$_SEEN" ] && grep -qxF "$_KEY" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_KEY" >> "$_SEEN" 2>/dev/null || true

_MSG="This writes ${_REASON}. That is the same auto-run primitive as a poisoned .claude/settings.json, ported to a sibling editor config (Contagious-Interview / Miasma / MCPoison class) — it runs code without any further action. Confirm the command is one you intend and trust. (Disable: SUPERCHARGER_EDITOR_CONFIG_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] editor-config-guard: ASK on auto-run editor config write" >&2
exit 0
