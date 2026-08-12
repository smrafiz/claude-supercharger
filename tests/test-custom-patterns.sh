#!/usr/bin/env bash
# Per-project custom patterns (v2.26.21)
#
# The on-thesis answer to "I want my own rules". A project adds `customPatterns` to
# .supercharger.json and gets extra blocks — config that survives updates, rather than
# forking the hooks (which harness-tamper-guard exists to prevent, and which would
# strand the repo on stale security patterns).
#
# The property that matters most is NOT that a custom pattern blocks. It is that a BAD
# custom pattern cannot disable the built-ins. Every built-in is joined into a single
# alternation and matched in one grep call; adding a malformed user regex to that
# alternation would make grep error, the `if` go false, and every destructive pattern
# silently stop matching. One typo in a project config would switch off the guard.
# Custom patterns are therefore evaluated in a SEPARATE pass, and that isolation is
# what these tests exist to hold.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# v2.26.34: customPatterns is keyed by project path now (the tightening twin of
# audit HIGH #13 — one project's extra rules used to fire in every project).
# Fixture-based tests below still use the un-suffixed name on purpose: that
# exercises the legacy-global fallback.
_pkey() {
  sc_key_for "$1"   # shared: tests/helpers.sh
}

HOOK="$REPO_DIR/hooks/safety.sh"

