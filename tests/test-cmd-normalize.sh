#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/cmd-normalize.sh"

echo "=== Command Normalize Tests ==="

# shellcheck source=hooks/cmd-normalize.sh
. "$LIB"

# --- normalize_cmd ---

begin_test "normalize_cmd: trims leading whitespace"
OUT=$(normalize_cmd "   ls -la")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: trims trailing whitespace"
OUT=$(normalize_cmd "ls -la   ")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips leading backslash (PS1 escape)"
OUT=$(normalize_cmd '\ls -la')
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips single sudo prefix"
OUT=$(normalize_cmd "sudo rm -rf /tmp/x")
[ "$OUT" = "rm -rf /tmp/x" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips command prefix"
OUT=$(normalize_cmd "command ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips env prefix AND inline env-vars (v2.6.80)"
OUT=$(normalize_cmd "env FOO=bar ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips bare inline env-var prefix (v2.6.80)"
OUT=$(normalize_cmd "PATH=/usr/bin ls")
[ "$OUT" = "ls" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips multiple chained inline env-vars (v2.6.80)"
OUT=$(normalize_cmd "FOO=bar PATH=/usr/bin BAZ=qux ls -la")
[ "$OUT" = "ls -la" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: strips nested sudo+command prefixes"
OUT=$(normalize_cmd "sudo command rm -rf /tmp/x")
[ "$OUT" = "rm -rf /tmp/x" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: collapses repeated spaces"
OUT=$(normalize_cmd "ls   -la    /tmp")
[ "$OUT" = "ls -la /tmp" ] && pass || fail "got: '$OUT'"

begin_test "normalize_cmd: leaves benign commands alone"
OUT=$(normalize_cmd "git status")
[ "$OUT" = "git status" ] && pass || fail "got: '$OUT'"

# --- split_segments ---

begin_test "split_segments: splits on &&"
OUT=$(split_segments "cd /tmp && ls -la")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && echo "$OUT" | grep -qx "cd /tmp" && echo "$OUT" | grep -qx "ls -la" && pass || fail "got: $OUT"

begin_test "split_segments: splits on ||"
OUT=$(split_segments "a || b")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs, got: $OUT"

begin_test "split_segments: splits on ;"
OUT=$(split_segments "a ; b ; c")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "3" ] && pass || fail "expected 3 segs, got: $OUT"

begin_test "split_segments: splits on | (pipe)"
OUT=$(split_segments "cat foo | grep bar")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs, got: $OUT"

begin_test "split_segments: does NOT split on && inside single quotes"
OUT=$(split_segments "echo 'a && b' ; ls")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs (quote-aware), got: $OUT"

begin_test "split_segments: does NOT split on ; inside double quotes"
OUT=$(split_segments "echo \"a ; b\" ; ls")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "2" ] && pass || fail "expected 2 segs (quote-aware), got: $OUT"

begin_test "split_segments: strips sudo from each segment"
OUT=$(split_segments "sudo rm -rf /tmp/a && sudo rm -rf /tmp/b")
echo "$OUT" | grep -qx "rm -rf /tmp/a" && echo "$OUT" | grep -qx "rm -rf /tmp/b" && pass || fail "got: $OUT"

begin_test "split_segments: single command returns 1 segment"
OUT=$(split_segments "ls -la")
LINES=$(printf '%s' "$OUT" | awk 'END{print NR}')
[ "$LINES" = "1" ] && pass || fail "got: $OUT"

begin_test "split_segments: empty input returns no segments"
OUT=$(split_segments "")
[ -z "$OUT" ] && pass || fail "got: $OUT"

report
