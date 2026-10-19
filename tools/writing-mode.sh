#!/usr/bin/env bash
# Claude Supercharger — opt-in writing modes (rules files Claude loads every session)
# Usage: bash tools/writing-mode.sh <mode> on|off|status
#        bash tools/writing-mode.sh list
#
# A mode is configs/rules/<mode>.md, deployed to ~/.claude/supercharger/rules/modes/.
# "on" copies it to ~/.claude/rules/sc-mode-<mode>.md, which Claude Code loads at the
# start of every session; "off" removes that copy. The sc-mode- prefix keeps mode
# files apart from the rules Supercharger always manages.
set -euo pipefail

SC="${SUPERCHARGER_HOME:-$HOME/.claude/supercharger}"
SRC_DIR="$SC/rules/modes"
DST_DIR="$HOME/.claude/rules"

case "${1:-}" in
  list|"")
    echo "Writing modes (on = loaded every session):"
    for f in "$SRC_DIR"/*.md; do
      [ -f "$f" ] || { echo "  none installed (re-run the installer)"; exit 0; }
      m=$(basename "$f" .md)
      if [ -f "$DST_DIR/sc-mode-$m.md" ]; then s=on; else s=off; fi
      printf '  %-14s %s\n' "$m" "$s"
    done
    exit 0 ;;
esac

MODE="$1"; ACTION="${2:-status}"
case "$MODE" in *[!a-z0-9-]*) echo "unknown mode: $MODE" >&2; exit 2 ;; esac
SRC="$SRC_DIR/$MODE.md"
DST="$DST_DIR/sc-mode-$MODE.md"
[ -f "$SRC" ] || { echo "unknown mode: $MODE (see: writing-mode.sh list)" >&2; exit 2; }

case "$ACTION" in
  on)
    mkdir -p "$DST_DIR"
    # Stage and rename: a session reading the rules dir never sees a half-written file.
    cp "$SRC" "$DST.tmp.$$" && mv -f "$DST.tmp.$$" "$DST"
    echo "Writing mode '$MODE': ON. Loaded at the start of every session until you turn it off." ;;
  off)
    rm -f "$DST"
    echo "Writing mode '$MODE': OFF from the next session." ;;
  status)
    if [ -f "$DST" ]; then echo "Writing mode '$MODE': on"; else echo "Writing mode '$MODE': off"; fi ;;
  *) echo "usage: writing-mode.sh <mode> on|off|status | list" >&2; exit 2 ;;
esac
