#!/usr/bin/env bash
# Python output encoding on Windows consoles (v2.26.71)
#
# Python on Windows defaults stdout to the ANSI codepage — cp1252 on most installs.
# Any character outside it raises UnicodeEncodeError, and the hook's ENTIRE output
# is lost. Reported from a real Windows desktop when autopilot was enabled:
#
#   [statusline error: 'charmap' codec can't encode character '⚡' ...]
#
# U+26A1 is the autopilot bolt. The same crash also took the context bar, which
# draws in U+2591 — one report, two symptoms, one cause.
#
# Reproducible on macOS/Linux by forcing PYTHONIOENCODING=cp1252, which is what
# makes this testable at all without a Windows box.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Python Output Encoding ==="

begin_test "lib-paths EXPORTS a UTF-8 encoding when none is set"
# Asserts OUR variable, not python's resulting encoding. On macOS and Linux python
# already defaults to UTF-8, so checking sys.stdout.encoding passes with or without
# the fix — the first version of this test did exactly that and proved nothing.
# The Windows platform default cannot be simulated here at all: python 3.7+ coerces
# the C locale to UTF-8 (PEP 538), so LC_ALL=C does not reproduce it either.
SET=$(env -u PYTHONIOENCODING -u PYTHONUTF8 bash -c "
  . '$REPO_DIR/hooks/lib-paths.sh' 2>/dev/null
  printf '%s' \"\${PYTHONIOENCODING:-UNSET}\"
" 2>/dev/null)
[ "$(printf '%s' "$SET" | tr 'A-Z' 'a-z')" = "utf-8" ] && pass \
  || fail "lib-paths left PYTHONIOENCODING as '$SET' — a Windows console would use cp1252"

begin_test "an explicit user setting is honoured, not overridden"
# Silently clamping a value the user set is its own bug class in this repo.
GOT=$(env PYTHONIOENCODING=latin-1 bash -c "
  . '$REPO_DIR/hooks/lib-paths.sh' 2>/dev/null
  python3 -c 'import os; print(os.environ[\"PYTHONIOENCODING\"])'
" 2>/dev/null)
[ "$GOT" = "latin-1" ] && pass || fail "override lost: got '$GOT'"

# A statusline with nothing to report is pure ASCII and cannot reproduce this at
# all — the first version of these tests passed against the PRE-FIX code for that
# reason. The bolt only renders while an autopilot window is open, so the fixture
# has to stage one. Read from ~/.claude/supercharger/scope, which follows HOME.
stage_bolt() { # -> echoes a state dir whose statusline contains U+26A1
  local sl; sl=$(mktemp -d)
  mkdir -p "$sl/scope" "$sl/home/.claude/supercharger/scope"
  printf '%s' "$(( $(date +%s) + 3600 ))" > "$sl/home/.claude/supercharger/scope/.autopilot-until"
  printf '%s' "$sl"
}
render() { # state-dir, encoding -> statusline output (empty encoding = inherit)
  local sl="$1" enc="${2:-}"
  # An earlier version wrote `${enc:+PYTHONIOENCODING="$enc"} ${enc:-}`, where the
  # second expansion repeated the VALUE as a bare argument — env then tried to run
  # `cp1252` as a command, produced nothing, and every grep-for-absence assertion
  # passed for the wrong reason.
  if [ -n "$enc" ]; then
    printf '{"session_id":"enc","cwd":"%s","model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"}}' \
      "$REPO_DIR" "$REPO_DIR" \
    | env PYTHONIOENCODING="$enc" HOME="$sl/home" SUPERCHARGER_STATE="$sl" \
      bash "$REPO_DIR/hooks/statusline.sh" 2>&1
  else
    printf '{"session_id":"enc","cwd":"%s","model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"}}' \
      "$REPO_DIR" "$REPO_DIR" \
    | env -u PYTHONIOENCODING -u PYTHONUTF8 HOME="$sl/home" SUPERCHARGER_STATE="$sl" \
      bash "$REPO_DIR/hooks/statusline.sh" 2>&1
  fi
}

begin_test "the fixture actually renders the autopilot bolt"
# Guards the guard: if this stops emitting U+26A1, every assertion below becomes
# vacuous without failing, which is precisely what happened on the first attempt.
SL=$(stage_bolt)
render "$SL" "" | grep -q 'Autopilot' && pass || fail "fixture does not produce the bolt — the tests below prove nothing"
rm -rf "$SL"

begin_test "the autopilot bolt survives a default environment"
SL=$(stage_bolt)
OUT=$(render "$SL" "")
if printf '%s' "$OUT" | grep -q 'statusline error'; then
  fail "statusline errored in a default environment: $(printf '%s' "$OUT" | head -1)"
else
  pass
fi
rm -rf "$SL"

begin_test "a hostile encoding degrades to a blank line, never to an error string"
# The structural half of the fix. print(line1) used to sit OUTSIDE the inner try,
# so one unencodable character replaced ALL THREE lines with an error string.
# Lines 2 and 3 already degraded independently; line 1 now does too. The worst case
# is a missing line, not a dead statusline.
SL=$(stage_bolt)
OUT=$(render "$SL" cp1252)
if printf '%s' "$OUT" | grep -q 'statusline error'; then
  fail "cp1252 still produces an error string rather than degrading"
else
  pass
fi
rm -rf "$SL"

begin_test "the statusline still emits three lines when it degrades"
# Claude Code renders a fixed number of statusline rows; collapsing to one would
# shift the display even when the content is merely missing.
SL=$(stage_bolt)
N=$(render "$SL" cp1252 2>/dev/null | wc -l | tr -d ' ')
[ "${N:-0}" -ge 3 ] && pass || fail "expected >=3 lines, got ${N:-0}"
rm -rf "$SL"

# --- the same crash, in tools/ ------------------------------------------------
# v2.26.71 fixed this for HOOKS via hooks/lib-paths.sh, the one file every hook
# reaches. Nothing covered tools/, and the v2.26.87 Windows diagnostic caught the
# consequence directly:
#
#   UnicodeEncodeError: 'charmap' codec can't encode characters in position 0-59
#
# tools/hook-perf.sh died there and took the entire chain report with it — nine
# test-perf-chain failures from one uncaught codec. Every one of these tools
# prints box-drawing characters or arrows, so the exposure is uniform.
#
# Asserted as a SCAN over the directory rather than a list of known files: the
# hook-side fix worked precisely because one file covered everything, and the
# tools cannot have that (only 9 of 23 even have a REPO_DIR to source from), so
# the scan is what stops this being partially applied.
begin_test "every python-forking script outside hooks/ sets a UTF-8 stdout"
# tools/ AND lib/ AND install.sh/uninstall.sh. The first version of this scan
# covered tools/ only, and six more files had the identical exposure — including
# install.sh, the first thing a Windows user runs, and lib/hooks.sh, which writes
# settings.json. A scan that stops at one directory is still a list.
#
# hooks/ is excluded deliberately: every hook reaches hooks/lib-paths.sh, which
# sets this once for all of them (v2.26.71). Nothing else reaches that file.
MISSING=""
for f in "$REPO_DIR"/tools/*.sh "$REPO_DIR"/lib/*.sh "$REPO_DIR"/install.sh "$REPO_DIR"/uninstall.sh; do
  [ -f "$f" ] || continue
  grep -q 'python3' "$f" || continue
  grep -q 'PYTHONIOENCODING' "$f" || MISSING="$MISSING $(basename "$f")"
done
[ -z "$MISSING" ] && pass || fail "forks python without a UTF-8 stdout:$MISSING"

begin_test "the tools honour an explicit encoding rather than forcing utf-8"
# `:=` not `=`. A user who deliberately sets an encoding must keep it, and the
# regression test for the Windows default cannot run here anyway — python on
# macOS/Linux already defaults to UTF-8 (PEP 538/540), so forcing cp1252 would
# only prove that an override works.
BAD=""
for f in "$REPO_DIR"/tools/*.sh "$REPO_DIR"/lib/*.sh "$REPO_DIR"/install.sh "$REPO_DIR"/uninstall.sh; do
  [ -f "$f" ] || continue
  grep -q 'PYTHONIOENCODING' "$f" || continue
  grep -q ': "${PYTHONIOENCODING:=' "$f" || BAD="$BAD $(basename "$f")"
done
[ -z "$BAD" ] && pass || fail "tools overwrite an explicit PYTHONIOENCODING:$BAD"

# --- CRLF: the OTHER half of Windows python output ---------------------------
# print() on Windows terminates lines with CRLF. bash splits on \n alone, so any
# hook that reads a MULTI-LINE python result into shell variables keeps a trailing
# CR on every field but the last.
#
# tool-history-tracker parses exactly that shape — line 1 is the session id, line
# 2 is the entry — and used line 1 to build `.tool-history-<sid>`. With the CR
# attached the filename holds a character Windows does not permit, the append
# fails, and the hook records NOTHING: no history, no per-session isolation, and
# a confidence-gate that never sees a failure. Five recon failures, one byte.
#
# Simulated with a python3 stub that emits CRLF, because that is the one part of
# Windows behaviour reproducible here — the same technique test-windows-rm-net
# uses to make the resolver inert.
begin_test "tool-history-tracker survives CRLF-terminated python output"
CRLF_DIR=$(mktemp -d); ST=$(mktemp -d); mkdir -p "$ST/scope"
REAL_PY=$(command -v python3)
# Resolve the real interpreter FIRST: a stub named python3 that re-invokes
# `python3` by name finds itself on PATH and forks until the box gives up.
cat > "$CRLF_DIR/python3" <<EOF
#!/bin/sh
"$REAL_PY" "\$@" | while IFS= read -r l; do printf '%s\r\n' "\$l"; done
EOF
chmod +x "$CRLF_DIR/python3"

printf '{"session_id":"crlfsess","tool_name":"Bash","tool_response":{"stdout":"ok"}}' \
  | env PATH="$CRLF_DIR:$PATH" SUPERCHARGER_STATE="$ST" \
    bash "$REPO_DIR/hooks/tool-history-tracker.sh" >/dev/null 2>&1

# The file must exist under the CLEAN name, and no CR-suffixed sibling may appear.
CLEAN=$ST/scope/.tool-history-crlfsess
DIRTY=$(find "$ST/scope" -name '*.tool-history*' 2>/dev/null | tr -d '\r' | grep -c . || true)
if [ -s "$CLEAN" ]; then
  pass
else
  fail "history not written under the clean name (found: $(ls -A "$ST/scope" 2>/dev/null | cat -v | tr '\n' ' ')) files=$DIRTY"
fi
rm -rf "$CRLF_DIR" "$ST"

begin_test "the CRLF stub really does emit carriage returns (guard the guard)"
# Without this, a stub that quietly failed would make the check above pass for
# the wrong reason -- the exact trap the resolver-stub test was written to avoid.
CRLF_DIR=$(mktemp -d); REAL_PY=$(command -v python3)
cat > "$CRLF_DIR/python3" <<EOF
#!/bin/sh
"$REAL_PY" "\$@" | while IFS= read -r l; do printf '%s\r\n' "\$l"; done
EOF
chmod +x "$CRLF_DIR/python3"
GOT=$(env PATH="$CRLF_DIR:$PATH" python3 -c "print('x')" | od -c | head -1)
rm -rf "$CRLF_DIR"
printf '%s' "$GOT" | grep -q '\\r' && pass || fail "stub emitted no CR — the test above proves nothing: $GOT"

report
