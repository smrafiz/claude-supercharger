#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-doctor.sh"

echo "=== Hook Doctor Tests ==="

# ── helpers ───────────────────────────────────────────────────────────────────
make_settings() {
  local home="$1" script="$2"
  mkdir -p "$home/.claude"
  python3 -c "
import json
s = {
  'hooks': {
    'PreToolUse': [{
      'hooks': [{'command': '$script #supercharger'}]
    }]
  }
}
print(json.dumps(s))
" > "$home/.claude/settings.json"
}

make_sc_dirs() {
  local home="$1"
  local sc="$home/.claude/supercharger"
  mkdir -p "$sc/hooks" "$sc/tools" "$sc/lib"
  touch "$sc/hooks/safety.sh" "$sc/tools/supercharger.sh" "$sc/lib/utils.sh"
}

run_doctor() {
  EXIT=0
  OUTPUT=$(HOME="$1" bash "$TOOL" "${2:-}" 2>&1) || EXIT=$?
}

# ── tests ─────────────────────────────────────────────────────────────────────
begin_test "hook-doctor: exits 1 when settings.json missing"
TMP=$(mktemp -d)
run_doctor "$TMP"
[ "$EXIT" -eq 1 ] && pass || fail "expected exit 1, got $EXIT"
rm -rf "$TMP"

begin_test "hook-doctor: exits 1 when no supercharger hooks registered"
TMP=$(mktemp -d)
mkdir -p "$TMP/.claude"
echo '{"hooks":{}}' > "$TMP/.claude/settings.json"
run_doctor "$TMP"
[ "$EXIT" -eq 1 ] && pass || fail "expected exit 1 for no hooks, got $EXIT"
rm -rf "$TMP"

begin_test "hook-doctor: reports missing script"
TMP=$(mktemp -d)
make_settings "$TMP" "/nonexistent/path/safety.sh"
make_sc_dirs "$TMP"
run_doctor "$TMP"
echo "$OUTPUT" | grep -qi "MISSING" && [ "$EXIT" -eq 1 ] && pass || fail "expected MISSING report; exit=$EXIT"
rm -rf "$TMP"

begin_test "hook-doctor: reports non-executable script"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '#!/usr/bin/env bash\n' > "$SCRIPT"
chmod 644 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
run_doctor "$TMP"
echo "$OUTPUT" | grep -qi "NOT EXECUTABLE\|executable" && [ "$EXIT" -eq 1 ] && pass || fail "expected NOT EXECUTABLE report; exit=$EXIT"
rm -rf "$TMP"

begin_test "hook-doctor: reports bad shebang"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '# no shebang\necho hi\n' > "$SCRIPT"
chmod 755 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
run_doctor "$TMP"
echo "$OUTPUT" | grep -qi "shebang\|SHEBANG" && [ "$EXIT" -eq 1 ] && pass || fail "expected BAD SHEBANG report; exit=$EXIT"
rm -rf "$TMP"

begin_test "hook-doctor: passes for valid script"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRIPT"
chmod 755 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
run_doctor "$TMP"
[ "$EXIT" -eq 0 ] && pass || fail "expected exit 0 for valid hook; exit=$EXIT output: $OUTPUT"
rm -rf "$TMP"

begin_test "hook-doctor: --quiet exits 1 on issues, no output"
TMP=$(mktemp -d)
make_settings "$TMP" "/nonexistent/hook.sh"
make_sc_dirs "$TMP"
run_doctor "$TMP" "--quiet"
[ "$EXIT" -eq 1 ] && [ -z "$OUTPUT" ] && pass || fail "expected exit 1 + no output; exit=$EXIT output='$OUTPUT'"
rm -rf "$TMP"

begin_test "hook-doctor: --quiet exits 0 on healthy install, no output"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRIPT"
chmod 755 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
run_doctor "$TMP" "--quiet"
[ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ] && pass || fail "expected exit 0 + no output; exit=$EXIT output='$OUTPUT'"
rm -rf "$TMP"

begin_test "hook-doctor: reports stale pending file"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRIPT"
chmod 755 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
SCOPE="$TMP/.claude/supercharger/scope"
mkdir -p "$SCOPE"
printf 'sql\n0\n' > "$SCOPE/.gate-pending-abc123"
run_doctor "$TMP"
echo "$OUTPUT" | grep -qi "stale" && pass || fail "expected stale pending file warning; output: $OUTPUT"
rm -rf "$TMP"

begin_test "hook-doctor: no stale warning for fresh pending file"
TMP=$(mktemp -d)
SCRIPT="$TMP/test-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRIPT"
chmod 755 "$SCRIPT"
make_settings "$TMP" "$SCRIPT"
make_sc_dirs "$TMP"
SCOPE="$TMP/.claude/supercharger/scope"
mkdir -p "$SCOPE"
printf 'sql\n%s\n' "$(date -u +%s)" > "$SCOPE/.gate-pending-fresh1"
run_doctor "$TMP"
echo "$OUTPUT" | grep -qi "No stale" && pass || fail "expected 'No stale' message; output: $OUTPUT"
rm -rf "$TMP"

report
