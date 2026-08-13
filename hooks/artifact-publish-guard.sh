#!/usr/bin/env bash
# Claude Supercharger — Artifact Publish Guard
# Event: PreToolUse | Matcher: Artifact
#
# The Artifact tool renders a local file to a page hosted on claude.ai and
# returns a URL. That is a FIRST-CLASS EGRESS PRIMITIVE — content leaves the
# machine — and nothing guarded it. The exfil family all match other channels:
#   bulk-exfil-guard     Bash,PowerShell
#   output-secrets-scanner  Bash,Read,WebFetch,WebSearch,mcp__  (and PostToolUse,
#                           which is after the publish already happened)
#   mcp-egress-guard     mcp__*
# So a file containing an API key could be published with no check at all.
#
# Publishing is effectively irreversible: the page may be cached or indexed even
# if it is later deleted, and the URL can be shared onward. That asymmetry is why
# a detected secret is a DENY here rather than the warn that output-secrets-scanner
# uses — that hook warns Claude not to REPEAT a value it already saw locally; this
# one stops the value leaving the machine.
#
# Scope is deliberately narrow: only an actual publish. `action: "list"` merely
# enumerates existing artifacts and sends nothing, so it is not touched.
#
# Disable: SUPERCHARGER_ARTIFACT_GUARD=0
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "artifact-publish-guard" && exit 0
[ "${SUPERCHARGER_ARTIFACT_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read (no $(cat) fork).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Fast path: nothing to do unless this is a publish with a file.
case "$_INPUT" in *file_path*) ;; *) exit 0 ;; esac

ACTION=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.action // empty' 2>/dev/null || true)
[ "$ACTION" = "list" ] && exit 0

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  /*) ;;
  *)  CWD=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
      [ -n "$CWD" ] && FILE_PATH="$CWD/$FILE_PATH" ;;
esac
[ -f "$FILE_PATH" ] || exit 0

# Bound the read. A 16MB artifact would otherwise be grepped in full on a hook
# that must stay responsive; secrets in a page live in its text, not megabytes in.
CONTENT=$(head -c 262144 "$FILE_PATH" 2>/dev/null || true)
[ -z "$CONTENT" ] && exit 0

# Single source of truth, shared with output-secrets-scanner and commit-guard.
# Add a pattern THERE, never here (v2.9.8 — cross-channel parity drift).
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"
COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$CONTENT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] artifact-publish-guard: BLOCKED publish — secret in artifact" >&2
  REASON="Refusing to publish $(basename "$FILE_PATH"): it contains what looks like a credential (API key, token, or private key).

Publishing sends this file to a hosted URL. That is not reversible — the page can be cached, indexed, or shared onward even if you delete it later.

Remove the secret from the file, then publish again. If it is a placeholder or test fixture, rename the value so it does not match a live credential shape, or set disableSecurityCategories: [\"credentials\"] for this project."
  REASON_JSON=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"secret detected in artifact"')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$REASON_JSON"

  # Block ledger — /why and the session [BLOCKS] summary read this.
  SCOPE_DIR="$SUPERCHARGER_STATE/scope"
  mkdir -p "$SCOPE_DIR" 2>/dev/null || true
  printf '[%s] credentials — secret in published artifact — %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$(basename "$FILE_PATH")" \
    >> "$SCOPE_DIR/.blocked-commands" 2>/dev/null || true
  exit 2
fi

exit 0
