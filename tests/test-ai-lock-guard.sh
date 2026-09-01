#!/usr/bin/env bash
# Suite for hooks/ai-lock-guard.sh (v4.0.13)
#
# Every other write guard in this product decides from the PATH. This one decides
# from the line range inside the file, and its whole value is the REASON the
# manifest carries — a guard that says "locked" gets waved through, one that says
# why does not.
#
# Two halves, and the second matters more. It must ask when an edit lands inside
# a locked range; it must stay SILENT everywhere else, because this hook runs on
# every Write and Edit and a guard that nags on unrelated files gets disabled.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/ai-lock-guard.sh"

# A project with one lock over lines 10-20 of src/a.py. The manifest deliberately
# carries a comment, a non-"locked" record and a malformed line: vibetags writes a
# `format` header, and one bad line must not void the rest of the file.
_mkproj() {  # $1 = manifest basename (.ai-locks | .vibetags-locks)
  local p; p=$(mktemp -d)
  mkdir -p "$p/src"
  local i=1
  : > "$p/src/a.py"
  while [ "$i" -le 40 ]; do printf 'line%02d\n' "$i" >> "$p/src/a.py"; i=$((i + 1)); done
  {
    printf '# generated, do not edit\n'
    printf '{"type":"format","version":1}\n'
    printf '%s\n' '{"type":"locked","file":"src/a.py","startLine":10,"endLine":20,"element":"parse()","reason":"Step order is load-bearing"}'
    printf '{ not json at all\n'
  } > "$p/$1"
  printf '%s' "$p"
}

# Returns "ask" or "allow". Runs with cwd AND PWD set to the project: bash
# recomputes PWD and can resolve it to a different spelling of the same directory
# (/private/var vs /var on macOS), which is the bug the detector's realpath fixes.
_verdict() {  # $1 = project dir, $2 = payload JSON
  local out
  out=$(printf '%s' "$2" | (cd "$1" && PWD="$1" HOME="$1" bash "$HOOK" 2>/dev/null))
  case "$out" in
    *'"ask"'*) printf 'ask' ;;
    '')        printf 'allow' ;;
    *)         printf 'other:%s' "${out:0:40}" ;;
  esac
}
_edit() {  # $1 = project, $2 = file, $3 = old_string, $4 = session
  printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"%s","new_string":"X"}}' \
    "$4" "$2" "$3"
}

echo "=== ai-lock-guard ==="

begin_test "ai-lock: an edit INSIDE a locked range asks"
P=$(_mkproj .ai-locks)
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line12 s1)")" = ask ] && pass \
  || fail "edit at line 12 of a 10-20 lock did not ask"
rm -rf "$P"

begin_test "ai-lock: the recorded REASON reaches the user"
# The entire point of the feature. A lock without its rationale is a speed bump.
P=$(_mkproj .ai-locks)
OUT=$(printf '%s' "$(_edit "$P" "$P/src/a.py" line12 s2)" | (cd "$P" && PWD="$P" HOME="$P" bash "$HOOK" 2>/dev/null))
case "$OUT" in
  *"Step order is load-bearing"*) pass ;;
  *) fail "reason absent from the prompt: ${OUT:0:120}" ;;
esac
rm -rf "$P"

begin_test "ai-lock: an edit OUTSIDE the locked range is silent"
P=$(_mkproj .ai-locks)
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line35 s3)")" = allow ] && pass \
  || fail "asked about line 35, which no lock covers"
rm -rf "$P"

begin_test "ai-lock: an unrelated file in the same project is silent"
P=$(_mkproj .ai-locks); printf 'x\n' > "$P/src/b.py"
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/b.py" x s4)")" = allow ] && pass \
  || fail "asked about a file carrying no lock"
rm -rf "$P"

