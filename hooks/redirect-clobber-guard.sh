#!/usr/bin/env bash
# Claude Supercharger — Redirect Clobber Guard
# Event: PreToolUse | Matcher: Bash
#
# The Write/Edit review path is guarded (path-guard, confidence-gate, scope-guard),
# but a Bash *redirect* that overwrites a file bypasses ALL of them — `echo x > app.ts`,
# `sed -i '…' app.ts`, `tee app.ts` truncate a tracked source file with no read-before-
# write, no path check, nothing. This is the biggest Bash write blind spot (cross-channel
# parity gap). This ASKS (not deny) — a deliberate redirect is occasionally legit and a
# human can confirm — and ONLY when the target is a git-TRACKED file (overwriting a new /
# temp / generated file is fine), once per file per session.
#
# Scope is deliberately narrow to keep false positives near zero: truncating `>` (not
# `>>`/`2>`/`>&`), `sed -i`, `tee` (no -a), `dd of=`, `truncate`, and `cp`/`mv` overwriting
# a tracked destination (recursive dir copies skipped; a rename to a NEW path stays
# silent) — targeting tracked source. Disable: SUPERCHARGER_REDIRECT_CLOBBER_GUARD=0
set -uo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
[ "${SUPERCHARGER_REDIRECT_CLOBBER_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: bail with ZERO forks unless the payload could contain a clobber op.
# Superset match on the raw stdin — precise parsing happens only past this gate.
case "$_INPUT" in
  *'>'*|*'sed '*|*'sed\t'*|*'tee '*|*'dd '*|*'truncate '*|*'cp '*|*'mv '*) ;;
  *) exit 0 ;;
esac

# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "redirect-clobber-guard" && exit 0
hook_profile_skip "redirect-clobber-guard" && exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL_NAME" = "Bash" ] || exit 0
CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

# Parse clobber targets and return the FIRST that is git-tracked (empty = nothing to
# ask). The parser lives in a sibling .py (deployed alongside — see lib/hooks.sh) to
# avoid heredoc-in-shell quoting hazards.
TARGET=$(CMD="$CMD" PROJECT_DIR="$PROJECT_DIR" python3 "$HOOKS_DIR/redirect-clobber-detect.py" 2>/dev/null || true)

[ -z "$TARGET" ] && exit 0

# Ask once per (file, session) — don't nag on repeated touches.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
ACK_FILE="$_SC_STATE/scope/.redirect-clobber-ack-${SID:-nosession}"
if [ -f "$ACK_FILE" ] && grep -qxF "$TARGET" "$ACK_FILE" 2>/dev/null; then
  exit 0
fi
mkdir -p "$_SC_STATE/scope" 2>/dev/null || true
printf '%s\n' "$TARGET" >> "$ACK_FILE" 2>/dev/null || true

BASE="${TARGET##*/}"
echo "" >&2
echo "Supercharger: this Bash command overwrites the tracked file '$BASE' via a redirect / in-place edit / move-copy." >&2
echo "  That bypasses the Edit/Write review path (path-guard, confidence-gate, scope-guard) — no read-before-write, no path check." >&2
echo "  Prefer Edit/Write for source changes. Confirm only if this overwrite is intended. (Asked once per file per session.)" >&2
echo "" >&2

RSN=$(printf "Bash overwrites tracked source '%s' via a redirect/in-place edit/move (>, sed -i, tee, dd, truncate, cp, mv) — this bypasses the Edit/Write guards (read-before-write, path-guard). Prefer Edit/Write; confirm only if the overwrite is intended." "$TARGET" \
  | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"Bash redirect overwrites tracked source — prefer Edit/Write"')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
exit 0