# Run safety.sh with a given set of custom patterns; echo DENY or ALLOW.
verdict() { # cmd, [pattern...]
  local cmd="$1"; shift
  local st rc
  st=$(mktemp -d); mkdir -p "$st/scope"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$st/scope/.custom-patterns"; fi
  printf '%s' "$(CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | env SUPERCHARGER_STATE="$st" bash "$HOOK" >/dev/null 2>&1
  rc=$?; rm -rf "$st"
  [ "$rc" -eq 2 ] && echo DENY || echo ALLOW
}
stderr_of() { # cmd, [pattern...]
  local cmd="$1"; shift
  local st out
  st=$(mktemp -d); mkdir -p "$st/scope"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$st/scope/.custom-patterns"; fi
  out=$(printf '%s' "$(CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | env SUPERCHARGER_STATE="$st" bash "$HOOK" 2>&1 >/dev/null)
  rm -rf "$st"; printf '%s' "$out"
}

WIPE=$(printf 'rm -%s /' 'rf')

echo "=== Custom Project Pattern Tests ==="

begin_test "a custom pattern blocks what it names"
[ "$(verdict 'terraform apply -auto-approve' 'terraform[[:space:]]+apply')" = "DENY" ] && pass || fail "custom pattern did not block"

begin_test "the block names the custom pattern, so /why is useful"
OUT=$(stderr_of 'terraform apply -auto-approve' 'terraform[[:space:]]+apply')
printf '%s' "$OUT" | grep -qi 'custom project pattern' && pass || fail "block reason does not identify it as a project rule: $OUT"

begin_test "no custom-patterns file → behaviour is unchanged"
[ "$(verdict 'terraform apply -auto-approve')" = "ALLOW" ] && pass || fail "blocked without any custom pattern"

begin_test "unrelated commands are unaffected by a custom pattern"
[ "$(verdict 'ls -la' 'terraform[[:space:]]+apply')" = "ALLOW" ] && pass || fail "over-blocked an unrelated command"

# --- the isolation property: a bad custom regex must not disable the built-ins ---
begin_test "MALFORMED custom regex does not disable built-in guards"
[ "$(verdict "$WIPE" 'foo[unclosed')" = "DENY" ] && pass || fail "a bad custom pattern switched off the built-in destructive guard"

begin_test "malformed custom regex is ANNOUNCED at config load, not silently dropped"
# Reported by project-config (SessionStart), NOT safety.sh: safety.sh only reaches the
# custom-pattern code for commands that survive its fast path, so a user with a typo
# could go a whole session without ever seeing it — believing a rule protects them when
# it does not. Validation also uses GREP, not python's re: they are different dialects
# and grep is what evaluates these at match time.
ST=$(mktemp -d); PD=$(mktemp -d); mkdir -p "$ST/scope"
cat > "$PD/.supercharger.json" <<'JSON'
{ "customPatterns": ["foo[unclosed", "terraform[[:space:]]+apply"] }
JSON
OUT=$(printf '{"cwd":"%s","workspace":{"current_dir":"%s"}}' "$PD" "$PD" \
  | env SUPERCHARGER_STATE="$ST" HOME="$PD" bash "$REPO_DIR/hooks/project-config.sh" 2>&1)
if printf '%s' "$OUT" | grep -qi 'INVALID customPatterns'; then
  grep -q 'terraform' "$ST/scope/.custom-patterns-$(_pkey "$PD")" 2>/dev/null && pass \
    || fail "invalid pattern reported but its valid sibling was dropped too"
else
  fail "invalid customPatterns not reported at config load: $OUT"
fi
rm -rf "$ST" "$PD"

begin_test "one bad pattern alongside good ones still leaves built-ins working"
[ "$(verdict "$WIPE" 'terraform[[:space:]]+apply' 'foo[unclosed')" = "DENY" ] && pass || fail "mixed valid/invalid disabled the built-ins"

begin_test "built-in patterns keep working with valid custom patterns present"
[ "$(verdict "$WIPE" 'terraform[[:space:]]+apply')" = "DENY" ] && pass || fail "valid custom patterns disturbed the built-ins"

# --- additive only: customPatterns may tighten, never loosen ---
begin_test "custom patterns cannot UNBLOCK a built-in denial"
# A customPattern matching a dangerous command can only add another reason to block
# it. Exempting a command is a separate, deliberately narrower mechanism —
# `allowPatterns` (v2.26.34, see test-allow-patterns.sh) — which cannot touch
# self-modification blocks and fails safe on a bad regex.
[ "$(verdict "$WIPE" 'rm')" = "DENY" ] && pass || fail "a custom pattern loosened the guard"

begin_test "an empty custom-patterns file is inert"
ST=$(mktemp -d); mkdir -p "$ST/scope"; : > "$ST/scope/.custom-patterns"
GOT=$(printf '%s' "$(CMD='ls -la' python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
  | env SUPERCHARGER_STATE="$ST" bash "$HOOK" >/dev/null 2>&1; echo $?)
rm -rf "$ST"
[ "$GOT" != "2" ] && pass || fail "an empty file caused a block"


# --- config plumbing ---
begin_test "project-config writes customPatterns to the scope file"
ST=$(mktemp -d); PD=$(mktemp -d); mkdir -p "$ST/scope"
cat > "$PD/.supercharger.json" <<'JSON'
{ "customPatterns": ["terraform[[:space:]]+apply", "kubectl[[:space:]]+delete"] }
JSON
printf '{"cwd":"%s","workspace":{"current_dir":"%s"}}' "$PD" "$PD" \
  | env SUPERCHARGER_STATE="$ST" HOME="$PD" bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1
PF="$ST/scope/.custom-patterns-$(_pkey "$PD")"
if [ -s "$PF" ] && grep -q 'terraform' "$PF"; then pass
else fail "customPatterns not written: $(ls -A "$ST/scope" 2>/dev/null | tr '\n' ' ')"; fi
rm -rf "$ST" "$PD"

begin_test "project-config bounds the list (a runaway config cannot flood the guard)"
ST=$(mktemp -d); PD=$(mktemp -d); mkdir -p "$ST/scope"
# The config filename arrives in two pieces because the whole literal in a
# command line trips our own self-modification guard. Path via argv, not
# interpolation: MSYS rewrites arguments, never the text inside `-c "..."`.
python3 -c "
import json, sys
json.dump({'customPatterns': ['p%d' % i for i in range(200)]}, open(sys.argv[1]+sys.argv[2],'w'))" "$PD/.supercharger" ".json"
printf '{"cwd":"%s","workspace":{"current_dir":"%s"}}' "$PD" "$PD" \
  | env SUPERCHARGER_STATE="$ST" HOME="$PD" bash "$REPO_DIR/hooks/project-config.sh" >/dev/null 2>&1
N=$(wc -l < "$ST/scope/.custom-patterns-$(_pkey "$PD")" 2>/dev/null | tr -d ' ')
[ "${N:-0}" -le 50 ] && pass || fail "wrote $N patterns; expected a cap of 50"
rm -rf "$ST" "$PD"

report
