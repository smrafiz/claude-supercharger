#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/file-lease.sh"

echo "=== file-lease Tests ==="

export SUPERCHARGER_NO_DEDUP=1

# Each test runs with an isolated HOME so leases never touch the real scope dir.
_run() { # <home> <session> <tool> <file> [key]
  local home="$1" sid="$2" tool="$3" file="$4" key="${5:-file_path}"
  printf '{"session_id":"%s","tool_name":"%s","tool_input":{"%s":"%s"},"cwd":"%s"}' \
    "$sid" "$tool" "$key" "$file" "$(dirname "$file")" \
    | HOME="$home" bash "$HOOK" 2>/dev/null
}

begin_test "file-lease: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "file-lease: first edit by a session is silent (no conflict)"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
OUT=$(_run "$H" sessA Edit "$F")
[ -z "$OUT" ] && pass || fail "expected no output on first touch, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: peer session editing the same file gets a conflict warning"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
_run "$H" sessA Edit "$F" >/dev/null       # A takes the lease
OUT=$(_run "$H" sessB Write "$F")          # B collides
echo "$OUT" | grep -qi 'additionalContext' && echo "$OUT" | grep -qi 'session' \
  && pass || fail "expected concurrent-session warning, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: same session re-editing its own file is silent"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
_run "$H" sessA Edit "$F" >/dev/null
OUT=$(_run "$H" sessA Edit "$F")
[ -z "$OUT" ] && pass || fail "expected no self-conflict, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: peer editing a DIFFERENT file is silent"
H=$(mktemp -d); PROJ=$(mktemp -d)
_run "$H" sessA Edit "$PROJ/a.ts" >/dev/null
OUT=$(_run "$H" sessB Edit "$PROJ/b.ts")
[ -z "$OUT" ] && pass || fail "expected no conflict on different file, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: expired peer lease does not warn (TTL)"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
printf '{"session_id":"sessA","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" \
  | HOME="$H" SUPERCHARGER_FILE_LEASE_TTL=1 bash "$HOOK" >/dev/null 2>&1
sleep 2
OUT=$(printf '{"session_id":"sessB","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" \
  | HOME="$H" SUPERCHARGER_FILE_LEASE_TTL=1 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no warning after TTL expiry, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: NotebookEdit peer conflict via notebook_path"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/nb.ipynb"
_run "$H" sessA NotebookEdit "$F" notebook_path >/dev/null
OUT=$(_run "$H" sessB NotebookEdit "$F" notebook_path)
echo "$OUT" | grep -qi 'additionalContext' && pass || fail "expected notebook conflict, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: fail-open on missing file_path"
H=$(mktemp -d)
OUT=$(printf '{"session_id":"sessA","tool_name":"Edit","tool_input":{}}' | HOME="$H" bash "$HOOK" 2>/dev/null)
RC=$?
[ -z "$OUT" ] && [ "$RC" = "0" ] && pass || fail "expected silent exit 0, got rc=$RC out=$OUT"
rm -rf "$H"

begin_test "file-lease: fail-open on missing session_id"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/x.ts"
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" | HOME="$H" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent exit 0 without session_id, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "file-lease: fail-open on malformed JSON"
H=$(mktemp -d)
OUT=$(printf 'not json' | HOME="$H" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent exit 0 on garbage, got: $OUT"
rm -rf "$H"

begin_test "file-lease: disabled via SUPERCHARGER_FILE_LEASE=0"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
_run "$H" sessA Edit "$F" >/dev/null
OUT=$(printf '{"session_id":"sessB","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" \
  | HOME="$H" SUPERCHARGER_FILE_LEASE=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no output when disabled, got: $OUT"
rm -rf "$H" "$PROJ"

report
