#!/usr/bin/env bash
# Claude Supercharger — Task Complete Notification
# Event: Stop | Matcher: *
# Notifies when a turn finishes — but only for turns longer than a threshold
# (default 30s, override with scope/.notify-min-seconds) so quick back-and-forth
# doesn't ping. Layout uses the title/subtitle/body tiers:
#   title    <project> · Done · 2m 14s     (project added by notify-helper)
#   subtitle <branch> · $<cost> this session
#   body     the reply, markdown stripped

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /sc-perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

source "${BASH_SOURCE[0]%/*}/notify-helper.sh"

[ -f "$SUPERCHARGER_DIR/.no-desktop-notify" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Skip if stop hook already active (prevent double notification)
STOP_ACTIVE=$(printf '%s\n' "$_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || true)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Suppress during subagents
_is_subagent "$_INPUT" && exit 0

# Cooldown (12s — task complete notifications)
_NS_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
_cooldown_ok "stop" 12 "$_NS_SID" || exit 0

# v2.7.34: duration gate — only notify for turns past the threshold so quick
# replies stay silent. Override seconds via scope/.notify-min-seconds.
# 4.2.1: the Stop payload carries no `cost` (that is a statusline field), so this
# read 0 for every turn and the gate silenced ALL turn-end notifications. The turn
# length is now taken from the transcript: now minus the last typed prompt.
_T=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
DURATION_MS=0
if [ -n "$_T" ] && [ -f "$_T" ]; then
  DURATION_MS=$(tail -n 400 "$_T" 2>/dev/null | jq -rs '
    [.[] | select(.type == "user" and .timestamp)
      | select((.message.content | type) == "string"
               or ([.message.content[]? | select(.type == "text")] | length > 0))]
    | last | .timestamp // empty | sub("\\.[0-9]+"; "") | fromdateiso8601
    | (now - .) * 1000 | floor' 2>/dev/null || echo 0)
fi
case "$DURATION_MS" in ''|*[!0-9]*) DURATION_MS=0 ;; esac
MIN_SECS=30
if [ -f "$SUPERCHARGER_DIR/scope/.notify-min-seconds" ]; then
  MIN_SECS=$(tr -cd '0-9' < "$SUPERCHARGER_DIR/scope/.notify-min-seconds" 2>/dev/null || echo 30)
  MIN_SECS=${MIN_SECS:-30}
fi
[ $((DURATION_MS / 1000)) -lt "$MIN_SECS" ] && exit 0

# Extract transcript path
TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

RESPONSE=""

# Small delay — Stop fires before transcript is fully flushed
sleep 0.3

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # v2.7.57: tail-read + single pass. Two full-file jq -rs SLURPS cost ~1.1s per
  # turn-end on a long transcript (measured: 47MB / 29k lines). The last user +
  # last assistant are always in the tail; one jq extracts both (separated by
  # __SC_SEP__, never in transcript text). ~1.1s → ~10ms, identical output.
  PAIR=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -rs '
    ([.[] | select(.type == "user")
      | if .message.content | type == "string" then .
        elif [.message.content[] | select(.type == "text")] | length > 0 then .
        else empty end] | last) as $u |
    ([.[] | select(.type == "assistant" and .message.content)] | last) as $a |
    (if $u.message.content | type == "array"
     then [$u.message.content[] | select(.type == "text") | .text] | join(" ")
     else $u.message.content // "" end)
    + "__SC_SEP__" +
    ([$a.message.content[] | select(.type == "text") | .text] | join(" "))
  ' 2>/dev/null || echo "__SC_SEP__")
  # 4.3.1: the reply only. The quoted prompt used half the banner and was often
  # harness text ("Another Claude session sent a message: <agent-message…").
  RESPONSE="${PAIR#*__SC_SEP__}"
  RESPONSE=$(printf '%s' "$RESPONSE" | tr '\n\t' '  ' | sed -E 's/\*\*|__|`|^#+ //g; s/  +/ /g; s/^ //')
  [ ${#RESPONSE} -gt 180 ] && RESPONSE="${RESPONSE:0:177}..."
fi

# Elapsed time for the title
MINS=$((DURATION_MS / 60000))
SECS=$(( (DURATION_MS % 60000) / 1000 ))
if [ "$MINS" -gt 0 ]; then
  ELAPSED=" · ${MINS}m ${SECS}s"
elif [ "$SECS" -gt 0 ]; then
  ELAPSED=" · ${SECS}s"
else
  ELAPSED=""
fi

# Body: what happened this turn
if [ -n "$RESPONSE" ]; then
  MSG="$RESPONSE"
else
  MSG="Task completed"
fi

# Subtitle: this session's spend (notify-helper puts the branch in front). The
# per-session file, as budget-cap uses — .session-cost is the machine's lifetime
# total and was shown here as "session" ($11.7M on one machine).
SUBTITLE=""
if [ -n "$_NS_SID" ] && [ -f "$SUPERCHARGER_DIR/scope/.main-tokens-$_NS_SID" ]; then
  COST_DISPLAY=$(jq -r '.cost_usd // empty | . * 100 | round / 100 | tostring' \
    "$SUPERCHARGER_DIR/scope/.main-tokens-$_NS_SID" 2>/dev/null || true)
  case "$COST_DISPLAY" in ''|*[!0-9.]*) ;; *) SUBTITLE=$(printf '$%.2f this session' "$COST_DISPLAY") ;; esac
fi

_send_notification "Claude — Done${ELAPSED}" "$MSG" "$SUBTITLE"

exit 0