begin_test "ai-lock: a Write asks, because it replaces the whole file"
# No old_string to locate, and the call rewrites every line — so every lock in
# that file is in scope regardless of where it sits.
P=$(_mkproj .ai-locks)
PL=$(printf '{"session_id":"s5","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$P/src/a.py")
[ "$(_verdict "$P" "$PL")" = ask ] && pass || fail "whole-file Write over a locked file did not ask"
rm -rf "$P"

begin_test "ai-lock: vibetags' own manifest name works unchanged"
# The schema is taken verbatim so a project already generating one is covered.
P=$(_mkproj .vibetags-locks)
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line12 s6)")" = ask ] && pass \
  || fail ".vibetags-locks was not honoured"
rm -rf "$P"

begin_test "ai-lock: asks once per file per session, then stays quiet"
# An edit loop inside a locked range is a human who already consented. Asking
# every time is how a guard gets switched off.
P=$(_mkproj .ai-locks)
A=$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line12 s7)")
B=$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line13 s7)")
[ "$A" = ask ] && [ "$B" = allow ] && pass || fail "expected ask then allow, got $A then $B"
rm -rf "$P"

begin_test "ai-lock: no manifest anywhere means total silence"
# The fast path. Projects that never opt in must pay nothing and see nothing.
P=$(mktemp -d); mkdir -p "$P/src"; printf 'x\n' > "$P/src/a.py"
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" x s8)")" = allow ] && pass \
  || fail "fired with no manifest present"
rm -rf "$P"

begin_test "ai-lock: an unreadable manifest fails OPEN"
# Documentation that cannot be parsed must never block work — that is how the
# manifest ends up deleted.
P=$(_mkproj .ai-locks); printf 'not json at all\nnor this\n' > "$P/.ai-locks"
[ "$(_verdict "$P" "$(_edit "$P" "$P/src/a.py" line12 s9)")" = allow ] && pass \
  || fail "a garbage manifest produced a prompt"
rm -rf "$P"

begin_test "ai-lock: the kill switch is honoured"
P=$(_mkproj .ai-locks)
OUT=$(printf '%s' "$(_edit "$P" "$P/src/a.py" line12 s10)" \
  | (cd "$P" && PWD="$P" HOME="$P" SUPERCHARGER_AI_LOCK_GUARD=0 bash "$HOOK" 2>/dev/null))
[ -z "$OUT" ] && pass || fail "SUPERCHARGER_AI_LOCK_GUARD=0 did not silence it"
rm -rf "$P"

begin_test "ai-lock: the detector normalises Git Bash paths"
# v4.0.13 shipped without this and the Windows job caught it: 5 pass / 6 fail,
# and the split was exact — every case expecting an ASK failed, every case
# expecting silence passed, i.e. the guard was inert on that platform while
# failing open and saying nothing. Native Windows python resolves a leading-slash
# path against the CURRENT DRIVE, so the manifest (POSIX, from the wrapper's $PWD
# walk) and the target spelled the same file differently and no lock matched.
# test-msys-path-normalisation asserts the same property for the other scanners.
grep -q 'def _msys_path' "$REPO_DIR/hooks/ai-lock-detect.py" && pass \
  || fail "ai-lock-detect.py does not normalise MSYS paths — it will be inert on Windows"

begin_test "ai-lock: path comparison is resolved in ONE place"
# Resolving inside the manifest loader fixed one side and left the other; the
# comparison owns it now, so a third spelling cannot be half-handled.
grep -q '_same_file' "$REPO_DIR/hooks/ai-lock-detect.py" && pass \
  || fail "path comparison is not centralised"

begin_test "ai-lock: the prompt is parseable permissionDecision JSON"
# A malformed payload is dropped by Claude Code, so the user is told nothing —
# the failure this hook exists to prevent.
P=$(_mkproj .ai-locks)
printf '%s' "$(_edit "$P" "$P/src/a.py" line12 s11)" \
  | (cd "$P" && PWD="$P" HOME="$P" bash "$HOOK" 2>/dev/null) \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
sys.exit(0 if d["permissionDecision"]=="ask" and d["permissionDecisionReason"] else 1)' \
  && pass || fail "output is not a valid ask decision"
rm -rf "$P"

report
