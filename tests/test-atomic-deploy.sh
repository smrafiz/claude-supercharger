#!/usr/bin/env bash
# deploy_hook_scripts must never leave a live hook half-written. It used to `cp` over
# the installed files in place, so a hook that fired during an update (or was already
# running: bash reads a script as it executes) hit a syntax error mid-file
# ("unexpected |" at typecheck.sh:123, during an update to 4.3.6). The deploy now
# stages and renames, so a reader sees the old file or the new one, never a torn one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
# shellcheck source=/dev/null
source "$REPO_DIR/lib/utils.sh" 2>/dev/null
# shellcheck source=/dev/null
source "$REPO_DIR/lib/hooks.sh"
D="$HOME/.claude/supercharger"

begin_test "atomic deploy: first deploy installs hooks, tools and lib"
deploy_hook_scripts "$REPO_DIR" >/dev/null 2>&1
[ -s "$D/hooks/typecheck.sh" ] && [ -s "$D/hooks/webhook-lib.sh" ] && [ -s "$D/hooks/safety-detect.py" ] \
  && [ -s "$D/tools/update.sh" ] && [ -s "$D/lib/utils.sh" ] && pass || fail "missing files: $(ls "$D"/*)"

begin_test "atomic deploy: no staging dirs left behind"
left=$(find "$D" -name '.stage.*' | head -3)
[ -z "$left" ] && pass || fail "leftover: $left"

begin_test "atomic deploy: modes kept (hooks and tools 700)"
m() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
case "$OSTYPE" in
  msys*|cygwin*) echo "    (skipped: NTFS has no mode 700; Git Bash reports 755 whatever chmod set)"; pass ;;
  *) [ "$(m "$D/hooks/typecheck.sh")" = 700 ] && [ "$(m "$D/tools/update.sh")" = 700 ] && pass || fail "modes: $(m "$D/hooks/typecheck.sh") $(m "$D/tools/update.sh")" ;;
esac

begin_test "atomic deploy: a reader during redeploys never sees a partial hook"
want=$(wc -c < "$D/hooks/typecheck.sh")
( for _ in $(seq 1 6); do deploy_hook_scripts "$REPO_DIR" >/dev/null 2>&1; done; : > "$T/done" ) &
bad=0; n=0
while [ ! -f "$T/done" ]; do
  got=$(wc -c < "$D/hooks/typecheck.sh" 2>/dev/null || echo 0)
  n=$((n + 1)); [ "$got" -eq "$want" ] || bad=$((bad + 1))
done
wait
[ "$bad" -eq 0 ] && pass || fail "$bad of $n reads saw a partial file"

report
