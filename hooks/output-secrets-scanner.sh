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
# A guard that has lost its libs must FAIL OPEN here, not block:
# tests/test-prompt-secret-guard.sh copies this hook WITHOUT its siblings and
# asserts exit 0, because a broken install that blocks every prompt is worse
# than one that scans nothing. The unconditional source regressed that.
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh" 2>/dev/null || true
_INPUT=""   # set -u: must exist even when the lib below is absent
# No inline-read fallback on purpose. Re-adding that line is exactly what
# tests/test-stdin-timeout.sh bans, and it caught this on the first run. With the
# lib absent, _INPUT simply stays empty and the hook's own empty-input path exits
# 0 — the fail-open the missing-lib test requires, without a second copy of the
# read that the shared helper exists to replace.
if command -v sc_read_input_warn >/dev/null 2>&1; then
  sc_read_input_warn _INPUT "output-secrets-scanner"
fi
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
  # transcript, and the answer was a DIFFERENT line in the same output. /sc-why reads
  # this file, so it can now name the rule instead of confirming that something
  # happened. Same shape as the Windows arc: knowing THAT is not knowing WHY.
  #
  # The identification loop runs only on the HIT path, which is rare -- the fast
  # path is still one joined grep. The matched TEXT is never written: this file is
  # read back by a diagnostic command, and a scanner that guards against
  # credentials reaching the transcript must not spool them to disk itself.
  _OSS_IDX=""
  _OSS_HIT=""
  _OSS_I=0
  for _oss_p in "${SECRET_PATTERNS[@]}"; do
    if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$_oss_p" 2>/dev/null; then
      _OSS_IDX="${_OSS_IDX:+$_OSS_IDX,}$_OSS_I"
      _OSS_HIT="$_OSS_HIT$_oss_p"$'\n'
    fi
    _OSS_I=$((_OSS_I + 1))
  done
  # The breadcrumb is keyed by session_id, which a subagent's hooks share with the
  # parent, so a subagent's hit lands on the parent's statusline. Say so.
  _OSS_SRC=""
  case "$_INPUT" in *'"agent_id"'*) _OSS_SRC=" source=subagent" ;; esac
  printf 'secrets pattern=%s of %s%s\n' "${_OSS_IDX:-unknown}" "${#SECRET_PATTERNS[@]}" "$_OSS_SRC" \
    > "$SCOPE_DIR/.scan-alert-${SID}" 2>/dev/null || true

  # Attribution. This hook is asyncRewake: on exit 2 the ONLY thing Claude Code
  # delivers is stderr, framed as `Stop hook blocking error from command
  # "PostToolUse:Bash"` (the systemMessage above is ignored for async hooks, see
  # docs/HOOK_AUTHORING.md "Async hooks cannot steer anything"), and a rewake
  # raised inside a subagent wakes the PARENT. The old fixed line named no tool,
  # command, pattern or source, so a fake fixture key printed by a background
  # subagent's test run read as the parent's own blocking error (8x in one session,
  # 2026-10-12/13). Name all four. Labels come from the pattern TEXT
  # (lib_outbound_secret._LABELS), and the command prefix is redacted with the same
  # pattern set BEFORE it is cut, so a secret can never be half-shown.
  _OSS_LINE=$(printf '%s' "$_INPUT" | OSS_HIT="$_OSS_HIT" OSS_ALL="$(IFS=$'\n'; echo "${SECRET_PATTERNS[*]}")" \
    HOOKS_DIR="$HOOKS_DIR" python3 -c '
import json, os, re, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import lib_outbound_secret as los
d = json.load(sys.stdin)
tool = str(d.get("tool_name") or "tool")
ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
subj = ""
if not tool.startswith("mcp__"):
    for k in ("command", "file_path", "url", "query"):
        if isinstance(ti.get(k), str) and ti[k]:
            subj = ti[k]
            break
subj = " ".join(subj[:2000].split())
for rx, _ in los._compile(os.environ.get("OSS_ALL", "")) + [(re.compile(r"[A-Fa-f0-9]{32,}"), "")]:
    subj = rx.sub("[REDACTED]", subj)
if len(subj) > 60:
    subj = subj[:60] + "..."
labels = []
for _, l in los._compile(os.environ.get("OSS_HIT", "")):
    if l not in labels:
        labels.append(l)
src = ""
if d.get("agent_id"):
    at = re.sub(r"[^A-Za-z0-9_.:-]", "", str(d.get("agent_type") or ""))[:40]
    src = ", from a subagent" + (" (%s)" % at if at else "")
print("[Supercharger] output-secrets-scanner (warning, nothing was blocked): %s output%s matched %s%s. "
      "Do not repeat, log or quote the value; refer to it generically. "
      "If it is a test fixture, carry on." % (
          tool, (" of `%s`" % subj) if subj else "", ", ".join(labels) or "a secret pattern", src))
' 2>/dev/null) || _OSS_LINE=""
  [ -n "$_OSS_LINE" ] || _OSS_LINE="[Supercharger] output-secrets-scanner (warning, nothing was blocked): tool output contains a secret-shaped value. Do not repeat, log or quote it."
  printf '%s\n' "$_OSS_LINE" >&2
  exit 2
fi

exit 0
