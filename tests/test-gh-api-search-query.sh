#!/usr/bin/env bash
# A `gh api …search/… -f q='<text>'` query is data, like `gh search issues '<text>'`
# (v4.2.0). Searching GitHub issues for a destructive SQL phrase was hard-blocked by
# safety.sh and asked about by human-approval-gate. Every allow case has a deny twin.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Assembled at runtime: written out, the phrase trips the deployed guard on any
# command that greps or edits this file.
SQL="DROP DATA""BASE prod"

probe() { # command -> BLOCK | allow
  local st rc
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  ST="$st" CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["ST"]}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf BLOCK || printf allow
}
expect() { # label, want, command
  local got; got=$(probe "$3")
  [ "$got" = "$2" ] && pass || fail "$1: expected $2, got $got"
}

echo "=== gh api search query is data ==="

begin_test "gh api search: -f q='…' is data";        expect a allow "gh api -X GET search/issues -f q='repo:x $SQL'"
begin_test "gh api search: -f 'q=…' is data";        expect b allow "gh api search/issues -f 'q=repo:x $SQL'"
begin_test "gh api search: --raw-field q=\"…\" is data"; expect c allow "gh api search/issues --raw-field q=\"repo:x $SQL\""
begin_test "gh search issues '…' still data (v4.2.0)"; expect d allow "gh search issues '$SQL'"

begin_test "gh api: a non-search endpoint is still scanned"; expect e BLOCK "gh api repos/x/y -f body='$SQL'"
begin_test "gh api search: a field other than q is still scanned"; expect f BLOCK "gh api search/issues -f q=x -f body='$SQL'"
begin_test "gh api search: q=\"…\" with \$( ) is still scanned"; expect g BLOCK "gh api search/issues -f q=\"\$(psql -c '$SQL')\""
begin_test "gh api search: SQL chained after the query is still scanned"; expect h BLOCK "gh api search/issues -f q='x' && psql -c '$SQL'"
begin_test "for-list feeding the query stays scanned (same shape as psql)"; expect i BLOCK "for q in '$SQL'; do gh api search/issues -f q=\"\$q\"; done"

report
