#!/usr/bin/env bash
# Claude Supercharger — Memory Auto-Pruner (v2.19.0)
#
# Archives author-declared-resolved memory entries so they stop loading into
# context every session, and SUGGESTS (never auto-moves) weaker candidates.
#
# Safety model (see docs): this operates on Claude's file-memory dir, so it is
# deliberately conservative —
#   * AUTO-archives ONLY entries whose frontmatter says  status: resolved|superseded
#     AND whose  type: project . feedback / reference / bug-class are NEVER auto-moved.
#   * "Archive" = MOVE to memory/archive/ (out of the loaded MEMORY.md index) and
#     stash the index line for exact restore. Nothing is ever deleted.
#   * Everything else is only listed as a candidate for you to confirm.
#
# Usage:
#   memory-prune.sh              # dry-run: show what WOULD be archived + suggestions
#   memory-prune.sh --apply      # archive the author-declared-resolved project entries
#   memory-prune.sh --restore <name>   # move an entry back from archive + re-add its index line
#   memory-prune.sh --list-archive     # show archived entries
#
# Env: SUPERCHARGER_MEMDIR overrides the memory dir (used by tests).

set -euo pipefail

MODE="dry"
RESTORE_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)        MODE="apply" ;;
    --dry-run)      MODE="dry" ;;
    --list-archive) MODE="list" ;;
    --restore)      MODE="restore"; shift; RESTORE_NAME="${1:-}" ;;
    --restore=*)    MODE="restore"; RESTORE_NAME="${1#--restore=}" ;;
    *)              echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift || true
done

# Resolve the file-memory dir for the current project (cwd → CC's project encoding).
if [ -n "${SUPERCHARGER_MEMDIR:-}" ]; then
  MEMDIR="$SUPERCHARGER_MEMDIR"
else
  ENC="-$(pwd | sed 's|/|-|g; s|^-||')"
  MEMDIR="$HOME/.claude/projects/$ENC/memory"
fi
INDEX="$MEMDIR/MEMORY.md"
ARCHIVE="$MEMDIR/archive"

if [ ! -d "$MEMDIR" ]; then
  echo "No file-memory dir for this project:"
  echo "  $MEMDIR"
  exit 0
fi

# Read one frontmatter field's value (first match, between the first two --- lines).
# Anchored so `type` never matches `node_type`.
fm_field() {
  awk -v f="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^[[:space:]]*" f ":[[:space:]]") {
      sub("^[[:space:]]*" f ":[[:space:]]*", ""); gsub(/[[:space:]]+$/, ""); print; exit
    }
  ' "$1" 2>/dev/null || true
}

# --- restore mode ---
if [ "$MODE" = "restore" ]; then
  [ -n "$RESTORE_NAME" ] || { echo "usage: --restore <name>" >&2; exit 2; }
  RESTORE_NAME="${RESTORE_NAME%.md}"
  af="$ARCHIVE/$RESTORE_NAME.md"
  [ -f "$af" ] || { echo "not in archive: $RESTORE_NAME" >&2; exit 1; }
  mv "$af" "$MEMDIR/$RESTORE_NAME.md"
  if [ -f "$ARCHIVE/$RESTORE_NAME.indexline" ]; then
    cat "$ARCHIVE/$RESTORE_NAME.indexline" >> "$INDEX"
    rm -f "$ARCHIVE/$RESTORE_NAME.indexline"
  fi
  echo "Restored: $RESTORE_NAME (moved back + index line re-added)"
  exit 0
fi

# --- list-archive mode ---
if [ "$MODE" = "list" ]; then
  if [ -d "$ARCHIVE" ] && ls "$ARCHIVE"/*.md >/dev/null 2>&1; then
    echo "Archived entries ($ARCHIVE):"
    for f in "$ARCHIVE"/*.md; do echo "  - $(basename "$f" .md)"; done
  else
    echo "No archived entries."
  fi
  exit 0
fi

# --- scan ---
AUTO=()          # status:resolved|superseded + type:project  → auto-archivable
FLAG_NONPROJ=()  # status:resolved but NOT project             → flag, never auto
SUGGEST=()       # weak signals (terminal marker / age)        → candidate only

NOW=$(date +%s)
for f in "$MEMDIR"/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f"); name="${b%.md}"
  [ "$b" = "MEMORY.md" ] && continue

  typ=$(fm_field "$f" type)
  st=$(fm_field "$f" status)

  case "$st" in
    resolved|superseded)
      if [ "$typ" = "project" ]; then AUTO+=("$name")
      else FLAG_NONPROJ+=("$name [type=${typ:-none}]"); fi
      ;;
    *)
      # Suggest-lane: ONLY project-type, and only weak machine signals.
      [ "$typ" = "project" ] || continue
      reason=""
      if grep -qiE '(all items? (now )?(resolved|debunked)|^#* *CLOSED|\bCLOSED:|debunked|superseded by|no longer needed)' "$f"; then
        reason="terminal marker in body"
      else
        mt=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo "$NOW")
        case "$mt" in ''|*[!0-9]*) mt=$NOW ;; esac
        age_days=$(( (NOW - mt) / 86400 ))
        [ "$age_days" -gt 90 ] && reason="untouched ${age_days}d (project entry)"
      fi
      [ -n "$reason" ] && SUGGEST+=("$name — $reason")
      ;;
  esac
done

archive_one() {
  local name="$1" f="$MEMDIR/$1.md"
  mkdir -p "$ARCHIVE"
  # stash the exact index line for restore (may be empty if not indexed)
  grep -F "($name.md)" "$INDEX" > "$ARCHIVE/$name.indexline" 2>/dev/null || true
  [ -s "$ARCHIVE/$name.indexline" ] || rm -f "$ARCHIVE/$name.indexline"
  # drop it from the loaded index
  if [ -f "$INDEX" ]; then
    grep -vF "($name.md)" "$INDEX" > "$INDEX.tmp" 2>/dev/null && mv "$INDEX.tmp" "$INDEX" || rm -f "$INDEX.tmp"
  fi
  mv "$f" "$ARCHIVE/$name.md"
}

echo "=== Memory prune — $MEMDIR ==="
echo "Entries: $(ls "$MEMDIR"/*.md 2>/dev/null | grep -vc 'MEMORY.md' || echo 0) | mode: $MODE"
echo ""

if [ "${#AUTO[@]}" -eq 0 ]; then
  echo "Auto-archivable (status: resolved/superseded + type: project): none"
else
  echo "Auto-archivable (${#AUTO[@]}):"
  for n in "${AUTO[@]}"; do echo "  ✓ $n"; done
  if [ "$MODE" = "apply" ]; then
    for n in "${AUTO[@]}"; do archive_one "$n"; done
    echo "  → archived ${#AUTO[@]} to $ARCHIVE/ (index lines removed; restore with --restore <name>)"
  else
    echo "  (dry-run — re-run with --apply to archive)"
  fi
fi
echo ""

if [ "${#SUGGEST[@]}" -gt 0 ]; then
  echo "Suggestions (NOT auto — confirm, then mark 'status: resolved' or --restore-proof):"
  for s in "${SUGGEST[@]}"; do echo "  ? $s"; done
  echo ""
fi
if [ "${#FLAG_NONPROJ[@]}" -gt 0 ]; then
  echo "Marked resolved but NOT type:project (left in place by design):"
  for s in "${FLAG_NONPROJ[@]}"; do echo "  · $s"; done
fi

exit 0
