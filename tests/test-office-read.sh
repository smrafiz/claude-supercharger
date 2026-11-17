#!/usr/bin/env bash
# office-read.sh (2026-11-17, from tsrmehmet/memokit's convert-read.sh): an opt-in
# Read of a PDF or Office file inside the project is redirected to a cached Markdown
# conversion by markitdown. A fake markitdown on PATH stands in for the real one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/office-read.sh"
echo "=== office-read ==="

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
mkdir -p "$T/bin" "$T/proj/docs" "$T/home" "$T/state" "$T/out"
cat > "$T/bin/markitdown" <<'EOF'
#!/bin/sh
echo "converted:$(basename "$1")"
echo x >> "$CALLS"
EOF
chmod +x "$T/bin/markitdown"
printf 'PK fake docx' > "$T/proj/docs/spec.docx"
printf '%%PDF fake' > "$T/proj/docs/r.pdf"
printf '%%PDF fake' > "$T/out/other.pdf"
export CALLS="$T/calls"

# read_ <file_path> [extra json] [env...] → hook stdout
read_() {
  local fp="$1" extra="${2:-}"; shift 2 2>/dev/null || shift
  printf '{"tool_name":"Read","session_id":"o1","cwd":"%s","tool_input":{"file_path":"%s"%s}}' "$T/proj" "$fp" "$extra" \
    | env HOME="$T/home" SUPERCHARGER_STATE="$T/state" CLAUDE_PROJECT_DIR="$T/proj" PATH="$T/bin:$PATH" SUPERCHARGER_MARKITDOWN=1 "$@" bash "$H" 2>/dev/null
}
newpath() { printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin)['hookSpecificOutput']['updatedInput']['file_path'])" 2>/dev/null; }

begin_test "a .docx in the project is redirected to its Markdown conversion"
out=$(read_ "$T/proj/docs/spec.docx"); np=$(newpath "$out")
[ -n "$np" ] && [ "$(cat "$np")" = "converted:spec.docx" ] && [[ "$out" == *'"allow"'* ]] && pass || fail "no redirect: $out"

begin_test "a second Read hits the cache (markitdown not run again)"
read_ "$T/proj/docs/spec.docx" >/dev/null
[ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] && pass || fail "converted twice"

begin_test "a changed file is converted again"
printf 'PK changed docx' > "$T/proj/docs/spec.docx"
read_ "$T/proj/docs/spec.docx" >/dev/null
[ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ] && pass || fail "stale cache served"

# Control for the negative rows below, which reuse r.pdf: without their condition it IS redirected.
begin_test "a PDF in the project is redirected (control)"
[ -n "$(newpath "$(read_ "$T/proj/docs/r.pdf")")" ] && pass || fail "r.pdf not redirected"

begin_test "a PDF Read with pages= is left alone (the model wants page images)"
[ -z "$(read_ "$T/proj/docs/r.pdf" ',"pages":"1-2"')" ] && pass || fail "pages Read redirected"

begin_test "a file outside the project is left alone"
[ -z "$(read_ "$T/out/other.pdf")" ] && pass || fail "outside file redirected"

begin_test "off unless SUPERCHARGER_MARKITDOWN=1"
[ -z "$(read_ "$T/proj/docs/r.pdf" '' SUPERCHARGER_MARKITDOWN=0)" ] && pass || fail "ran while off"

begin_test "without markitdown on PATH: left alone"
out=$(printf '{"tool_name":"Read","cwd":"%s","tool_input":{"file_path":"%s"}}' "$T/proj" "$T/proj/docs/r.pdf" \
  | env HOME="$T/home" SUPERCHARGER_STATE="$T/state" CLAUDE_PROJECT_DIR="$T/proj" PATH="/usr/bin:/bin" SUPERCHARGER_MARKITDOWN=1 /bin/bash "$H" 2>/dev/null)
[ -z "$out" ] && pass || fail "redirected without markitdown: $out"

begin_test "a Read deny rule anywhere keeps the hook out (a redirect would sidestep it)"
mkdir -p "$T/proj/.claude"
printf '{"permissions":{"deny":["Read(./docs/r.pdf)"]}}' > "$T/proj/.claude/settings.json"
[ -z "$(read_ "$T/proj/docs/r.pdf")" ] && pass || fail "redirected past a Read deny rule"
rm "$T/proj/.claude/settings.json"

begin_test "a symlink pointing outside the project is left alone"
ln -s "$T/out/other.pdf" "$T/proj/docs/link.pdf"
[ -z "$(read_ "$T/proj/docs/link.pdf")" ] && pass || fail "symlink redirected"

begin_test "other extensions are ignored"
printf 'x' > "$T/proj/docs/a.txt"
[ -z "$(read_ "$T/proj/docs/a.txt")" ] && pass || fail ".txt redirected"

report
