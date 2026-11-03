#!/usr/bin/env bash
# KNOWN-ISSUES #8: the shipped-commands generator saw only this machine's git refs, so a
# fresh clone dropped hashes of versions that did ship. It must only ever add lines.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== gen-commands-shipped: union with the committed list ==="

T=$(mktemp -d)
mkdir -p "$T/tools" "$T/configs/commands"
cp "$REPO_DIR/tools/gen-commands-shipped.sh" "$T/tools/"
printf -- '---\ndescription: "x"\n---\nhello\n' > "$T/configs/commands/sc-demo.md"
# A version that shipped from a commit this clone cannot see.
printf 'sc-gone %064d\n' 0 > "$T/configs/commands-shipped.txt"
git -C "$T" init -q && git -C "$T" add -A \
  && git -C "$T" -c user.name=t -c user.email=t@t commit -qm init

begin_test "a committed hash with no reachable commit is kept"
bash "$T/tools/gen-commands-shipped.sh" >/dev/null 2>&1
grep -q '^sc-gone 0\{64\}$' "$T/configs/commands-shipped.txt" && pass || fail "dropped: $(cat "$T/configs/commands-shipped.txt")"

begin_test "the current command's hash is added"
grep -q '^sc-demo [0-9a-f]\{64\}$' "$T/configs/commands-shipped.txt" && pass || fail "missing sc-demo"

begin_test "a second run changes nothing"
cp "$T/configs/commands-shipped.txt" "$T/before"
bash "$T/tools/gen-commands-shipped.sh" >/dev/null 2>&1
cmp -s "$T/before" "$T/configs/commands-shipped.txt" && pass || fail "not idempotent"

rm -rf "$T"
report
