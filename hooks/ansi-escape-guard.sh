#!/usr/bin/env bash
# Claude Supercharger — ANSI Escape Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# A raw ANSI escape written into a file can carry a HIDDEN payload: the SGR conceal
# code (ESC[8m … ESC[0m) renders text invisible to a human but fully readable by the
# model / next reviewer — a hidden-instruction trap — and cursor-scrub sequences
# overwrite already-printed "safe" output to spoof it (2026 Codex-CLI ANSI-injection
# RCE; macOS Terminal DiLLMa DNS-exfil). This ASKS before a write whose content
# contains a RAW ESC byte (0x1b) forming a conceal or an OSC-8 hyperlink — a raw ESC
# in source is itself the anomaly (a normal string literal uses the TEXTUAL "\x1b",
# which does NOT fire, so terminal libraries defining escape constants are unaffected).
# Terminal-recording / snapshot fixtures and docs are skipped. Plain SGR *color*
# (ESC[31m …) is NOT flagged — only content-HIDING codes. Asks once per file per
# session. Fail-open; disable with SUPERCHARGER_ANSI_ESCAPE_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_ANSI_ESCAPE_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: need an ESC (0x1b) present — as a raw byte OR (the usual JSON
# transport form) escaped. Needle built split (backslash + "u001b") so no
# tool folds it to a literal ESC. Python re-checks the decoded content exactly.
_ESCN=$(printf '\\u001b'); _ESCNU=$(printf '\\u001B')
case "$_INPUT" in *"$_ESCN"*|*"$_ESCNU"*|*$'\x1b'*) : ;; *) exit 0 ;; esac
check_hook_disabled "ansi-escape-guard" 2>/dev/null && exit 0
hook_profile_skip "ansi-escape-guard" 2>/dev/null && exit 0

_AE_OUT=$(mktemp 2>/dev/null) || _AE_OUT="${TMPDIR:-/tmp}/ansiesc.$$"
HOOK_INPUT="$_INPUT" python3 > "$_AE_OUT" 2>/dev/null <<'PYEOF'
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
low = path.lower()
base = low.rsplit("/", 1)[-1]
ext = "." + base.rsplit(".", 1)[-1] if "." in base else ""
# Terminal-recording / snapshot fixtures + docs legitimately hold raw escapes.
SKIP_EXT = {".cast", ".ansi", ".snap", ".log", ".vhs", ".tape",
            ".md", ".markdown", ".mdx", ".rst", ".txt"}
if ext in SKIP_EXT:
    sys.exit(0)
if re.search(r'(^|/)(__snapshots__|snapshots|fixtures?|testdata|__fixtures__)/', low):
    sys.exit(0)

content = ti.get("content") or ti.get("new_string") or ""
if not content and isinstance(ti.get("edits"), list):
    content = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
if "\x1b" not in content:
    sys.exit(0)

ESC = "\x1b"
hits = []
# Raw-ESC SGR conceal — invisible text (the hidden-instruction primitive).
if re.search(re.escape(ESC) + r"\[8m", content):
    hits.append("SGR conceal ESC[8m (renders following text invisible)")
# Raw-ESC OSC-8 hyperlink — can mask a link's real target.
if re.search(re.escape(ESC) + r"\]8;;", content):
    hits.append("OSC-8 hyperlink ESC]8;; (masks the real link target)")

if hits:
    print(" ; ".join(hits))
PYEOF
_HITS=$(cat "$_AE_OUT" 2>/dev/null); rm -f "$_AE_OUT" 2>/dev/null
[ -z "$_HITS" ] && exit 0

SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_FP=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.ansiesc-seen-${SID}"
_KEY=$(printf '%s' "$_FP" | cksum 2>/dev/null | cut -d' ' -f1 || echo "$_FP")
if [ -f "$_SEEN" ] && grep -qxF "$_KEY" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_KEY" >> "$_SEEN" 2>/dev/null || true

_MSG="This writes a raw ANSI escape that HIDES content: ${_HITS}. Invisible/masked text is a hidden-instruction or output-spoofing trap (2026 Codex-CLI ANSI-injection / DiLLMa class) — a human reviewer won't see what the model and terminal do. Confirm you intend a raw escape here (a normal string constant uses the textual \\x1b, which is fine). (Disable: SUPERCHARGER_ANSI_ESCAPE_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] ansi-escape-guard: ASK on raw ANSI content-hiding escape write" >&2
exit 0
