#!/usr/bin/env bash
# Fuzz-harness self-check (v2.26.4)
#
# tests/fuzz-safety.sh is deliberately excluded from the suite (slow +
# non-deterministic), so nothing kept its instrument honest. That matters more than
# for an ordinary test, because every way the harness can break produces the same
# output as a catastrophic security regression: a run reporting that ~100% of
# dangerous commands were allowed. `bash "$HOOK"` on a missing file exits 127, which
# is != 2, which counts as a false negative. Running a copy from outside the repo
# once reported 4055 bypasses for exactly that reason, and the number was believed
# before it was traced.
#
# The harness now proves it can see a block and an allow before measuring anything.
# These assertions pin that preflight — they abort before the corpus runs, so they
# cost nothing, and they are what keeps the excluded file from rotting silently.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

FUZZ="$REPO_DIR/tests/fuzz-safety.sh"

echo "=== Fuzz Harness Self-Check Tests ==="

# Each case runs the harness from a sandbox whose hooks/ we control, so the
# preflight trips and the ~4000-command corpus never starts.
sandbox() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/tests" "$dir/hooks"
  cp "$FUZZ" "$dir/tests/fuzz-safety.sh"
  printf '%s' "$dir"
}

begin_test "fuzz-safety: aborts when the hook is missing (does not report bypasses)"
SB=$(sandbox); rm -rf "$SB/hooks"
OUT=$(bash "$SB/tests/fuzz-safety.sh" 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'hook not found' && ! printf '%s' "$OUT" | grep -q 'BYPASSES'; then
  pass
else
  fail "expected abort rc=3 with no bypass report; got rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "fuzz-safety: aborts when the hook allows everything (would read as 100% bypass)"
SB=$(sandbox); printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/hooks/safety.sh"
OUT=$(bash "$SB/tests/fuzz-safety.sh" 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'self-check failed'; then
  pass
else
  fail "expected abort rc=3 on an always-allow hook; got rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "fuzz-safety: aborts when the hook blocks everything (would read as zero bypasses)"
SB=$(sandbox); printf '#!/usr/bin/env bash\nexit 2\n' > "$SB/hooks/safety.sh"
OUT=$(bash "$SB/tests/fuzz-safety.sh" 2>&1); RC=$?
if [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'ls -la'; then
  pass
else
  fail "expected abort rc=3 naming the allow probe; got rc=$RC out=$OUT"
fi
rm -rf "$SB"

begin_test "fuzz-safety: never writes to live Supercharger state"
# The harness fires thousands of real attack strings through the real hook, and
# safety.sh appends every block to $SUPERCHARGER_STATE/scope/.blocked-commands —
# a 500-line ring buffer that feeds learn-from-blocks.sh and the [BLOCKS] banner
# injected into every session. One unisolated run evicted the user's entire
# genuine block history and replaced it with synthetic attacks (530 of 533
# entries). A diagnostic must not write to the thing it diagnoses.
#
# Discriminating by construction: the stub hook writes into whatever
# SUPERCHARGER_STATE it is handed, exactly as safety.sh does. If the harness stops
# isolating, that write lands in the sentinel and this fails. The stub exits 0 on
# everything, so the preflight aborts after two probes — no corpus, no minutes.
SB=$(sandbox)
cat > "$SB/hooks/safety.sh" <<'EOS'
#!/usr/bin/env bash
mkdir -p "$SUPERCHARGER_STATE/scope" 2>/dev/null || true
echo "block" >> "$SUPERCHARGER_STATE/scope/.blocked-commands" 2>/dev/null || true
exit 0
EOS
SENTINEL=$(mktemp -d); mkdir -p "$SENTINEL/scope"
printf 'pre-existing-real-entry\n' > "$SENTINEL/scope/.blocked-commands"
SUPERCHARGER_STATE="$SENTINEL" bash "$SB/tests/fuzz-safety.sh" >/dev/null 2>&1
LIVE=$(wc -l < "$SENTINEL/scope/.blocked-commands" | tr -d ' ')
if [ "$LIVE" = "1" ]; then
  pass
else
  fail "harness wrote to live state: sentinel went 1 -> $LIVE lines"
fi
rm -rf "$SB" "$SENTINEL"

begin_test "fuzz-safety: the real hook passes the preflight (probes still classify correctly)"
# Guards the guard the other way: if safety.sh ever stopped blocking `rm -rf /` or
# started blocking `ls -la`, the three assertions above would still pass while the
# harness became unrunnable. Runs the two probes directly — not the corpus.
HOOK="$REPO_DIR/hooks/safety.sh"
probe() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]},'cwd':'/tmp'}))" "$1" \
    | bash "$HOOK" >/dev/null 2>&1; echo $?
}
B=$(probe "rm -rf /"); A=$(probe "ls -la")
if [ "$B" = "2" ] && [ "$A" != "2" ]; then
  pass
else
  fail "preflight probes misclassify: 'rm -rf /' exit=$B (want 2), 'ls -la' exit=$A (want not-2)"
fi

report
