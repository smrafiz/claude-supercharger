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
  ".quality-gate-cache-*:$SECS_WEEK"
  ".typecheck-cache-*:$SECS_WEEK"
  ".notify-ts-*:$SECS_DAY"
  ".cache-health-counter:$SECS_DAY"
  ".eco-reinforce-counter:$SECS_DAY"
  ".memory-restored:$SECS_DAY"
  ".last-idle-notify:$SECS_DAY"
  ".prompt-cost-*:$SECS_WEEK"
  ".prompt-tokens-*:$SECS_WEEK"
  ".last-prompt-tokens-*:$SECS_WEEK"
  ".active-mcp-*:$SECS_DAY"
  ".gate-pending:$SECS_HOUR"
  ".loop-detector:$SECS_DAY"
  ".loop-detector-*:$SECS_DAY"
)

cleanup_pattern() {
  local pattern="$1" max_age="$2"
  shopt -s nullglob 2>/dev/null || true
  for f in "$SCOPE_DIR"/$pattern; do
    [ ! -f "$f" ] && continue
    local mtime age size
    # GNU stat (Linux): -c %Y for mtime, -c %s for size.
    # BSD/macOS stat:   -f %m for mtime, -f %z for size.
    # GNU's -f returns filesystem info (not file), so try GNU first.
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "$now")
    age=$((now - mtime))
    size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
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

# Orphan check: list files NOT covered by any pattern (suggests new patterns to add)
if [ "${ORPHANS:-0}" = "1" ]; then
  echo ""
  echo "Orphan files (not covered by any TTL pattern):"
  shopt -s nullglob 2>/dev/null || true
  for f in "$SCOPE_DIR"/.*; do
    base=$(basename "$f")
    [ "$base" = "." ] && continue
    [ "$base" = ".." ] && continue
    [ ! -f "$f" ] && continue
    matched=0
    for entry in "${patterns_max_age[@]}"; do
      pattern="${entry%%:*}"
      # shellcheck disable=SC2254
      case "$base" in $pattern) matched=1; break ;; esac
    done
    [ "$matched" = "0" ] && echo "  $base"
  done
fi

echo ""
if [ "$APPLY" = 1 ]; then
  echo "Removed: $removed files, freed $bytes_freed bytes."
else
  echo "Would remove: $removed files, freeing $bytes_freed bytes. Kept: $kept."
  echo "Run with --apply to execute. Run with ORPHANS=1 to list unmatched files."
fi
