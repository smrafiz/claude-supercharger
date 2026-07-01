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
# v2.7.23: removed 10 dead/misnamed entries that matched no real writer
# (.pending-*, .eco-stop-*, .tier-snapshot-*, .eco-reinforce-counter,
#  .last-idle-notify, .prompt-cost-*/.prompt-tokens-*/.last-prompt-tokens-*,
#  bare .gate-pending, .loop-detector/.loop-detector-*) and added coverage for
# real scope files that previously leaked forever (no pruner matched them).
# Note: .snapshot-* mtime is set once at SessionStart, so a session running
# longer than its TTL would lose its scope-alert baseline — acceptable (rare;
# check mode degrades gracefully).
patterns_max_age=(
  ".dedup-*:$SECS_HOUR"
  ".agent-classified-*:$SECS_WEEK"
  ".denied-*:$SECS_WEEK"
  ".keep-going-*:$SECS_WEEK"
  ".stack-cache-*:$SECS_MONTH"
  ".router-hash-*:$SECS_DAY"
  ".router-cache-*:$SECS_DAY"
  ".router-roster-*:$SECS_WEEK"
  ".last-tier-*:$SECS_WEEK"
  ".last-category-*:$SECS_WEEK"
  ".subagent-active-*:$SECS_DAY"
  ".subagent-costs-*.jsonl:$SECS_WEEK"
  ".subagent-spawns-*.json:$SECS_WEEK"
  ".main-tokens-*:$SECS_WEEK"
  ".subagent-safety-injected-*:$SECS_WEEK"
  ".tool-history-*:$SECS_WEEK"
  ".tool-calls-*:$SECS_DAY"
  ".snapshot-*:$SECS_WEEK"
  ".contract-*:$SECS_DAY"
  ".user-corrections-*:$SECS_MONTH"
  ".user-reinforcements-*:$SECS_MONTH"
  ".agent-dispatched-*:$SECS_WEEK"
  ".gate-pending-*:$SECS_HOUR"
  ".rate-limit-*:$SECS_DAY"
  ".quality-gate-cache-*:$SECS_WEEK"
  ".typecheck-cache-*:$SECS_WEEK"
  ".notify-ts-*:$SECS_DAY"
  ".cache-health-counter:$SECS_DAY"
  ".eco-reinforce-acked:$SECS_WEEK"
  ".eco-last-*:$SECS_WEEK"
  ".memory-restored:$SECS_DAY"
  ".active-mcp-*:$SECS_DAY"
  ".failed-commands-*:$SECS_WEEK"
  ".scan-alert-*:$SECS_DAY"
  ".standards-inject-*:$SECS_MONTH"
  ".repetition-flag-*:$SECS_DAY"
  ".loop-history:$SECS_WEEK"
  ".read-history:$SECS_WEEK"
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
    case "$mtime" in ''|*[!0-9]*) mtime=$now ;; esac  # v2.6.78: numeric guard
    age=$((now - mtime))
    size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
    case "$size" in ''|*[!0-9]*) size=0 ;; esac  # v2.6.78: numeric guard
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
