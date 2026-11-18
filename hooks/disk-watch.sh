#!/usr/bin/env bash
# Claude Supercharger — Disk Watch
# Event: PostToolUse, PostToolUseFailure | Matcher: Bash
# Tells Claude when free disk space drops sharply or sits under a floor.
# 2026-11-17, from tsrmehmet/memokit (MIT) check-disk.sh. A build, a docker pull or a
# runaway log can eat the disk inside one Bash call, and nothing told Claude, who then
# kept going until writes failed. After each Bash call: compare free space on the
# project's filesystem with the previous call's, and tell Claude (additionalContext)
# when it dropped by SUPERCHARGER_DISK_DROP_GB (default 10) or sits under
# SUPERCHARGER_DISK_MIN_GB (default 5; at most once per 10 minutes). 0 disables either.
# ponytail: the baseline is the previous Bash call, not a PreToolUse snapshot of this
# one — one fork per call instead of two; a drop from a non-Bash tool lands on the
# next Bash call. A Pre hook if attribution ever matters.
# Disable: SUPERCHARGER_DISK_WATCH=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-stdin.sh
. "$HOOKS_DIR/lib-stdin.sh"; sc_read_input _INPUT
[ "${SUPERCHARGER_DISK_WATCH:-1}" = 0 ] && exit 0
case "$_INPUT" in *'"tool_name"'*'"Bash"'*) ;; *) exit 0 ;; esac
check_hook_disabled "disk-watch" && exit 0

# Fork-free field reads: these are plain ids and paths.
EVENT=PostToolUse; case "$_INPUT" in *PostToolUseFailure*) EVENT=PostToolUseFailure ;; esac
SID=nosession; [[ "$_INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" ]] && SID="${BASH_REMATCH[1]}"
DIR="$PWD"; [[ "$_INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"\\]+)\" ]] && DIR="${BASH_REMATCH[1]}"
[ -d "$DIR" ] || DIR="$PWD"

FREE="${SUPERCHARGER_DF_KB:-}"
if [ -z "$FREE" ]; then
  FREE=$(df -Pk "$DIR" 2>/dev/null) || exit 0
  FREE=${FREE##*$'\n'}; read -r _ _ _ FREE _ <<<"$FREE"
fi
case "$FREE" in ''|*[!0-9]*) exit 0 ;; esac

ST="$SUPERCHARGER_STATE/scope"; mkdir -p "$ST" 2>/dev/null || exit 0
LAST_F="$ST/.disk-free-$SID"; FLOOR_F="$ST/.disk-floor-$SID"
LAST=""; [ -f "$LAST_F" ] && read -r LAST < "$LAST_F"
printf '%s\n' "$FREE" > "$LAST_F"

GB=1048576 MSG=""
DROP_GB="${SUPERCHARGER_DISK_DROP_GB:-10}"; MIN_GB="${SUPERCHARGER_DISK_MIN_GB:-5}"
case "$DROP_GB$MIN_GB" in *[!0-9]*) exit 0 ;; esac
if [ "$DROP_GB" -gt 0 ] && [ -n "$LAST" ] && [ $(( LAST - FREE )) -ge $(( DROP_GB * GB )) ]; then
  MSG="Free disk space dropped by $(( (LAST - FREE) / GB )) GB since the previous command ($(( FREE / GB )) GB free now). If that was not expected, find what grew (du -sh on build output, caches, logs, docker) before running more."
fi
if [ "$MIN_GB" -gt 0 ] && [ "$FREE" -lt $(( MIN_GB * GB )) ]; then
  NOW=$(date +%s); PREV=0; [ -f "$FLOOR_F" ] && read -r PREV < "$FLOOR_F"
  case "$PREV" in ''|*[!0-9]*) PREV=0 ;; esac
  if [ $(( NOW - PREV )) -ge 600 ]; then
    printf '%s\n' "$NOW" > "$FLOOR_F"
    MSG="${MSG:+$MSG }Only $(( FREE / GB )) GB free on this disk (under ${MIN_GB} GB). Writes may start failing: free space before anything large, and tell the user."
  fi
fi
[ -z "$MSG" ] && exit 0
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"[DISK] %s"}}\n' "$EVENT" "$MSG"
