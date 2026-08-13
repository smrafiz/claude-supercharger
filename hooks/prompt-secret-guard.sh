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
# Disable: SUPERCHARGER_PROMPT_SECRET_GUARD=0

set -uo pipefail
# shellcheck source=hooks/lib-json-fast.sh
. "${BASH_SOURCE[0]%/*}/lib-json-fast.sh" 2>/dev/null || true
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_PROMPT_SECRET_GUARD:-1}" = "0" ] && exit 0
[ "${SUPERCHARGER_ALLOW_PROMPT_SECRETS:-0}" = "1" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Pre-initialised: if lib-json-fast is absent _json_get is undefined, and

# under `set -u` an unset var here is FATAL — which turned a missing lib

# into a fail-CLOSED block. Empty keeps the fail-open contract.

PROMPT=""

_json_get PROMPT prompt "$_INPUT" '.prompt // empty'
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi
[ -z "$PROMPT" ] && exit 0

# shellcheck source=hooks/lib-secret-patterns.sh
# 2.21.5: fail OPEN if the pattern lib can't be sourced or yields no patterns.
# Without this, a broken/missing lib left COMBINED_PATTERN empty (SECRET_PATTERNS
# unset under set -u empties the subshell), and `grep -qE ""` matches EVERY
# prompt → exit 2 blocked every prompt — the opposite of this guard's documented
# fail-open contract. Never block a prompt just because the lib is unavailable.
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || exit 0
COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]:-}")
[ -z "$COMBINED_PATTERN" ] && exit 0

# v2.26.29: `0x` + 64 hex is an EVM wallet private key AND, byte for byte, a
# public transaction hash, block hash or any other 32-byte on-chain identifier.
# There is nothing in the value to tell them apart, so blocking it meant a prompt
# asking about a PUBLIC identifier was refused outright. Held as a known FP since
# the v2.22.10 audit; the argument for keeping it was that a bare wallet key with
# no label is the realistic leak and a keyword requirement would miss it.
#
# Resolution: ambiguous patterns WARN on this channel instead of blocking. The
# other channels are untouched — output-secrets-scanner still blocks the value in
# tool output and display-secret-redactor still redacts it on the way to the
# screen — so a real wallet key stays covered everywhere it would be echoed. What
# is given up is silent prevention of a key reaching the transcript; the user is
# told instead of overruled.
#
# Matched by exact pattern string. If lib-secret-patterns.sh rewrites this regex
# the match stops working and the pattern simply goes back to blocking — the
# fail-safe direction. test-prompt-secret-ambiguous.sh pins that it still matches.
AMBIGUOUS_PATTERNS=('0x[a-fA-F0-9]{64}')

# v2.26.35: cheap pre-filter. The partition loop plus two greps below used to run
# on EVERY prompt, including the overwhelming majority containing no secret-shaped
# value at all — measured +6.6ms per prompt (13.2 -> 19.8, a 50% regression this
# hook did not have before 2.26.29). One combined grep answers "is any of this
# even present?" for the common case, which is what the hook did originally; the
# partition only happens once something has actually matched.
if ! printf '%s\n' "$PROMPT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  exit 0
fi

BLOCK_LIST=()
WARN_LIST=()
for _p in "${SECRET_PATTERNS[@]:-}"; do
  _is_amb=0
  for _a in "${AMBIGUOUS_PATTERNS[@]:-}"; do
    if [ "$_p" = "$_a" ]; then _is_amb=1; break; fi
  done
  if [ "$_is_amb" = "1" ]; then WARN_LIST+=("$_p"); else BLOCK_LIST+=("$_p"); fi
done
BLOCK_PATTERN=$(IFS='|'; echo "${BLOCK_LIST[*]:-}")
WARN_PATTERN=$(IFS='|'; echo "${WARN_LIST[*]:-}")

# Ambiguous-only match: warn, do not block. Checked after the blocking set below,
# so a prompt carrying both a real credential and a tx hash is still blocked.
if [ -n "$WARN_PATTERN" ] \
   && ! printf '%s\n' "$PROMPT" | LC_ALL=C grep -qE "$BLOCK_PATTERN" \
   && printf '%s\n' "$PROMPT" | LC_ALL=C grep -qE "$WARN_PATTERN"; then
  echo '[Supercharger] prompt-secret-guard: your prompt contains a 0x + 64-hex value. That is the format of an EVM wallet PRIVATE KEY as well as of a public transaction or block hash — they are indistinguishable, so this is a warning, not a block. If it is a private key, stop and rotate it: it is now in the transcript. Silence this with SUPERCHARGER_PROMPT_SECRET_GUARD=0.' >&2
  # UserPromptSubmit stdout on exit 0 is added to the model's context.
  echo 'Note: the user prompt contains a 0x+64-hex value that may be a wallet private key. Do not repeat, echo, or log the value; refer to it generically.'
  BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] ambiguous secret pattern in user prompt — warned, not blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  exit 0
fi

if [ -n "$BLOCK_PATTERN" ] && printf '%s\n' "$PROMPT" | LC_ALL=C grep -qE "$BLOCK_PATTERN"; then
  MSG='[Supercharger] prompt-secret-guard: your prompt contains a value matching a known live-credential format (API key, token, private key, or wallet key). Blocked BEFORE it is sent to the model and written to the local transcript. Remove or redact the secret and resend. If this is intentional (e.g. a revoked or test value), resend with SUPERCHARGER_ALLOW_PROMPT_SECRETS=1 set; or disable this guard with SUPERCHARGER_PROMPT_SECRET_GUARD=0.'
  echo "$MSG" >&2
  # Log the block (never the value).
  BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] secret in user prompt — blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"
  echo "secrets" > "$SUPERCHARGER_STATE/scope/.scan-alert-${SID}" 2>/dev/null || true
  exit 2
fi

exit 0
