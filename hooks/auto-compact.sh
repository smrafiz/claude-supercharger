#!/usr/bin/env bash
# Claude Supercharger — Auto Compact Advisor
# Event: PostToolUse | Matcher: (none)
# Injects /compact reminders during agentic runs when context climbs.
# Fires once per threshold band (70/80/90%) — resets when context drops below 70%.
#
# Complements context-advisor.sh (UserPromptSubmit) by catching context growth
# during long agentic runs where the user isn't typing.
#
# Opt-out: add "auto-compact" to ~/.claude/supercharger/scope/.disabled-hooks
# or set {"disableHooks": ["auto-compact"]} in .supercharger.json

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-ctx-pct.sh
. "$HOOKS_DIR/lib-ctx-pct.sh"
check_hook_disabled "auto-compact" && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# 2.21.12: session-scope the compaction debounce band. The context window is
# per-session, but .compact-last-band was global — one session at 85% wrote
# band 80 and suppressed another session's 70/80 warning, and dropping below 70
# removed the shared file, resetting the other's debounce.
#
# v4.1.8: extracted by parameter expansion rather than `jq -r .session_id`. This
# hook is PostToolUse with no matcher, so it runs on EVERY tool call and the id
# is now needed on every one of them to key the sidecar — a jq fork there is
# ~2ms per tool call, the whole spawn floor.
# Same parse as context-advisor.sh: match the colon (a spaced payload must not
# fall through to the whole document), take the FIRST occurrence, and refuse
# anything that is not a plausible id rather than letting it become a filename.
SID="default"
case "$_INPUT" in *'"session_id"'*)
  _ac_after="${_INPUT#*\"session_id\":}"
  if [ "$_ac_after" != "$_INPUT" ]; then
    _ac_after="${_ac_after#"${_ac_after%%[![:space:]]*}"}"
    case "$_ac_after" in
      \"*) _ac_after="${_ac_after#\"}"; SID="${_ac_after%%\"*}" ;;
    esac
  fi
  case "$SID" in ''|*[!A-Za-z0-9._-]*) SID="default" ;; esac
  ;;
esac

# ── Read context percentage ───────────────────────────────────────────────────
# v2.27.26 perf: the fork-free `case` keeps the python fork off the common path.
# This hook is PostToolUse with no matcher, so it fires on every tool call, and
# an unconditional python3 measured +35ms on every PostToolUse:Bash call.
# v4.1.8: it is now a BRANCH, not a bail-out. It used to `exit 0` when the key
# was absent — which is every real payload, since no hook event carries
# `context_window` (see hooks/lib-ctx-pct.sh), so the hook short-circuited 100%
# of its calls. The payload read is kept because it is the path the field would
# arrive on if upstream ever adds it, and because it costs nothing when absent.
PCT=""
case "$_INPUT" in *'"used_percentage"'*)
  PCT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    pct = d.get('context_window', {}).get('used_percentage', '')
    print(int(float(pct)) if pct != '' else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  ;;
esac

# The statusline sidecar is what actually supplies the number in practice.
# _ctx_pct is bash builtins plus, on bash 3.2 only, one `date` — and that fork is
# reached only once the sidecar file has been found, so an install without a
# Supercharger statusline still pays nothing per tool call.
# The freshness check is deliberately LEFT ON here despite the per-call cost: a
# resumed session would otherwise read yesterday's percentage on its first tool
# call, before the statusline has re-rendered, and warn on a stale number.
[ -z "$PCT" ] && _ctx_pct PCT "$SID"

[ -z "$PCT" ] && exit 0
[ "$PCT" -lt 70 ] && {
  rm -f "$SUPERCHARGER_STATE/scope/.compact-last-band-${SID}"
  exit 0
}

# ── Determine threshold band ──────────────────────────────────────────────────
if   [ "$PCT" -ge 90 ]; then BAND=90
elif [ "$PCT" -ge 80 ]; then BAND=80
else                          BAND=70
fi

# ── Debounce: skip if already warned at this band ────────────────────────────
STATE_FILE="$SUPERCHARGER_STATE/scope/.compact-last-band-${SID}"
LAST_BAND=$(cat "$STATE_FILE" 2>/dev/null || echo "0")

[ "$BAND" -le "$LAST_BAND" ] && exit 0

# ── Write new band state ──────────────────────────────────────────────────────
mkdir -p "$SUPERCHARGER_STATE/scope"
printf '%s\n' "$BAND" > "$STATE_FILE"

# ── Compose message ───────────────────────────────────────────────────────────
case "$BAND" in
  90) MSG="[CTX CRITICAL ${PCT}%] Near context limit. Stop current task, run /compact, verify work is saved." ;;
  80) MSG="[CTX HIGH ${PCT}%] Run /compact before continuing. Switch to eco minimal to reduce growth." ;;
  70) MSG="[CTX ${PCT}%] Context approaching limit. Consider /compact soon." ;;
esac

# MSG is built from hardcoded literals + integer PCT — no quotes, backslashes,
# or control chars to escape. Bash printf is safe here. Avoids a python3 fork
# (~50-70ms cold-start per call). Verified by case statement above.
printf '{"systemMessage":"%s"}\n' "$MSG"
