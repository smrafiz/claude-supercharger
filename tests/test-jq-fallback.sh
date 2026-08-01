#!/usr/bin/env bash
# jq-fallback discipline (v2.26.16).
#
# The pattern `X=$(… jq …); if [ -z "$X" ]; then X=$(… python3 …); fi` conflates two
# different things: "jq is unavailable" and "the field is not in the payload". The
# fallback exists for the first. It fires on the second.
#
# Measured on adaptive-economy and context-advisor, which read
# `.context_window.used_percentage` — a field that is not part of the UserPromptSubmit
# payload at all, so it is ALWAYS absent. Both hooks were therefore *slower* when the
# field was missing (32.3ms) than when it was present (13.0ms), paying ~20ms for a
# python fork that could only ever return empty. context-advisor's very next line
# exits when the value is empty, so the fork bought literally nothing.
#
# The fix is `command -v jq` — a builtin, no fork. These assertions pin both halves:
# the fast path must not fork, and the fallback must still work without jq.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== jq Fallback Discipline Tests ==="

payload() {  # $1 = "with" | "without" the context_window field
  if [ "$1" = "with" ]; then
    printf '{"session_id":"p","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"x","context_window":{"used_percentage":91}}' "$REPO_DIR"
  else
    printf '{"session_id":"p","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"x"}' "$REPO_DIR"
  fi
}

for HOOK in adaptive-economy context-advisor; do
  begin_test "$HOOK: falls back on jq ABSENCE, not on an empty result"
  # The structural assertion. A ms threshold would be flaky on a loaded runner, and
  # the defect was a conflation, not slowness.
  if grep -q 'command -v jq' "$REPO_DIR/hooks/$HOOK.sh" \
     && ! grep -qE 'if \[ -z "\$PCT" \]; then' "$REPO_DIR/hooks/$HOOK.sh"; then
    pass
  else
    fail "$HOOK still forks python when jq merely returned empty"
  fi
done

begin_test "context-advisor: still produces its warning when jq IS available"
OUT=$(payload with | SUPERCHARGER_STATE="$(mktemp -d)" bash "$REPO_DIR/hooks/context-advisor.sh" 2>/dev/null)
printf '%s' "$OUT" | grep -q '91%' && pass || fail "no advisory emitted with the field present: $OUT"

begin_test "context-advisor: silent when the field is absent (the real payload shape)"
OUT=$(payload without | SUPERCHARGER_STATE="$(mktemp -d)" bash "$REPO_DIR/hooks/context-advisor.sh" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silence when context_window is absent: $OUT"

begin_test "context-advisor: python fallback still works when jq is genuinely missing"
# The half that must not regress. Without this, 'optimising' the fallback away
# entirely would pass every assertion above.
FAKE=$(mktemp -d)
for b in bash sh printf cat sed grep awk python3 date mkdir tr head tail wc cut sort uniq stat rm touch mv cp ln chmod ls expr test env git dirname basename; do
  ln -sf "$(command -v "$b")" "$FAKE/$b" 2>/dev/null
done
# Allocate the state dir BEFORE stripping PATH — `mktemp` is not in $FAKE, so doing
# it inline made the subshell print "mktemp: command not found" and hand the hook an
# empty SUPERCHARGER_STATE. The assertion still passed, for the wrong reason.
FAKE_STATE=$(mktemp -d); mkdir -p "$FAKE_STATE/scope"
if PATH="$FAKE" command -v jq >/dev/null 2>&1; then
  echo "    (skipped: jq still reachable in the stripped PATH)"
  pass
else
  ERRF="$FAKE_STATE/err"
  OUT=$(payload with | PATH="$FAKE" SUPERCHARGER_STATE="$FAKE_STATE" bash "$REPO_DIR/hooks/context-advisor.sh" 2>"$ERRF")
  if printf '%s' "$OUT" | grep -q '91%' && ! grep -q 'command not found' "$ERRF"; then
    pass
  else
    fail "fallback broken without jq: out=[$OUT] err=[$(cat "$ERRF")]"
  fi
fi
rm -rf "$FAKE" "$FAKE_STATE"

report
