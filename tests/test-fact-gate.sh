#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/fact-gate.sh"

echo "=== fact-gate Tests ==="
export SUPERCHARGER_NO_DEDUP=1

# Isolated HOME per call so markers never touch the real scope dir.
# Echoes the hook stdout; caller inspects it. (Deny path exits 2, allow exits 0.)
_run() { # <home> <session> <tool> <file> [enabled=1] [key=file_path]
  local home="$1" sid="$2" tool="$3" file="$4" en="${5:-1}" key="${6:-file_path}"
  local env="SUPERCHARGER_FACT_GATE=$en"
  [ "$en" = "0" ] && env="SUPERCHARGER_FACT_GATE=0"
  printf '{"session_id":"%s","tool_name":"%s","tool_input":{"%s":"%s"},"cwd":"%s"}' \
    "$sid" "$tool" "$key" "$file" "$(dirname "$file")" \
    | HOME="$home" env "SUPERCHARGER_FACT_GATE=$en" bash "$HOOK" 2>/dev/null
}

begin_test "fact-gate: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "fact-gate: OFF by default — first edit allowed, silent"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
OUT=$(_run "$H" sA Edit "$F" 0)
[ -z "$OUT" ] && pass || fail "expected no output when disabled, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — first edit of a file is denied with a fact demand"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
OUT=$(_run "$H" sA Edit "$F" 1)
echo "$OUT" | grep -q 'permissionDecision.*deny' && echo "$OUT" | grep -qi 'FACT-GATE' \
  && pass || fail "expected first-touch deny, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — second edit of same file is allowed (marker set)"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
_run "$H" sA Edit "$F" 1 >/dev/null   # first touch stamps the marker
OUT=$(_run "$H" sA Edit "$F" 1)
[ -z "$OUT" ] && pass || fail "expected retry to pass, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — a different file gets its own first-touch deny"
H=$(mktemp -d); PROJ=$(mktemp -d)
_run "$H" sA Edit "$PROJ/a.ts" 1 >/dev/null
OUT=$(_run "$H" sA Edit "$PROJ/b.ts" 1)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny on new file, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — .claude/ control path is exempt (allowed)"
H=$(mktemp -d); PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude"
OUT=$(_run "$H" sA Write "$PROJ/.claude/settings.json" 1)
[ -z "$OUT" ] && pass || fail "expected exempt .claude path, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — .supercharger.json is exempt (allowed)"
H=$(mktemp -d); PROJ=$(mktemp -d)
OUT=$(_run "$H" sA Write "$PROJ/.supercharger.json" 1)
[ -z "$OUT" ] && pass || fail "expected exempt config, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — stale marker re-demands (TTL)"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/app.ts"
printf '{"session_id":"sA","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" \
  | HOME="$H" SUPERCHARGER_FACT_GATE=1 SUPERCHARGER_FACT_GATE_TTL=1 bash "$HOOK" >/dev/null 2>&1
sleep 2
OUT=$(printf '{"session_id":"sA","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" \
  | HOME="$H" SUPERCHARGER_FACT_GATE=1 SUPERCHARGER_FACT_GATE_TTL=1 bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected re-demand after TTL, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — fail-open on missing file_path"
H=$(mktemp -d)
OUT=$(printf '{"session_id":"sA","tool_name":"Edit","tool_input":{}}' | HOME="$H" SUPERCHARGER_FACT_GATE=1 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
rm -rf "$H"

begin_test "fact-gate: ON — fail-open on missing session_id"
H=$(mktemp -d); PROJ=$(mktemp -d); F="$PROJ/x.ts"
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$F" "$PROJ" | HOME="$H" SUPERCHARGER_FACT_GATE=1 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
rm -rf "$H" "$PROJ"

begin_test "fact-gate: ON — fail-open on malformed JSON"
H=$(mktemp -d)
OUT=$(printf 'not json' | HOME="$H" SUPERCHARGER_FACT_GATE=1 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
rm -rf "$H"

report
