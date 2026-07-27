#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/ansi-escape-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== ANSI Escape Guard Tests ==="

TMP=$(mktemp -d)
# Build payloads with a RAW ESC (chr(27)) inside python so this test's own source
# stays control-char-free. KEY selects the case.
mkpay() { KEY="$2" python3 - "$1" <<'PY'
import json, os, sys
E = chr(27)
specs = {
    "conceal":  ("/p/x.ts",                "note " + E + "[8mHIDDEN" + E + "[0m tail"),
    "osc8":     ("/p/x.py",                "see " + E + "]8;;http://evil" + E + "\\ ok"),
    "color":    ("/p/x.ts",                "red " + E + "[31mvisible" + E + "[0m"),
    "textual":  ("/p/x.ts",                r"CONCEAL = '\x1b[8m'  # a constant"),
    "castfix":  ("/p/rec.cast",            "x " + E + "[8mh" + E + "[0m"),
    "snappath": ("/p/__snapshots__/a.ts",  "x " + E + "[8mh" + E + "[0m"),
    "mddoc":    ("/p/NOTES.md",            "x " + E + "[8mh" + E + "[0m"),
    "clean":    ("/p/x.ts",                "const x = 1"),
}
fp, c = specs[os.environ["KEY"]]
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": fp, "content": c}, "session_id": "ae"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" | \
    python3 -c "import json,sys;s=sys.stdin.read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'SILENT')"
}
n=0
check() { n=$((n+1)); mkpay "$TMP/c$n" "$2"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g"; }

# --- ASK: raw-ESC content-hiding escapes ---
check "raw conceal ESC[8m"     conceal  ASK
check "raw OSC-8 hyperlink"    osc8     ASK

# --- SILENT: not a hiding escape / not raw / skipped location ---
check "plain color SGR"        color    SILENT
check "textual \\x1b constant" textual  SILENT
check ".cast fixture skipped"  castfix  SILENT
check "__snapshots__ path"     snappath SILENT
check "markdown doc skipped"   mddoc    SILENT
check "clean source"           clean    SILENT

# --- dedup / kill switch / fail-open ---
mkpay "$TMP/dd" conceal
SS=$(mktemp -d)
begin_test "asks first, silent on repeat file (dedup)"
SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd" >/dev/null 2>&1
second=$(SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd" 2>/dev/null)
[ -z "$second" ] && pass || fail "expected SILENT on repeat"
rm -rf "$SS"

begin_test "kill switch disables"
out=$(SUPERCHARGER_ANSI_ESCAPE_GUARD=0 bash "$HOOK" < "$TMP/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
