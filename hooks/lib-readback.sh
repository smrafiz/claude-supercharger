#!/usr/bin/env bash
# Claude Supercharger — readback mode helpers (sourced by failure-tracker.sh).
# READBACK.md is UNTRUSTED repo content: its gate strings are only ever compared
# literally (quoted case patterns) — never executed, eval'd, or built into a regex.

# Set SC_RB_DIR to the project dir iff READBACK.md is a regular file at its root
# (no walk-up; -f rejects FIFOs/dirs). No fork.
sc_rb_dir() {
  SC_RB_DIR=""
  local d="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [ -f "$d/READBACK.md" ]; then SC_RB_DIR="$d"; fi
  return 0
}

# Print one gate per line: the VALUE cell (field 3 of the `| Item | Value | Example |`
# row, never the Example) of the four gate rows. Reads <= 64 KB.
# shortcut: an escaped `\|` inside a cell just cuts the cell; upgrade if gates need pipes.
sc_rb_gates() {
  head -c 65536 "$1/READBACK.md" 2>/dev/null | tr -d '\0' | awk -F'|' '
    { gsub(/\r/, "") }
    $0 !~ /^[ \t]*\|/ { next }
    { l = $2; gsub(/^[ \t]+|[ \t]+$/, "", l) }
    l != "Targeted test" && l != "Full suite" && l != "New warnings" && l != "Secret scan" { next }
    {
      v = $3
      if (match(v, /`[^`]*`/)) v = substr(v, RSTART + 1, RLENGTH - 2)
      if (match(v, /[<(]/)) v = substr(v, 1, RSTART - 1)
      gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", v)
      if (v != "") print v
    }' 2>/dev/null || true
}

# sc_rb_is_gate DIR CMD — 0 if CMD is a gate, starts with one, or runs one after `&& `/`; `.
sc_rb_is_gate() {
  local g
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    case "$2" in
      "$g"|"$g "*|*"&& $g"|*"&& $g "*|*"; $g"|*"; $g "*) return 0 ;;
    esac
  done < <(sc_rb_gates "$1")
  return 1
}
