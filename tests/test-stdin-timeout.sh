#!/usr/bin/env bash
# A payload that does not arrive must not read as "nothing to check" (v4.0.28)
#
# Every hook read stdin with:
#
#   IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
#
# Two defects in one line. The blanking branch keys on `$? > 128`, which is bash
# 4+ behaviour — bash 3.2, /bin/bash on every macOS, returns 1 on a -t timeout.
# And it does not matter, because on timeout `read` DISCARDS the bytes it
# already had: the variable is empty either way, every guard takes its fast path
# and exits 0, and the tool then runs unchecked and unannounced.
#
# Measured on 3.2.57 with a writer slower than the timeout: rc=1, len=0, full
# timeout burned. Against the deployed artifact guard, same payload:
#
#   writer faster than the timeout   rc=2, deny
#   writer slower than the timeout   rc=0, no stdout, no stderr
#
# Unlike v4.0.26's unreadable-file case this is not self-limiting: a stalled
# read does not stop the tool, only the check. So gates now ASK.
#
# The control that matters most is C: genuinely empty stdin must stay SILENT.
# A guard that nags on every empty invocation gets switched off, and then none
# of this matters. [[failure-modes-collapse-to-one-verdict]]
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-stdin.sh"
GUARD="$REPO_DIR/hooks/artifact-publish-guard.sh"

echo "=== stdin-timeout Tests ==="

begin_test "the shared reader exists"
[ -f "$LIB" ] && pass || fail "hooks/lib-stdin.sh missing"

begin_test "it does not key the timeout on an exit code above 128 alone"
# The bug this file exists for. `$? -gt 128` may still appear as a SECOND
# condition (it is correct on bash 4+), but elapsed time must be there too.
grep -q 'SECONDS - _sc_t0' "$LIB" && pass \
  || fail "no elapsed-time check — bash 3.2 returns 1 on timeout, not >128"

begin_test "every deny-capable hook reads stdin through it"
# A new gate that copies the old inline line would be silently unguarded again.
_STO_MISSING=""
for _h in "$REPO_DIR"/hooks/*.sh; do
  case "$(basename "$_h")" in lib-*) continue ;; esac
  grep -q 'permissionDecision' "$_h" || continue
  grep -q "read -r -d '' -t" "$_h" || continue        # uses the inline read
  _STO_MISSING="$_STO_MISSING $(basename "$_h")"
done
# budget-cap reads inside a function, twice, and is a COST cap: failing open on
# a stalled pipe costs one un-warned turn, not an unchecked security decision.
_STO_MISSING="${_STO_MISSING// budget-cap.sh/}"
[ -z "$_STO_MISSING" ] && pass || fail "still on the inline read:$_STO_MISSING"

# --- behavioural, through a real gate ----------------------------------------
# A short timeout keeps the suite fast; the code path is identical.
_STO_TD=$(mktemp -d)
_STO_KEY="sk-ant-api03-$(printf 'D%.0s' $(seq 95))"
printf '<html>%s</html>' "$_STO_KEY" > "$_STO_TD/secret.html"
printf '<p>ordinary</p>' > "$_STO_TD/clean.html"
_sto_payload() {
  printf '{"tool_name":"Artifact","cwd":"%s","tool_input":{"file_path":"%s"}}' "$_STO_TD" "$1"
}

begin_test "A: a payload that arrives is still denied (baseline)"
# Without this the three below prove nothing — silence could mean no bug or no
# fixture. [[measurement-fixture-defects]]
_STO_RC=$(_sto_payload "$_STO_TD/secret.html" | SUPERCHARGER_STDIN_TIMEOUT_S=1 bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$_STO_RC" = "2" ] && pass || fail "baseline is not a deny, rc=$_STO_RC — the rest of this block is meaningless"

begin_test "B: a payload slower than the timeout asks instead of allowing"
_STO_OUT=$({ _sto_payload "$_STO_TD/secret.html" | head -c 30; sleep 3; _sto_payload "$_STO_TD/secret.html" | tail -c +31; } \
  | SUPERCHARGER_STDIN_TIMEOUT_S=1 bash "$GUARD" 2>/dev/null)
case "$_STO_OUT" in
  *'"permissionDecision":"ask"'*) pass ;;
  '') fail "silent allow — the tool would run unchecked" ;;
  *) fail "unexpected output: ${_STO_OUT:0:80}" ;;
esac

begin_test "C: genuinely empty stdin stays silent"
_STO_OUT=$(printf '' | SUPERCHARGER_STDIN_TIMEOUT_S=1 bash "$GUARD" 2>&1)
[ -z "$_STO_OUT" ] && pass || fail "nags on empty stdin: ${_STO_OUT:0:80}"

begin_test "D: a clean page that arrives is still silent"
_STO_OUT=$(_sto_payload "$_STO_TD/clean.html" | SUPERCHARGER_STDIN_TIMEOUT_S=1 bash "$GUARD" 2>&1)
[ -z "$_STO_OUT" ] && pass || fail "false positive on a clean page: ${_STO_OUT:0:80}"

rm -rf "$_STO_TD"

report
