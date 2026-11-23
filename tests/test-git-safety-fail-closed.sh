#!/usr/bin/env bash
# 2026-11-23: git-safety.sh runs under `set -e`. A failing step used to exit 1 with no
# output, and onFailure:block showed "failed ... No stderr output" on a plain `git commit`.
# It must still block (exit 2) and say why on stderr.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/state/scope"
cp -R "$REPO_DIR/hooks" "$T/hooks"
IN='{"session_id":"g1","tool_name":"Bash","tool_input":{"command":"git commit -q -m \"docs: x\""},"cwd":"/tmp"}'
run() { printf '%s' "$IN" | env HOME="$T/home" SUPERCHARGER_STATE="$T/state" bash "$1" >/dev/null 2>"$T/err"; }

echo "=== git-safety: an internal failure blocks with a message ==="

begin_test "a normal git commit still passes (no fail-closed message)"
run "$T/hooks/git-safety.sh"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'before reaching a verdict' "$T/err" && pass || fail "rc=$rc err=$(head -c 200 "$T/err")"

begin_test "a failing step blocks (exit 2) and names the cause on stderr"
# Inject a failing command right after the payload read.
sed 's/^\(\. "\${BASH_SOURCE\[0\]%\/\*}\/lib-deny.sh"; sc_read_input _INPUT\)$/\1\
false/' "$T/hooks/git-safety.sh" > "$T/hooks/git-safety-broken.sh"
grep -qx false "$T/hooks/git-safety-broken.sh" || fail "fixture: injection point not found"
run "$T/hooks/git-safety-broken.sh"; rc=$?
[ "$rc" -eq 2 ] && grep -q 'before reaching a verdict' "$T/err" && pass || fail "rc=$rc err=$(head -c 200 "$T/err")"

report
