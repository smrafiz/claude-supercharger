#!/usr/bin/env bash
# Claude Supercharger — Conflict Marker Guard
# Event: PostToolUse | Matcher: Write, Edit, MultiEdit
#
# Catches a git merge-conflict marker left in a written file — an unresolved or
# half-resolved conflict (`<<<<<<< HEAD` … `=======` … `>>>>>>> branch`) that the
# agent "resolved" but left a marker in, or wrote as content. The file won't
# compile/parse; the failure surfaces a round-trip later. WARN only
# (additionalContext) — never blocks. Line-anchored on the 7-char angle markers
# (`<<<<<<< ` / `>>>>>>> `) so heredocs (`<<EOF`), bit-shift (`>>`), and prose
# rarely trip; a bare `=======` line is counted only alongside an angle marker (it
# doubles as a text separator). Documentation / patch files are skipped (markers
# there are often illustrative or 7-deep email quotes). Fail-open; disable with
# SUPERCHARGER_CONFLICT_MARKER_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_CONFLICT_MARKER_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
# Fast-path: needs a 7-char angle run somewhere in the payload.
case "$_INPUT" in *'<<<<<<<'*|*'>>>>>>>'*) : ;; *) exit 0 ;; esac
check_hook_disabled "conflict-marker-guard" 2>/dev/null && exit 0
hook_profile_skip "conflict-marker-guard" 2>/dev/null && exit 0

_CM_OUT=$(mktemp 2>/dev/null) || _CM_OUT="${TMPDIR:-/tmp}/conflictmk.$$"
HOOK_INPUT="$_INPUT" python3 > "$_CM_OUT" 2>/dev/null <<'PYEOF'
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
base = path.rsplit("/", 1)[-1].lower()
ext = "." + base.rsplit(".", 1)[-1] if "." in base else ""
# Docs / patches: markers are often illustrative or 7-deep email quotes ('>>>>>>> ').
SKIP = {".md", ".markdown", ".mdx", ".rst", ".txt", ".adoc", ".org",
        ".eml", ".mbox", ".patch", ".diff", ".rej"}
if ext in SKIP:
    sys.exit(0)

content = ti.get("content") or ti.get("new_string") or ""
if not content and isinstance(ti.get("edits"), list):
    content = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
if not content:
    sys.exit(0)

START = re.compile(r'^' + '<' * 7 + r' ', re.M)
END = re.compile(r'^' + '>' * 7 + r' ', re.M)
MID = re.compile(r'^' + '=' * 7 + r'$', re.M)

hits = []
if START.search(content):
    hits.append('<' * 7)
if END.search(content):
    hits.append('>' * 7)
# a bare 7-'=' line counts only when an angle marker confirms a real conflict
if hits and MID.search(content):
    hits.append('=' * 7)

if hits:
    print(" ".join(hits))
PYEOF
_HITS=$(cat "$_CM_OUT" 2>/dev/null); rm -f "$_CM_OUT" 2>/dev/null
[ -z "$_HITS" ] && exit 0

_MSG="[merge conflict] The written file contains unresolved git conflict marker(s): ${_HITS}. This is a half-resolved or accidentally-written merge conflict — the file won't compile/parse. Remove the markers and keep the intended content before it fails at build/run. (Disable: SUPERCHARGER_CONFLICT_MARKER_GUARD=0)"
_JSON=$(printf '%s' "$_MSG" | python3 -c "import sys,json;print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.stdin.read()}}))" 2>/dev/null || true)
[ -z "$_JSON" ] && exit 0
printf '%s\n' "$_JSON"
echo "[Supercharger] conflict-marker-guard: unresolved conflict marker(s) — ${_HITS}" >&2
exit 0
