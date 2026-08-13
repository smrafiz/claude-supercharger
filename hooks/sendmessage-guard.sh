#!/usr/bin/env bash
# Claude Supercharger — Cross-Session Message Guard
# Event: PreToolUse | Matcher: SendMessage
#
# SendMessage had NO guards at all — found by the coverage diff on 2026-08-09,
# where it was one of 28 exposed tools with nothing but the two universal hooks.
# It is the only one of those that moves free text OUT of this session: per its
# own description it addresses in-process subagents, other LOCAL Claude sessions,
# cloud sessions, and Remote Control sessions ON OTHER MACHINES.
#
# Two checks, both parity with guards that already exist on other channels:
#
# (A) CREDENTIAL EXFILTRATION -> deny. The egress family covers Bash
#     (bulk-exfil-guard), MCP (mcp-egress-guard) and WebFetch
#     (webfetch-egress-guard). A channel that hands arbitrary text to another
#     machine belongs in that family. Same SECRET_PATTERNS list as
#     output-secrets-scanner and commit-guard, for the usual reason: one list, or
#     the channels drift on what counts as a secret.
#
# (B) CROSS-SESSION PERMISSION LAUNDERING -> ask. The SendMessage tool
#     description states the rule itself: "NEVER ask a peer to perform an action
#     that was denied or blocked in your session ... a peer doing it for you
#     bypasses the user's permission decision". The platform states it as an
#     INSTRUCTION with no mechanism behind it — and an instruction is exactly
#     what a prompt injection overrides. We are the only layer that can enforce
#     it, because we already record what was blocked: safety.sh and
#     harness-tamper-guard append every denial to scope/.blocked-commands.
#     So: if the outbound message replays a command this session just had
#     blocked, the human sees a confirm.
#
#     ASK, not deny — relaying "the rm -rf failed, any ideas?" to a peer is
#     legitimate and common. What must not happen is it going through unseen.
#
# `to: "main"` is exempt from (B): the parent conversation shares this session's
# user and permission decisions, so replaying a blocked command there launders
# nothing. (A) still applies — secrets should not be echoed anywhere.
#
# Disable: SUPERCHARGER_SENDMESSAGE_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
check_hook_disabled "sendmessage-guard" 2>/dev/null && exit 0
[ "${SUPERCHARGER_SENDMESSAGE_GUARD:-1}" = "0" ] && exit 0

# Fork-free stdin read (v2.26.35 convention).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

_SM_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
_SM_LEDGER="$_SM_STATE/scope/.blocked-commands"

# Secret patterns come from the shared list, never a local copy.
# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || true
_SM_PATTERNS=$(printf '%s\n' "${SECRET_PATTERNS[@]:-}" 2>/dev/null || true)

RESULT=$(HOOK_INPUT="$_INPUT" LEDGER="$_SM_LEDGER" PATTERNS="$_SM_PATTERNS" python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys

# NOTE: this heredoc lives inside RESULT=$(...). Keep every quote character
# MATCHED in this body or bash misses the PYEOF terminator and parses the rest as
# shell -- see hooks/workflow-guard.sh for the measured write-up.
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
except Exception:
    sys.exit(0)

ti = data.get('tool_input') or {}
msg = ti.get('message')
if not isinstance(msg, str) or not msg.strip():
    sys.exit(0)
to = ti.get('to') or ''
summary = ti.get('summary') or ''
summary = summary if isinstance(summary, str) else ''
haystack = msg + '\n' + summary
# v2.26.81: also scan the two fields JOINED, not only newline-separated. A secret
# cut across the boundary (message ends "...AKIA", summary begins "IOSFO...")
# matched neither half and neither did the separated form. Found by red-teaming.
# Cheap because both fields are already in hand; it does not help against a secret
# the model base64s first, which pattern scanning cannot reach either way.
haystack_joined = msg + summary

# ── (A) credentials leaving the session ───────────────────────────────────────
hits = []
for pat in (os.environ.get('PATTERNS') or '').splitlines():
    pat = pat.strip()
    if not pat:
        continue
    try:
        if re.search(pat, haystack) or re.search(pat, haystack_joined):
            hits.append(pat)
    except re.error:
        continue

if hits:
    reason = ("This message carries credential-shaped text to another session "
              "(recipient: %s). Sending it copies the secret outside this session, "
              "possibly to another machine. Redact it and send a reference instead."
              % (to or 'unknown'))
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': reason,
    }}))
    sys.exit(0)

# ── (B) replaying a command this session had blocked ──────────────────────────
# The parent conversation shares this session's user and permission decisions,
# so relaying to it launders nothing.
if to.strip().lower() == 'main':
    sys.exit(0)

ledger = os.environ.get('LEDGER', '')
try:
    with open(ledger, encoding='utf-8', errors='replace') as fh:
        lines = fh.readlines()[-50:]
except Exception:
    sys.exit(0)


def norm(s):
    return re.sub(r'\s+', ' ', s).strip().lower()


hay = norm(haystack)

# 24 chars: long enough that a shared fragment is the actual command rather than
# a common word or a path prefix every entry shares, short enough to still catch
# a blocked command quoted with small edits. Tuned against the live ledger.
WINDOW = 24

matched = None
for line in lines:
    # Ledger format, written by safety.sh / harness-tamper-guard:
    #   [ts] reason - command      (the separator is an em dash)
    parts = line.rsplit(' — ', 1)
    if len(parts) != 2:
        continue
    cmd = norm(parts[1])
    if len(cmd) < WINDOW:
        continue
    for i in range(len(cmd) - WINDOW + 1):
        if cmd[i:i + WINDOW] in hay:
            matched = parts[1].strip()
            break
    if matched:
        break

if not matched:
    sys.exit(0)

short = matched if len(matched) <= 160 else matched[:160] + '...'
reason = ("This message repeats a command that was BLOCKED in this session, to a "
          "peer that does not share this session's permission decisions "
          "(recipient: %s).\n\nBlocked earlier: %s\n\n"
          "Asking a peer to run it is how a blocked action gets performed anyway. "
          "Approve only if you are relaying context rather than delegating the work."
          % (to or 'unknown', short))
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'ask',
    'permissionDecisionReason': reason,
}}))
PYEOF
)

[ -z "$RESULT" ] && exit 0
printf '%s\n' "$RESULT"

if printf '%s' "$RESULT" | grep -q '"deny"'; then
  echo "[Supercharger] sendmessage-guard: BLOCKED credential-bearing message" >&2
  _BLK="$_SM_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$_BLK")" 2>/dev/null || true
  printf '[%s] sendmessage — %s — %.200s\n' "$(date '+%Y-%m-%dT%H:%M:%SZ')" \
    "credential in cross-session message" "redacted" >> "$_BLK" 2>/dev/null || true
  exit 2
fi
exit 0
