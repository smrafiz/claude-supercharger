#!/usr/bin/env bash
# Claude Supercharger — Handoff file selection (shared)
# Sourced by session-memory-inject.sh, post-compact-inject.sh, compaction-backup.sh.
#
# Handoff briefs are SESSION-SCOPED: `.claude/handoff-<session_id>.md`. Under
# multiple concurrent sessions in one project, a single unsuffixed file meant
# last-writer-wins + one session's compaction injecting another session's brief
# (the scope-file-session-scoping leak class). Session-scoping mirrors the
# `.checkpoint-<sid>` convention and keeps each session's resume brief its own.
#
# Selection precedence (single source of truth so the readers can't drift):
#   1. the caller's OWN-SID file, if present and within the freshness gate
#   2. otherwise the NEWEST `.claude/handoff-*.md` within the gate
#   3. otherwise the legacy unsuffixed `.claude/handoff.md` (pre-2.23.12), within the gate
#
# select_handoff_file <project_dir> <session_id> [max_age_secs]
#   max_age_secs = 0 (or omitted) → no age gate (compaction is same-session).
# Echoes the chosen path, or nothing if none qualifies. Never fails the caller.

_hf_mtime() {
  local m
  m=$(stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || echo 0)
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

# The time a brief was WRITTEN: the date in its heading ("## Handoff — p — YYYY-MM-DD"),
# taken as the end of that day, else the file mtime. After a clone or checkout git
# rewrites every mtime, so "newest file" meant whichever file git wrote last, and a
# two-month-old brief passed the 7-day gate because its mtime was a minute old.
_hf_time() {
  local line="" l d t n=0
  # First date in the first 5 lines: briefs put it in the heading; the project
  # carry file (.claude/handoff.md) puts it in a "Verified YYYY-MM-DD" line.
  while [ $n -lt 5 ] && IFS= read -r l; do
    n=$((n + 1))
    if [[ "$l" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then line="$l"; break; fi
  done < "$1" 2>/dev/null
  if [[ "$line" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    d="${BASH_REMATCH[1]}"
    t=$(date -j -f '%Y-%m-%d %H:%M:%S' "$d 23:59:59" +%s 2>/dev/null \
        || date -d "$d 23:59:59" +%s 2>/dev/null || echo "")
    case "$t" in ''|*[!0-9]*) ;; *) printf '%s' "$t"; return ;; esac
  fi
  _hf_mtime "$1"
}

_hf_fresh() { # path now max_age  → 0 if within gate (or gate disabled)
  local mt
  [ "$3" -le 0 ] && return 0
  mt=$(_hf_time "$1")
  [ "$mt" -gt 0 ] && [ $(( $2 - mt )) -lt "$3" ]
}

select_handoff_file() {
  local dir="$1" sid="$2" max_age="${3:-0}"
  local d="$dir/.claude" now cand mt best="" best_mt=0
  now=$(date +%s)

  # 1. own-SID file wins outright when present + fresh
  if [ -n "$sid" ] && [ -f "$d/handoff-$sid.md" ] && _hf_fresh "$d/handoff-$sid.md" "$now" "$max_age"; then
    printf '%s\n' "$d/handoff-$sid.md"; return 0
  fi

  # 2. newest session-scoped file, then 3. legacy unsuffixed — all gated
  for cand in "$d"/handoff-*.md "$d/handoff.md"; do
    [ -f "$cand" ] || continue                      # unmatched glob / missing legacy
    _hf_fresh "$cand" "$now" "$max_age" || continue
    mt=$(_hf_time "$cand")
    # Same heading date → the later-written file wins (mtime as the tie-break).
    if [ "$mt" -gt "$best_mt" ] || { [ "$mt" -eq "$best_mt" ] && [ -n "$best" ] \
         && [ "$(_hf_mtime "$cand")" -gt "$(_hf_mtime "$best")" ]; }; then
      best_mt=$mt; best=$cand
    fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}
