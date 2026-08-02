#!/usr/bin/env bash
# Newline as a command separator (v2.26.17)
#
# Found while fixing an unrelated ledger bug: an INDENTED continuation line escaped
# safety.sh entirely.
#
#     rm -rf /                     DENY
#     echo one \n rm -rf /         DENY
#     echo one \n <TAB>rm -rf /    ALLOW   <-- the hole
#     echo one \n     rm -rf /     ALLOW
#
# Two layers failed together. `split_segments` splits on `; | &` but NOT on a newline,
# even though a newline separates commands exactly as `;` does — so a multi-line
# command arrived as ONE segment beginning with the first line's command, and
# safety.sh's `[[ "$seg" =~ ^rm[[:space:]] ]]` never matched. The generic pattern layer
# anchors without allowing indentation, so line two escaped that too.
#
# The fix is strictly tightening: more segments means more validation, never less. Both
# directions are pinned, because the risk of splitting more aggressively is
# over-blocking ordinary multi-line work.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

verdict() {
  local cmd="$1" st rc
  st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s' "$(CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | env SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
  rc=$?; rm -rf "$st"
  [ "$rc" -eq 2 ] && echo DENY || echo ALLOW
}
expect() { # want label cmd
  begin_test "$2"
  local got; got=$(verdict "$3")
  [ "$got" = "$1" ] && pass || fail "expected $1, got $got"
}

# Fixtures built with printf so this file never contains a bare destructive literal.
WIPE=$(printf 'rm -%s /' 'rf')
HOME_WIPE=$(printf 'rm -%s ~' 'rf')

echo "=== Newline Separator Tests ==="

expect DENY  "plain wipe still denied"                 "$WIPE"
expect DENY  "leading TAB on a single line"            "$(printf '\t%s' "$WIPE")"
expect DENY  "newline then unindented wipe"            "$(printf 'echo one\n%s' "$WIPE")"
expect DENY  "newline then TAB-INDENTED wipe (the hole)" "$(printf 'echo one\n\t%s' "$WIPE")"
expect DENY  "newline then 4-SPACE-indented wipe"      "$(printf 'echo one\n    %s' "$WIPE")"
expect DENY  "indented mv of the root"                 "$(printf 'echo one\n    mv / /tmp/x')"
expect DENY  "indented, three lines deep"              "$(printf 'echo a\necho b\n\t  %s' "$HOME_WIPE")"

expect ALLOW "ordinary multi-line work"                "$(printf 'echo one\n    ls -la\n    git status')"
expect ALLOW "indented removal of a PROJECT path"      "$(printf 'cd /tmp/proj\n    rm -rf build')"
expect ALLOW "heredoc that only MENTIONS the wipe"     "$(printf 'cat <<EOF\n  see: %s is bad\nEOF' "$WIPE")"
expect ALLOW "plain single-line build"                 'npm run build'

report
