#!/usr/bin/env bash
# enforce-pkg-manager: blocks the wrong package manager, and (v2.x Phase 2) now honors
# the /sc-off kill-switch via lib-timing instrumentation.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/enforce-pkg-manager.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Enforce Pkg Manager Tests ==="

D=$(mktemp -d); mkdir -p "$D/proj" "$D/state/scope"
printf 'lockfileVersion: 6\n' > "$D/proj/pnpm-lock.yaml"   # pnpm project
DIS=".supercharger-""disabled"   # split so nothing trips on the literal

_rc() { C="$2" python3 -c 'import json,os,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["C"]},"cwd":sys.argv[1],"session_id":"e"}))' "$D/proj" \
  | SUPERCHARGER_STATE="$1" bash "$HOOK" >/dev/null 2>&1; echo $?; }

begin_test "blocks the wrong package manager (npm in a pnpm project)"
[ "$(_rc "$D/state" 'npm install lodash')" = 2 ] && pass || fail "expected block (rc 2)"

begin_test "allows the correct package manager"
[ "$(_rc "$D/state" 'pnpm install')" = 0 ] && pass || fail "expected allow (rc 0)"

begin_test "no crash on a benign non-install command (set -e/-u safe)"
[ "$(_rc "$D/state" 'ls -la')" = 0 ] && pass || fail "expected clean exit 0"

begin_test "honors /sc off — inert when the kill-switch flag is present"
printf 'disabled\n' > "$D/state/scope/$DIS"
[ "$(_rc "$D/state" 'npm install lodash')" = 0 ] && pass || fail "should NOT block when Supercharger is off"
rm -f "$D/state/scope/$DIS"

rm -rf "$D"
report
