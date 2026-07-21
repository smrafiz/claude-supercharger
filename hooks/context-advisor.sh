#!/usr/bin/env bash
# Claude Supercharger — Context Advisor
# Event: UserPromptSubmit | Matcher: (none)
# Injects context warnings and economy suggestions based on context window usage.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "context-advisor" && exit 0

PCT=$(printf '%s\n' "$_INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null || true)
if [ -z "$PCT" ]; then
  PCT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pct = data.get('context_window', {}).get('used_percentage', '')
print(int(pct) if pct != '' else '')
" 2>/dev/null || echo "")
fi

[ -z "$PCT" ] && exit 0

PCT=${PCT%%.*}

echo "[Supercharger] context-advisor: ${PCT}% used" >&2

# Bucket-keyed dedup (2.18.2): warn ONCE per escalation band (70 / 80 / 90) instead
# of every turn once >70%. Re-warn only when crossing into a HIGHER band; reset when
# context drops below 70 (e.g. after /compact) so a later climb re-warns. Fork-free
# on the common <70 path — session_id via bash param-expansion, and the reset rm only
# fires right after a compaction (when the peak file exists).
SCOPE_DIR="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope"
SESSION_ID="default"
case "$_INPUT" in *'"session_id"'*) SESSION_ID="${_INPUT##*\"session_id\":\"}"; SESSION_ID="${SESSION_ID%%\"*}" ;; esac
PEAK_FILE="$SCOPE_DIR/.ctx-advisor-peak-${SESSION_ID}"

if [ "$PCT" -lt 70 ]; then
  [ -f "$PEAK_FILE" ] && rm -f "$PEAK_FILE" 2>/dev/null || true
  exit 0
elif [ "$PCT" -lt 80 ]; then
  BUCKET=70
  MSG="[CTX] ${PCT}% used. /compact if continuing."
elif [ "$PCT" -lt 90 ]; then
  BUCKET=80
  MSG="[CTX WARN] ${PCT}% — run /compact now. eco minimal. Verify: tests pass, build clean, no uncommitted work."
else
  BUCKET=90
  MSG="[CTX CRITICAL] ${PCT}% — near limit. Stop and verify work before compacting."
fi

# Skip if we've already warned at this band or higher this session (until a <70 reset).
LAST_PEAK=0
[ -f "$PEAK_FILE" ] && IFS= read -r LAST_PEAK < "$PEAK_FILE" 2>/dev/null || true
case "$LAST_PEAK" in ''|*[!0-9]*) LAST_PEAK=0 ;; esac
[ "$BUCKET" -le "$LAST_PEAK" ] && exit 0
mkdir -p "$SCOPE_DIR" 2>/dev/null || true
printf '%s\n' "$BUCKET" > "$PEAK_FILE" 2>/dev/null || true

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
