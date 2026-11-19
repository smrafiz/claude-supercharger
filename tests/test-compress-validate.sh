#!/usr/bin/env bash
# tools/compress/validate.py: a compression must not drop a negation or a
# MUST/NEVER/ONLY word, because losing one can reverse a rule while every
# structural check (headings, code, URLs, paths, bullets) still passes.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

D=$(mktemp -d)
# verdict <original text> <compressed text> -> "valid" or the first error
verdict() {
  printf '%s' "$1" > "$D/orig.md"; printf '%s' "$2" > "$D/comp.md"
  (cd "$REPO_DIR" && python3 -c '
import sys
from pathlib import Path
from tools.compress.validate import validate
r = validate(Path(sys.argv[1]), Path(sys.argv[2]))
print("valid" if r.is_valid else r.errors[0])' "$D/orig.md" "$D/comp.md")
}

ORIG=$'# Rules\n\n- Never push to main without a review.\n- You must run the tests before every commit.\n'

begin_test "compress-validate: a dropped never fails"
case "$(verdict "$ORIG" $'# Rules\n\n- Push to main without a review.\n- Must run tests before every commit.\n')" in
  *"Negation words dropped"*) pass ;; *) fail "accepted a reversed rule" ;; esac

begin_test "compress-validate: a dropped must fails"
case "$(verdict "$ORIG" $'# Rules\n\n- Never push to main without review.\n- Run tests before every commit.\n')" in
  *"MUST/NEVER/ONLY/ALWAYS words dropped"*) pass ;; *) fail "accepted a weakened rule" ;; esac

begin_test "compress-validate: do not rewritten as don't passes"
O2=$'# Rules\n\n- Do not edit generated files.\n'
case "$(verdict "$O2" $'# Rules\n\n- Don\'t edit generated files.\n')" in
  valid) pass ;; *) fail "rejected an equivalent rewrite" ;; esac

begin_test "compress-validate: a terse rewrite that keeps every rule word passes"
case "$(verdict "$ORIG" $'# Rules\n\n- Never push main without review.\n- Must run tests before each commit.\n')" in
  valid) pass ;; *) fail "rejected a faithful compression" ;; esac

rm -rf "$D"
report
