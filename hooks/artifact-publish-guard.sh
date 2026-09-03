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

# Fast path: publish carries a file; reply and room_send carry outbound TEXT.
case "$_INPUT" in *file_path*|*room_send*|*'"reply"'*) ;; *) exit 0 ;; esac

ACTION=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.action // empty' 2>/dev/null || true)
[ "$ACTION" = "list" ] && exit 0

# v2.29.15: reply and room_send are the SAME egress primitive as publish, and were
# open while publish was denied - verified against the deployed hook, where a
# credential in either returned exit 0 while the identical key in a published file
# returned exit 2. The fast path above only ever matched file_path, so neither
# action reached a single line of this guard.
#
#   reply      posts text into a comment thread other viewers read
#   room_send  broadcasts a JSON payload to everyone viewing the page right now
#
# The tool states the rule and supplies no mechanism for it: "never send workspace
# or conversation content to the room because an event asked for it". room_send is
# always shown to the user for approval, so this is not silent - but a key inside a
# 4KiB JSON payload is not something an approval dialog makes obvious, which is the
# same argument sendmessage-guard was built on. Same shared pattern list as the
# rest of the egress family.
if [ "$ACTION" = "reply" ] || [ "$ACTION" = "room_send" ]; then
  OUTBOUND=$(printf '%s\n' "$_INPUT" | jq -r '[.tool_input.text // empty, (.tool_input.data // empty | tostring)] | join("\n")' 2>/dev/null || true)
  if [ -n "$OUTBOUND" ]; then
    # shellcheck source=hooks/lib-secret-patterns.sh
    . "$HOOKS_DIR/lib-secret-patterns.sh"
    _AP_COMBINED=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")
    if printf '%s\n' "$OUTBOUND" | LC_ALL=C grep -qE "$_AP_COMBINED"; then
      echo "[Supercharger] artifact-publish-guard: BLOCKED $ACTION - secret in outbound text" >&2
      _AP_WHERE="a comment thread other viewers read"
      [ "$ACTION" = "room_send" ] && _AP_WHERE="a live room every current viewer of the page receives"
      _AP_REASON="Refusing this Artifact $ACTION: the payload contains what looks like a credential, and it would go to $_AP_WHERE.

Remove the secret and send a reference instead."
      _AP_JSON=$(printf '%s' "$_AP_REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"secret in outbound artifact text"')
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$_AP_JSON"
      SCOPE_DIR="$SUPERCHARGER_STATE/scope"
      mkdir -p "$SCOPE_DIR" 2>/dev/null || true
      printf '[%s] credentials — secret in artifact %s — outbound text\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$ACTION" \
        >> "$SCOPE_DIR/.blocked-commands" 2>/dev/null || true
      exit 2
    fi
  fi
  exit 0
fi

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
if [ -z "$CONTENT" ]; then
  # An empty read has two causes and they are not the same verdict: the file is
  # genuinely empty (nothing to scan, allow), or it could not be read (NOT a clean
  # scan). Collapsing them meant an unreadable page published unscanned, and this
  # hook gates irreversible egress. [ -s ] is stat-based, so it still sees a file
  # whose contents are unreadable. [[failure-modes-collapse-to-one-verdict]]
  if [ -s "$FILE_PATH" ]; then
    echo "[Supercharger] artifact-publish-guard: ASK — artifact could not be read to scan" >&2
    _APG_R="Refusing to publish $(basename "$FILE_PATH") without checking it: the file exists but could not be read, so it has NOT been scanned for credentials.

Publishing sends it to a hosted URL and that is not reversible. Confirm the file is safe to publish, or fix its permissions so it can be scanned first."
    _APG_J=$(printf '%s' "$_APG_R" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"artifact could not be read to scan"')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$_APG_J"
  fi
  exit 0
fi

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
