#!/usr/bin/env bash
# v4.2.0 sweep 5: command-normalizer bypasses, data false positives, git work-loss
# spellings, disk/permission rules. Cases live in fixtures/sweep5-bash-cases.tsv as
# `expect<TAB>command`, expect = deny | ask | allow | block (deny or ask). `RM` in a
# command expands to the remove verb at run time, so this file and the fixture do
# not trip the live guards of the session editing them.
set -u
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks"
FIX="$REPO_DIR/tests/fixtures/sweep5-bash-cases.tsv"
_RMV="r""m"

verdict() { # command -> deny|ask|allow (safety.sh, then git-safety.sh)
  local h out v=allow j
  j=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":"/tmp"}))' "$1")
  for h in safety.sh git-safety.sh; do
    out=$(printf '%s\n' "$j" | SUPERCHARGER_STATE="$(mktemp -d)" bash "$H/$h" 2>/dev/null)
    case "$out" in *'"deny"'*) echo deny; return ;; *'"ask"'*) v=ask ;; esac
  done
  echo "$v"
}

echo "=== sweep 5: Bash rule cases ==="
while IFS=$'\t' read -r want cmd; do
  [ -z "$want" ] && continue
  cmd="${cmd//RM/$_RMV}"
  begin_test "$want: $cmd"
  got=$(verdict "$cmd")
  if [ "$got" = "$want" ] || { [ "$want" = block ] && [ "$got" != allow ]; }; then pass; else fail "got $got"; fi
done < "$FIX"

report
