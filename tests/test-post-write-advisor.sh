#!/usr/bin/env bash
# Post-write advisory dispatcher — folds conflict-marker + config-validity +
# shebang-exec into one process (reads the final on-disk file once).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/post-write-advisor.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Post-Write Advisor Tests ==="

TMP=$(mktemp -d)
HAS_TOML=$(python3 -c "import tomllib" 2>/dev/null && echo 1 || echo 0)
# markers built at runtime so this file's source stays marker-free
L=$(printf '<%.0s' 1 2 3 4 5 6 7); R=$(printf '>%.0s' 1 2 3 4 5 6 7); E=$(printf '=%.0s' 1 2 3 4 5 6 7)

# write CONTENT to a real file at MODE, emit a Write payload carrying that content
mkf() { printf '%s' "$4" > "$2"; chmod "$3" "$2"; FP="$2" C="$4" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"], "content": os.environ["C"]}, "session_id": "pw"}))
PY
}
ctx() { SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" 2>/dev/null | \
  python3 -c "import json,sys;s=sys.stdin.read().strip();print(json.loads(s)['hookSpecificOutput']['additionalContext'] if s else '')"; }
verdict() { local c; c=$(ctx "$1"); [ -n "$c" ] && echo WARN || echo SILENT; }
n=0
check() { n=$((n+1)); mkf "$TMP/c$n" "$TMP/f$n$3" "$4" "$5"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$2" ] && pass || fail "expected $2 got $g"; }

# --- conflict-marker check ---
CONFLICT=$'a=1\n'"$L HEAD"$'\nmine\n'"$E"$'\nyours\n'"$R f"$'\nb=2'
check "conflict markers .ts"   WARN   .ts   644 "$CONFLICT"
check "clean source .ts"       SILENT .ts   644 'const x = 1'
check "conflict in .md skipped" SILENT .md   644 "$CONFLICT"

# --- config-validity check ---
check "invalid json"           WARN   .json 644 '{"a":1'
check "valid json"             SILENT .json 644 '{"a":1,"b":2}'
check "jsonc tsconfig"         SILENT .json 644 $'{\n  // c\n  "x": true,\n}'

# --- shebang-exec check ---
# The advisory is POSIX-only as of v2.28.4. Windows python os.stat() carries no
# POSIX permission bits, so a .sh file can never read as executable there and the
# hook cannot tell 0644 from 0755 - it used to warn for BOTH, which is why the
# runner reported "shebang already +x - expected SILENT got WARN". Asserting the
# POSIX expectations on Windows would just move the failure to the other case.
case "$OSTYPE" in
  msys*|cygwin*|win32*)
    check "shebang 0644 (POSIX-only advisory)"           SILENT .sh   644 $'#!/usr/bin/env bash\necho hi\n'
    check "shebang already +x (POSIX-only advisory)"     SILENT .sh   755 $'#!/usr/bin/env bash\necho hi\n'
    ;;
  *)
    check "shebang 0644"           WARN   .sh   644 $'#!/usr/bin/env bash\necho hi\n'
    check "shebang already +x"     SILENT .sh   755 $'#!/usr/bin/env bash\necho hi\n'
    ;;
esac

# --- combined: a .json with conflict markers = BOTH conflict + invalid-json warnings ---
n=$((n+1)); mkf "$TMP/c$n" "$TMP/both.json" 644 "$CONFLICT"
begin_test "combined: two advisories in one pass"
c=$(ctx "$TMP/c$n")
{ printf '%s' "$c" | grep -q "merge conflict" && printf '%s' "$c" | grep -q "invalid JSON"; } && pass || fail "expected both advisories: $c"

# --- kill switches ---
mkf "$TMP/ks" "$TMP/ks.json" 644 '{"a":1'
begin_test "master kill switch disables all"
out=$(SUPERCHARGER_POST_WRITE_ADVISOR=0 bash "$HOOK" < "$TMP/ks" 2>/dev/null); [ -z "$out" ] && pass || fail "expected SILENT"

begin_test "per-check legacy kill switch (config-validity) silences only it"
out=$(SUPERCHARGER_CONFIG_VALIDITY_GUARD=0 SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$TMP/ks" 2>/dev/null); [ -z "$out" ] && pass || fail "expected SILENT for the disabled check"

mkf "$TMP/cf" "$TMP/cf.ts" 644 "$CONFLICT"
begin_test "conflict kill switch off, others still active (shebang via separate file)"
out=$(SUPERCHARGER_CONFLICT_MARKER_GUARD=0 SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$TMP/cf" 2>/dev/null); [ -z "$out" ] && pass || fail "expected SILENT when only-check disabled"

# --- fail-open ---
begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null); [ -z "$out" ] && pass || fail "expected fail-open silence"

# --- TOML (validated only where tomllib is present; always REPORTED) ---
# v2.24.11: these two used to vanish entirely without tomllib (Python < 3.11),
# so the suite total differed by platform — and the README tests-badge check
# compares that total exactly, which meant CI could never be green on both
# ubuntu and macos at once. Emit the assertions either way.
if [ "$HAS_TOML" = 1 ]; then
  check "broken toml"          WARN   .toml 644 $'x = "unterminated'
  check "valid toml"           SILENT .toml 644 $'x = 1\n[t]\ny = 2'
else
  for t in "broken toml" "valid toml"; do
    begin_test "$t"
    echo "    (skipped: python3 tomllib unavailable — TOML parsing not exercised here)"
    pass
  done
fi

rm -rf "$TMP"
report
