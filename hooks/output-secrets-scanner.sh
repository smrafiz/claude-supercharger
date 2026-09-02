#!/usr/bin/env bash
# Claude Supercharger — Output Secrets Scanner Hook
# Event: PostToolUse | Matcher: Bash,Read
# Scans tool output for leaked secrets and warns Claude not to repeat them.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.27.31: cwd via the fork-free reader (jq fallback intact). The OUTPUT read
# below has to stay on jq — it pulls the whole of stdout, which is exactly the
# large, escape-carrying value the fast reader is built to refuse — but the cwd
# is a short top-level field and needed one jq fork of its own on every call.
_json_get PROJECT_DIR cwd "$_INPUT" '.cwd // .workspace.current_dir // empty'
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.77: Bash PostToolUse payloads deliver output under `.tool_response.stdout`,
# not `.tool_response.output`. Reading only `.output` made this hook inert for
# every Bash tool call — secrets in `cat ~/.env`, `env`, `printenv` output were
# never scanned. Read both fields, prefer stdout (Bash) then output (Read tool).
OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
if [ -z "$OUTPUT" ]; then
  # v2.9.17: MCP responses carry text under content[]/other shapes, not stdout —
  # for mcp__ tools, stringify the whole tool_response so secrets in an MCP reply
  # are scanned too. Bash/Read behavior is unchanged (still stdout/output).
  OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('tool_response')
tool = str(d.get('tool_name') or '')
if isinstance(r, dict):
    out = r.get('stdout') or r.get('output') or ''
    if not out and tool.startswith('mcp__'):
        out = json.dumps(r)
    print(out)
elif r is not None and tool.startswith('mcp__'):
    print(json.dumps(r))
" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0
[ "${#OUTPUT}" -lt 10 ] && exit 0

# v2.26.44: drop base64 IMAGE payloads before scanning. A browser screenshot
# returns its pixels as base64, and base64 of binary data contains long Base58-safe
# runs — which matched the Bitcoin WIF pattern on nearly every screenshot. The
# pattern is now boundary-anchored (see lib-secret-patterns.sh), but image bytes
# are not a credential channel at all, so scanning them is pure downside: cost and
# false alarms with nothing to find.
#
# Narrowly scoped ON PURPOSE — only base64 tied to an image media_type or a
# data:image/ URI, and only when the payload mentions an image at all. A general
# "strip long base64" rule would also skip a base64-encoded .env, which IS worth
# scanning.
case "$OUTPUT" in
  *image/*|*data:image*)
    OUTPUT=$(printf '%s' "$OUTPUT" | python3 -c "
import re, sys
t = sys.stdin.read()
# \"data\": \"<base64>\" following an image media_type, and data:image/...;base64,<...>
t = re.sub(r'(\"media_type\"\s*:\s*\"image/[^\"]*\"[^}]*?\"data\"\s*:\s*\")[A-Za-z0-9+/=\s]+', r'\1<image-data-stripped>', t)
t = re.sub(r'(\"data\"\s*:\s*\")[A-Za-z0-9+/=]{200,}(\")', r'\1<image-data-stripped>\2', t)
t = re.sub(r'data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+', 'data:image/<stripped>', t)
sys.stdout.write(t)
" 2>/dev/null || printf '%s' "$OUTPUT")
    ;;
esac
[ -z "$OUTPUT" ] && exit 0

# v2.9.8: SECRET_PATTERNS moved to lib-secret-patterns.sh — the single source of
# truth shared with commit-guard.sh (prevents cross-channel parity drift).
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"

COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] output-secrets-scanner: SECRET DETECTED in tool output — warning Claude" >&2
  MSG='[SECURITY] Tool output contains what appears to be a secret/credential. Do NOT repeat, log, or include this value in your response. Refer to it generically (e.g., "the API key") without showing the actual value.'
  MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
  # Signal statusline: scan alert (per-session, not global — v2.6.49)
  SCOPE_DIR="$SUPERCHARGER_STATE/scope"
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -z "$SID" ] && SID="default"
  mkdir -p "$SCOPE_DIR"
  # v4.0.17: record WHICH pattern fired, never the value. A user asked why this
  # warned on a graphql import listing and nothing on disk could answer -- the
  # alert was the bare word "secrets". Reconstructing it meant grepping the raw
  # transcript, and the answer was a DIFFERENT line in the same output. /why reads
  # this file, so it can now name the rule instead of confirming that something
  # happened. Same shape as the Windows arc: knowing THAT is not knowing WHY.
  #
  # The identification loop runs only on the HIT path, which is rare -- the fast
  # path is still one joined grep. The matched TEXT is never written: this file is
  # read back by a diagnostic command, and a scanner that guards against
  # credentials reaching the transcript must not spool them to disk itself.
  _OSS_IDX=""
  _OSS_I=0
  for _oss_p in "${SECRET_PATTERNS[@]}"; do
    if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$_oss_p" 2>/dev/null; then
      _OSS_IDX="${_OSS_IDX:+$_OSS_IDX,}$_OSS_I"
    fi
    _OSS_I=$((_OSS_I + 1))
  done
  printf 'secrets pattern=%s of %s\n' "${_OSS_IDX:-unknown}" "${#SECRET_PATTERNS[@]}" \
    > "$SCOPE_DIR/.scan-alert-${SID}" 2>/dev/null || true
  exit 2
fi

exit 0
