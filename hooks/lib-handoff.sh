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

_hf_fresh() { # path now max_age  → 0 if within gate (or gate disabled)
  local mt
  [ "$3" -le 0 ] && return 0
  mt=$(_hf_mtime "$1")
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
    mt=$(_hf_mtime "$cand")
    if [ "$mt" -gt "$best_mt" ]; then best_mt=$mt; best=$cand; fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}
