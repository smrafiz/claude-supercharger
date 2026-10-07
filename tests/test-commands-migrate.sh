#!/usr/bin/env bash
# 4.3.0: commands renamed to sc-<name>. The migration may only replace or remove a
# file whose content is a version we shipped; anything the user wrote or edited
# stays exactly as it was.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
M="$REPO_DIR/tools/commands-migrate.py"
SHIPPED="$REPO_DIR/configs/commands-shipped.txt"

# Byte-exact copies of shipped pre-rename versions (CI clones with no history).
old_version() { cat "$REPO_DIR/tests/fixtures/commands-old/$1.md"; }

T=$(mktemp -d); C="$T/c"; mkdir -p "$C"
old_version security > "$C/security.md"                 # ours, unmodified
old_version pr > "$C/pr.md"; echo edited >> "$C/pr.md"  # ours, edited
old_version doc > "$C/doc.md"                           # ours, dropped long ago
echo mine > "$C/build.md"                               # never ours
echo mine > "$C/sc-mine.md"                             # never ours, sc- spelled
cp "$REPO_DIR/configs/commands/"*.md "$C/"
OUT=$(python3 "$M" install "$C" "$REPO_DIR")

begin_test "migrate: an unmodified old command becomes a redirect to its sc- name"
grep -q 'supercharger:renamed' "$C/security.md" && grep -q '/sc-security' "$C/security.md" \
  && pass || fail "security.md: $(head -c 80 "$C/security.md")"

begin_test "migrate: a command the user edited is left alone, and the user is told"
tail -1 "$C/pr.md" | grep -qx edited && printf '%s' "$OUT" | grep -q '/pr: you edited it' \
  && pass || fail "pr.md changed or no notice"

begin_test "migrate: an unmodified command we dropped is removed"
[ ! -e "$C/doc.md" ] && pass || fail "doc.md left behind"

begin_test "migrate: files we never shipped are untouched"
{ [ "$(cat "$C/build.md")" = mine ] && [ "$(cat "$C/sc-mine.md")" = mine ]; } && pass || fail "foreign file touched"

begin_test "migrate: a second run changes nothing"
B=$(cd "$C" && cat ./*.md | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
python3 "$M" install "$C" "$REPO_DIR" >/dev/null
A=$(cd "$C" && cat ./*.md | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
[ "$A" = "$B" ] && pass || fail "not idempotent"

begin_test "uninstall: removes stubs and our files, keeps the user's"
python3 "$M" uninstall "$C" "$REPO_DIR"
for f in "$REPO_DIR/configs/commands/"*.md; do rm -f "$C/$(basename "$f")"; done
[ "$(cd "$C" && ls | tr '\n' ' ')" = "build.md pr.md sc-mine.md " ] && pass || fail "left: $(ls "$C" | tr '\n' ' ')"
rm -rf "$T"

begin_test "every shipped command is in the manifest, at its current content"
R=""
for f in "$REPO_DIR/configs/commands/"*.md; do
  h=$(tr -d '\r' < "$f" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
  grep -q "^$(basename "$f" .md) $h\$" "$SHIPPED" || R="$R $(basename "$f")"
done
[ -z "$R" ] && pass || fail "stale manifest — run tools/gen-commands-shipped.sh:$R"

begin_test "no shipped command keeps an unprefixed name"
R=$(cd "$REPO_DIR/configs/commands" && ls ./*.md | sed 's#^\./##' | grep -vE '^(sc-.*|sc|supercharger)\.md$' || true)
[ -z "$R" ] && pass || fail "unprefixed: $R"

report
