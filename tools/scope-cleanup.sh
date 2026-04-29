#!/usr/bin/env bash
# Claude Supercharger — Scope State Cleanup
# Removes accumulated state files in ~/.claude/supercharger/scope/
# Categories:
#   .dedup-*           : per-session dedup hashes (TTL 1h)
#   .agent-classified-*: per-session agent classifier cache (TTL 7d)
#   .denied-*          : per-session denied tools log (TTL 7d)
#   .keep-going-*      : per-session stop-keep-going poke counter (TTL 7d)
#   .stack-cache-*     : per-project stack detection cache (TTL 30d)
#   .pending-*         : human-approval-gate pending files (TTL 1h)
#
# Usage:
#   bash tools/scope-cleanup.sh         # report only (dry run)
#   bash tools/scope-cleanup.sh --apply # actually delete

set -uo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

if [ ! -d "$SCOPE_DIR" ]; then
  echo "scope dir not found: $SCOPE_DIR"
  exit 0
fi

now=$(date +%s)
SECS_HOUR=3600
SECS_DAY=86400
SECS_WEEK=$((SECS_DAY * 7))
SECS_MONTH=$((SECS_DAY * 30))

declare -i removed=0 kept=0
declare -i bytes_freed=0

# pattern => max age (sec)
patterns_max_age=(
  ".dedup-*:$SECS_HOUR"
  ".agent-classified-*:$SECS_WEEK"
  ".denied-*:$SECS_WEEK"
  ".keep-going-*:$SECS_WEEK"
  ".stack-cache-*:$SECS_MONTH"
  ".pending-*:$SECS_HOUR"
  ".router-hash-*:$SECS_DAY"
  ".last-tier-*:$SECS_WEEK"
  ".last-category-*:$SECS_WEEK"
  ".subagent-active-*:$SECS_DAY"
  ".subagent-costs-*.jsonl:$SECS_WEEK"
  ".user-corrections-*:$SECS_MONTH"
  ".user-reinforcements-*:$SECS_MONTH"
  ".agent-dispatched-*:$SECS_WEEK"
  ".gate-pending-*:$SECS_HOUR"
  ".eco-stop-*:$SECS_DAY"
  ".tier-snapshot-*:$SECS_WEEK"
  ".rate-limit-*:$SECS_DAY"
)

cleanup_pattern() {
  local pattern="$1" max_age="$2"
  shopt -s nullglob 2>/dev/null || true
  for f in "$SCOPE_DIR"/$pattern; do
    [ ! -f "$f" ] && continue
    local mtime age size
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "$now")
    age=$((now - mtime))
    size=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$age" -gt "$max_age" ]; then
      if [ "$APPLY" = 1 ]; then
        rm -f "$f" 2>/dev/null && removed+=1 && bytes_freed+=$size
      else
        removed+=1
        bytes_freed+=$size
        printf '  would remove: %s (%dh old, %dB)\n' "$(basename "$f")" "$((age / SECS_HOUR))" "$size"
      fi
    else
      kept+=1
    fi
  done
}

if [ "$APPLY" = 0 ]; then
  echo "Dry run (use --apply to delete):"
fi

for entry in "${patterns_max_age[@]}"; do
  pattern="${entry%%:*}"
  max_age="${entry##*:}"
  cleanup_pattern "$pattern" "$max_age"
done

echo ""
if [ "$APPLY" = 1 ]; then
  echo "Removed: $removed files, freed $bytes_freed bytes."
else
  echo "Would remove: $removed files, freeing $bytes_freed bytes. Kept: $kept."
  echo "Run with --apply to execute."
fi
