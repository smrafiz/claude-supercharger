#!/usr/bin/env bash
# office-read.sh (2026-11-17, from tsrmehmet/memokit's convert-read.sh): an opt-in
# Read of a PDF or Office file inside the project is redirected to a cached Markdown
# conversion by markitdown. A fake markitdown on PATH stands in for the real one.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/office-read.sh"
echo "=== office-read ==="

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P); TP="$T"   # TP: POSIX form, for PATH (a drive colon would split it)
# Windows: the hook's python is native, so it gets native paths (as Claude Code sends
# them), and finds a .cmd fake through PATHEXT; a shebang script is not runnable there.
WIN=""; case "$OSTYPE" in msys*|cygwin*) WIN=1; T=$(cygpath -m "$T") ;; esac
mkdir -p "$T/bin" "$T/proj/docs" "$T/home" "$T/state" "$T/out"
cat > "$T/bin/markitdown" <<'EOF'
#!/bin/sh
echo "converted:$(basename "$1")"
echo x >> "$CALLS"
EOF
chmod +x "$T/bin/markitdown"
[ -n "$WIN" ] && printf '@echo off\r\necho converted:%%~nx1\r\necho x>>"%%CALLS%%"\r\n' > "$T/bin/markitdown.cmd"
printf 'PK fake docx' > "$T/proj/docs/spec.docx"
printf '%%PDF fake' > "$T/proj/docs/r.pdf"
printf '%%PDF fake' > "$T/out/other.pdf"
export CALLS="$T/calls"

# read_ <file_path> [extra json] [env...] → hook stdout
read_() {
  local fp="$1" extra="${2:-}"; shift 2 2>/dev/null || shift
  printf '{"tool_name":"Read","session_id":"o1","cwd":"%s","tool_input":{"file_path":"%s"%s}}' "$T/proj" "$fp" "$extra" \
    | env HOME="$T/home" SUPERCHARGER_STATE="$T/state" CLAUDE_PROJECT_DIR="$T/proj" PATH="$TP/bin:$PATH" SUPERCHARGER_MARKITDOWN=1 "$@" bash "$H" 2>/dev/null
}
newpath() { printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin)['hookSpecificOutput']['updatedInput']['file_path'])" 2>/dev/null; }

begin_test "a .docx in the project is redirected to its Markdown conversion"
out=$(read_ "$T/proj/docs/spec.docx"); np=$(newpath "$out")
[ -n "$np" ] && [ "$(tr -d '\r' < "$np")" = "converted:spec.docx" ] && [[ "$out" == *'"allow"'* ]] && pass || fail "no redirect: $out"

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

# Git Bash `ln -s` makes a COPY without developer mode, so the row means nothing there.
if [ -z "$WIN" ]; then
  begin_test "a symlink pointing outside the project is left alone"
  ln -s "$T/out/other.pdf" "$T/proj/docs/link.pdf"
  [ -z "$(read_ "$T/proj/docs/link.pdf")" ] && pass || fail "symlink redirected"
fi

begin_test "a Read deny rule under CLAUDE_CONFIG_DIR keeps the hook out"
mkdir -p "$T/cfg"
printf '{"permissions":{"ask":["Read(./docs/r.pdf)"]}}' > "$T/cfg/settings.json"
[ -z "$(read_ "$T/proj/docs/r.pdf" '' CLAUDE_CONFIG_DIR="$T/cfg")" ] && pass || fail "redirected past a CLAUDE_CONFIG_DIR rule"
rm "$T/cfg/settings.json"

begin_test "output over the size cap falls back to the plain Read"
printf '%%PDF big' > "$T/proj/docs/cap.pdf"
[ -z "$(read_ "$T/proj/docs/cap.pdf" '' SUPERCHARGER_OFFICE_READ_MAX=5)" ] && pass || fail "oversized conversion handed back"

# A shebang fake is not runnable on Windows, so the kill row is POSIX-only.
if [ -z "$WIN" ]; then
  begin_test "a markitdown slower than the inner timeout: fall back, no temp file, child killed"
  mkdir -p "$T/slowbin"
  printf '#!/bin/sh\nsleep 60 &\necho $! > "$PIDF"\nwait\n' > "$T/slowbin/markitdown"
  chmod +x "$T/slowbin/markitdown"
  printf '%%PDF slow' > "$T/proj/docs/slow.pdf"
  export PIDF="$T/pid"
  out=$(read_ "$T/proj/docs/slow.pdf" '' PATH="$T/slowbin:$PATH" SUPERCHARGER_OFFICE_READ_TIMEOUT=1)
  alive=1; for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null || { alive=0; break; }; sleep 0.5; done
  stray=$(find "$T/state/office-read" -type f -name 'tmp*' | wc -l | tr -d ' ')
  [ -z "$out" ] && [ "$alive" = 0 ] && [ "$stray" = 0 ] && pass || fail "out=[$out] child alive=$alive stray=$stray"
fi

begin_test "other extensions are ignored"
printf 'x' > "$T/proj/docs/a.txt"
[ -z "$(read_ "$T/proj/docs/a.txt")" ] && pass || fail ".txt redirected"

report
