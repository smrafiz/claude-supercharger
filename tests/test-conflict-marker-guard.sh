#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/conflict-marker-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Conflict Marker Guard Tests ==="

# Build the 7-char markers at runtime so this test file's own source stays
# marker-free (deployed guard never self-warns on it).
L=$(printf '<%.0s' 1 2 3 4 5 6 7)   # 7 open-angles
R=$(printf '>%.0s' 1 2 3 4 5 6 7)   # 7 close-angles
E=$(printf '=%.0s' 1 2 3 4 5 6 7)   # 7 equals
S6=$(printf '<%.0s' 1 2 3 4 5 6)    # only 6 open-angles (not a marker)

FULL=$'a=1\n'"$L HEAD"$'\nmine\n'"$E"$'\ntheirs\n'"$R feature"$'\nb=2'
STARTONLY=$'x\n'"$L HEAD"$'\ny'
ENDONLY=$'x\n'"$R feature"$'\ny'
MIDONLY=$'title\n'"$E"$'\nbody'
HEREDOC=$'cat <<EOF\nhi\nEOF'
SHIFT=$'v = x >> 2\nw = y << 3'
SIX=$'x\n'"$S6 HEAD"$'\ny'

TMP=$(mktemp -d)
mkin() { FP="$2" C="$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"], "content": os.environ["C"]}, "session_id": "cm"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" | \
    python3 -c "import json,sys;s=sys.stdin.read().strip();print('WARN' if s and json.loads(s).get('hookSpecificOutput',{}).get('additionalContext') else 'SILENT')"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n" "$2" "$3"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$4" ] && pass || fail "expected $4 got $g"; }

# --- WARN: real conflict markers in code ---
check "full conflict .ts"     "$TMP/app.ts"    "$FULL"       WARN
check "start marker only .py"  "$TMP/m.py"      "$STARTONLY"  WARN
check "end marker leftover .js" "$TMP/m.js"     "$ENDONLY"    WARN

# --- SILENT: not a conflict marker ---
check "heredoc <<EOF"          "$TMP/a.sh"      "$HEREDOC"    SILENT
check "bit-shift >> <<"        "$TMP/a.ts"      "$SHIFT"      SILENT
check "bare ======= separator" "$TMP/a.ts"      "$MIDONLY"    SILENT
check "only 6 angles"          "$TMP/a.ts"      "$SIX"        SILENT
check "clean source"           "$TMP/a.ts"      $'const x=1'  SILENT

# --- SILENT: docs / patches skipped (illustrative markers / email quotes) ---
check "markdown doc skipped"   "$TMP/README.md" "$FULL"       SILENT
check "txt email quote"        "$TMP/mail.txt"  "$ENDONLY"    SILENT
check "patch file skipped"     "$TMP/x.patch"   "$FULL"       SILENT

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_CONFLICT_MARKER_GUARD=0 bash "$HOOK" < "$TMP/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
