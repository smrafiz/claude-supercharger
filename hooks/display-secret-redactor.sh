#!/usr/bin/env bash
# Claude Supercharger — Display Secret Redactor
# Event: MessageDisplay | Matcher: (none)
#
# Last line of defense, and the only one that protects the HUMAN rather than the
# model. output-secrets-scanner tells Claude not to repeat a credential it just
# read; prompt-secret-guard catches one on the way in. Both act on Claude's
# context. If a value reaches an assistant message anyway — Claude quotes a config
# it read, pastes a stack trace with a token in it — it lands in your terminal, in
# your scrollback, and in any screen share or recording running at the time.
#
# MessageDisplay's `displayContent` rewrites what is rendered. It does not change
# what Claude said or knows, so this is cosmetic in exactly the way that matters:
# the value stops being on screen.
#
# Patterns come from lib-secret-patterns.sh — the same source of truth as the other
# two scanners, so the three channels cannot drift apart.
set -euo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-timing.sh
. "$HOOKS_DIR/lib-timing.sh" 2>/dev/null || true

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

[ "${#_INPUT}" -lt 24 ] && exit 0

# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"
COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

# v2.26.12: gate on the RAW payload, before any parsing. This hook is blocking and
# fires on every assistant message, and the first version parsed the JSON with a
# python3 fork *before* reaching this grep — 27.7 ms per message measured, four
# times the warm statusline render, on a path the user waits behind. The comment
# claimed the grep came first; the code did not. Now: bash startup plus one grep,
# and python is forked only when a credential is actually present.
#
# Matching the raw JSON rather than the extracted string is safe for this purpose.
# Every SECRET_PATTERNS shape is alphanumerics with `-`, `_`, `/`, `+`, `.` and `:`,
# none of which JSON escapes, so a credential in message_text appears verbatim in
# the payload. The cost of the choice is direction-of-error: a token appearing in
# some other field would also trip the gate, and then the python pass simply finds
# nothing in message_text and exits — a wasted fork on a rare input, never a miss.
printf '%s\n' "$_INPUT" | LC_ALL=C grep -qE "$COMBINED_PATTERN" || exit 0

TEXT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('message_text') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$TEXT" ] && exit 0
[ "${#TEXT}" -lt 10 ] && exit 0

# Re-check the extracted text: the raw-payload gate above can match a credential
# that lives in another field, and redacting a message that never contained one
# would be a lie about what was on screen.
printf '%s\n' "$TEXT" | LC_ALL=C grep -qE "$COMBINED_PATTERN" || exit 0

echo "[Supercharger] display-secret-redactor: redacting a credential from the rendered message" >&2

PAT="$COMBINED_PATTERN" TEXT="$TEXT" python3 <<'PY' 2>/dev/null || exit 0
import json, os, re, sys

text = os.environ['TEXT']
try:
    rx = re.compile(os.environ['PAT'])
except re.error:
    # A pattern this hook cannot compile is a pattern it cannot redact. Emitting
    # nothing leaves the message untouched, which is the correct failure: showing
    # the real text is what happens today, and a crash here must not blank a reply.
    sys.exit(0)

def mask(m):
    s = m.group(0)
    # Keep a short prefix so the reader can still tell WHICH credential leaked and
    # match it against a rotation list. Four characters is not enough to use.
    return (s[:4] + '…[redacted ' + str(len(s)) + ' chars]') if len(s) > 12 else '…[redacted]'

redacted, n = rx.subn(mask, text)
if not n:
    sys.exit(0)

print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'MessageDisplay',
        'displayContent': redacted,
    },
    'systemMessage': '[SECURITY] %d credential-shaped value(s) redacted from the displayed message. Claude still has the original in context — rotate the credential if this was real.' % n,
}))
PY
exit 0
