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

# Print one gate per line: the VALUE cell (field 3 of the `| Item | Your value | Example |`
# row, never the Example) of the four gate rows. Reads <= 64 KB; when the file is longer
# the final (possibly cut) line is dropped so a cut row never parses as a shorter gate.
# A row whose `<`/`(` cut leaves an odd number of " or ' is skipped: under-count, never
# over-count (`bash -c "(cd web && npm test)"` must not become `bash -c`). A balanced
# cut is kept: `npm test -- --grep (unit)` => `npm test -- --grep`.
# shortcut: an escaped `\|` inside a cell just cuts the cell; upgrade if gates need pipes.
sc_rb_gates() {
  local big=0 sz
  sz=$(wc -c < "$1/READBACK.md" 2>/dev/null) || sz=0
  sz="${sz//[[:space:]]/}" # BSD wc pads
  case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
  [ "$sz" -gt 65536 ] && big=1
  head -c 65536 "$1/READBACK.md" 2>/dev/null | tr -d '\0' | awk -v big="$big" '
    function row(line,   a, l, v, q) {
      gsub(/\r/, "", line)
      if (line !~ /^[ \t]*\|/) return
      split(line, a, "|")
      l = a[2]; gsub(/^[ \t]+|[ \t]+$/, "", l)
      if (l != "Targeted test" && l != "Full suite" && l != "New warnings" && l != "Secret scan") return
      v = a[3]
      if (match(v, /`[^`]*`/)) v = substr(v, RSTART + 1, RLENGTH - 2)
      if (match(v, /[<(]/)) {
        v = substr(v, 1, RSTART - 1)
        q = v; if (gsub(/"/, "", q) % 2) return
        q = v; if (gsub(/\047/, "", q) % 2) return
      }
      gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", v)
      if (v != "") print v
    }
    { if (have) row(prev); prev = $0; have = 1 }
    END { if (have && !big) row(prev) }' 2>/dev/null || true
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
