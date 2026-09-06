#!/usr/bin/env bash
# The harness and `[ -f ]` must agree on what a path means (v4.0.29)
#
# Where they disagree, the TOOL acts on the real file and the GUARD stats
# something that cannot exist, takes its "nothing there, nothing to do" exit,
# and says nothing. Asked of the harness directly rather than reasoned about:
#
#   ~/path          EXPANDED by the harness, not by [ -f ]   -> bypass
#   "  /abs/path"   leading whitespace tolerated              -> bypass
#   $HOME/path      NOT expanded, the tool fails too          -> no bypass
#   ["/abs/path"]   coerced, the tool fails too               -> no bypass
#
# Only the first two are fixed. A fix for the other two would ask on calls that
# can never succeed, which is how a guard earns being switched off.
#
# The content scanners are not the worst case. path-guard resolves a
# non-absolute path against cwd, so `~/elsewhere/x` became
# `<project>/~/elsewhere/x` — INSIDE the boundary — and a write outside the
# project read as one within it. [[one-path-many-spellings]]
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-toolpath.sh"

echo "=== Tool-Path Normalisation Tests ==="

begin_test "the shared normaliser exists"
[ -f "$LIB" ] && pass || fail "hooks/lib-toolpath.sh missing"

begin_test "it expands ~ and trims, and leaves ~user alone"
# Behavioural, not a grep over the source: the first version of this assertion
# matched the word "~user" in the lib's own comment EXPLAINING that it is not
# expanded, so it failed on correct code. A guard's documentation is not its
# behaviour. Guessing another user's home would silently retarget a security
# check at their file, so ~user must pass through untouched.
_TP_BAD=""
_tp_case() {  # input, expected, label — one pass/fail for the whole set
  local got
  got=$( . "$LIB"; _v="$1"; sc_norm_path _v; printf '%s' "$_v" )
  [ "$got" = "$2" ] || _TP_BAD="$_TP_BAD $3(got '$got')"
}
_tp_case "~/x"        "$HOME/x"     "tilde-slash"
_tp_case "  /a/b  "   "/a/b"        "trim"
_tp_case "~someone/x" "~someone/x"  "tilde-user-must-not-change"
_tp_case '$HOME/x'    '$HOME/x'     "dollar-HOME-must-not-change"
_tp_case "/plain/x"   "/plain/x"    "plain-absolute-unchanged"
[ -z "$_TP_BAD" ] && pass || fail "wrong normalisation:$_TP_BAD"

begin_test "every hook that stats a tool-supplied path normalises it first"
# Registration check: a new guard copying the old extraction would be bypassable
# again, and nothing else would say so.
_TP_MISSING=""
for _h in "$REPO_DIR"/hooks/*.sh; do
  grep -qE 'tool_input\.(file_path|notebook_path|path)' "$_h" || continue
  grep -qE '\[ -[fesr] "\$' "$_h" || continue          # only the ones that stat
  grep -q 'sc_norm_path' "$_h" || _TP_MISSING="$_TP_MISSING $(basename "$_h")"
done
# repetition-detector uses the path as a dedupe KEY and never stats it, so a
# spelling difference costs at most a missed dedupe.
_TP_MISSING="${_TP_MISSING// repetition-detector.sh/}"
[ -z "$_TP_MISSING" ] && pass || fail "stats a raw tool path:$_TP_MISSING"

# --- behavioural: a content scanner ------------------------------------------
# The fixture must live under $HOME — the whole point is tilde expansion.
_TP_D="$HOME/.sc-test-toolpath-$$"
mkdir -p "$_TP_D"
_TP_KEY="sk-ant-api03-$(printf 'D%.0s' $(seq 95))"
printf '<html>%s</html>' "$_TP_KEY" > "$_TP_D/secret.html"
printf '<p>ordinary</p>' > "$_TP_D/clean.html"
_TP_REL="~/.sc-test-toolpath-$$"
_tp_rc() {
  printf '{"tool_name":"Artifact","cwd":"/tmp","tool_input":{"file_path":"%s"}}' "$1" \
    | bash "$REPO_DIR/hooks/artifact-publish-guard.sh" >/dev/null 2>&1; echo $?
}

begin_test "A: an absolute path to a credential is denied (baseline)"
# Without this the rest prove nothing — silence could be no bug or no fixture.
[ "$(_tp_rc "$_TP_D/secret.html")" = "2" ] && pass \
  || fail "baseline is not a deny; the assertions below are meaningless"

begin_test "B: the same file spelled with ~ is denied too"
[ "$(_tp_rc "$_TP_REL/secret.html")" = "2" ] && pass \
  || fail "tilde path published unscanned — the harness would have read it"

begin_test "C: leading whitespace does not hide the file either"
[ "$(_tp_rc "   $_TP_D/secret.html")" = "2" ] && pass \
  || fail "whitespace-padded path published unscanned"

begin_test "D: a genuinely missing file is still a silent no-op"
[ "$(_tp_rc "$_TP_REL/nope.html")" = "0" ] && pass || fail "fired on a missing file"

begin_test "E: a clean page under ~ is still silent"
[ "$(_tp_rc "$_TP_REL/clean.html")" = "0" ] && pass || fail "false positive on clean content"

# --- behavioural: the project boundary ---------------------------------------
_tp_pg() {
  printf '{"tool_name":"Write","cwd":"%s","workspace":{"current_dir":"%s"},"session_id":"tp","tool_input":{"file_path":"%s","content":"x"}}' \
    "$REPO_DIR" "$REPO_DIR" "$1" | bash "$REPO_DIR/hooks/path-guard.sh" 2>/dev/null
}

begin_test "F: a write inside the project stays silent"
[ -z "$(_tp_pg "$REPO_DIR/README.md")" ] && pass || fail "path-guard fired inside the project"

begin_test "G: an absolute write outside the project fires (baseline)"
case "$(_tp_pg "$HOME/.sc-test-toolpath-$$/x.txt")" in
  *permissionDecision*) pass ;;
  *) fail "baseline does not fire; H below would prove nothing" ;;
esac

begin_test "H: a ~ write outside the project fires the same way"
case "$(_tp_pg "$_TP_REL/x.txt")" in
  *permissionDecision*) pass ;;
  '') fail "tilde escaped the project boundary — read as a write INSIDE it" ;;
  *) fail "unexpected path-guard output" ;;
esac

rm -rf "$_TP_D"

report
