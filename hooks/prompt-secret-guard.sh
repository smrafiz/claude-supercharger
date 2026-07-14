#!/usr/bin/env bash
# Claude Supercharger — Prompt Secret Guard
# Event: UserPromptSubmit | Matcher: (none)
# Blocks a prompt that contains what looks like a LIVE credential BEFORE it is
# sent to the model and written to the on-disk transcript JSONL. Completes the
# secret-scanning coverage:
#   - output-secrets-scanner  scans tool OUTPUT (Bash/Read)
#   - commit-secret-guard     scans the STAGED git diff
#   - code-security-scanner   scans Write/Edit CONTENT
# None of them saw the user's own typed prompt, so a pasted AWS key / token /
# private key / wallet key reached Anthropic AND the local transcript unscanned.
# Reuses the shared lib-secret-patterns.sh set (drift-proof, low-FP). Reports
# only THAT a secret was found — never the value. Fully fail-open.
# Idea from dwarvesf/claude-guardrails (scan-secrets.sh).
#
# Blocks via exit 2 (UserPromptSubmit blocking contract — verified against CC
# hook docs: exit 2 stops the prompt, stderr is surfaced). The secret never
# reaches the model.
#
# Override (intentional paste of a revoked/test value): SUPERCHARGER_ALLOW_PROMPT_SECRETS=1
# Disable entirely:                                     SUPERCHARGER_PROMPT_SECRET_GUARD=0

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_PROMPT_SECRET_GUARD:-1}" = "0" ] && exit 0
[ "${SUPERCHARGER_ALLOW_PROMPT_SECRETS:-0}" = "1" ] && exit 0

_INPUT=$(cat)

PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi
[ -z "$PROMPT" ] && exit 0

# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"
COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$PROMPT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  MSG='[Supercharger] prompt-secret-guard: your prompt contains a value matching a known live-credential format (API key, token, private key, or wallet key). Blocked BEFORE it is sent to the model and written to the local transcript. Remove or redact the secret and resend. If this is intentional (e.g. a revoked or test value), resend with SUPERCHARGER_ALLOW_PROMPT_SECRETS=1 set; or disable this guard with SUPERCHARGER_PROMPT_SECRET_GUARD=0.'
  echo "$MSG" >&2
  # Log the block (never the value).
  BLOG="$HOME/.claude/supercharger/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] secret in user prompt — blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"
  echo "secrets" > "$HOME/.claude/supercharger/scope/.scan-alert-${SID}" 2>/dev/null || true
  exit 2
fi

exit 0
