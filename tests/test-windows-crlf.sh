#!/usr/bin/env bash
# Windows CRLF hardening (v2.9.3).
# Windows Python's print() writes \r\n; any hook that captures python output and
# turns it into a filename, key, or control-flow compare gets a stray \r on Git
# Bash — invisible to mac/Linux. A 3-subagent audit found 7 such hooks; each strips
# \r now. This suite (a) guards those strips against silent removal, cross-platform,
# and (b) functionally proves the highest-value fix (enforce-pkg-manager) actually
# blocks, which only works if PROJECT_DIR is \r-free. Runs in the windows-latest CI
# subset — on Git Bash it's the real regression proof; on mac/Linux it still passes.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Windows CRLF hardening (v2.9.3) ==="
export SUPERCHARGER_NO_DEDUP=1

# --- Regression guards: the \r-strip must remain in each fixed hook ---
# tool-history uses `tr -d '\r'`; the other six use bash-native `${VAR//$'\r'/}`.
_guard() {
  local hook="$REPO_DIR/hooks/$1" marker="$2"
  begin_test "crlf-guard: $1 strips python \\r"
  if [ ! -f "$hook" ]; then fail "hook missing: $1"; return; fi
  grep -qF "$marker" "$hook" && pass || fail "$1 no longer strips \\r (expected marker: $marker)"
}
_guard tool-history-tracker.sh    "tr -d '\\r'"
_guard enforce-pkg-manager.sh     "//\$'\\r'/"
_guard subagent-circuit-breaker.sh "//\$'\\r'/"
_guard quality-gate.sh            "//\$'\\r'/"
_guard cache-health.sh            "//\$'\\r'/"
_guard typecheck.sh               "//\$'\\r'/"
_guard file-watcher.sh            "//\$'\\r'/"

# --- Functional proof: enforce-pkg-manager blocks npm in a pnpm project ---
# The hook reads cwd from the JSON payload, builds PROJECT_DIR, and tests
# "$PROJECT_DIR/pnpm-lock.yaml". Before the \r fix, on Git Bash PROJECT_DIR ended
# in \r, that test failed, and enforcement silently no-op'd. Asserting a BLOCK
# (exit 2) here proves PROJECT_DIR is clean on whatever platform runs this.
HOOK="$REPO_DIR/hooks/enforce-pkg-manager.sh"

begin_test "crlf-func: enforce-pkg-manager blocks npm in a pnpm project (PROJECT_DIR clean)"
PROJ=$(mktemp -d)
: > "$PROJ/pnpm-lock.yaml"
INPUT=$(printf '{"tool_input":{"command":"npm install lodash"},"cwd":"%s"}' "$PROJ")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
EC=$?
rm -rf "$PROJ"
if [ "$EC" -eq 2 ] && printf '%s' "$OUT" | grep -qi "pnpm"; then pass
else fail "expected block (exit 2 + pnpm reason); got ec=$EC out=$(printf '%s' "$OUT" | tr '\n' '|')"; fi

# Negative control: no lockfile → must NOT block (proves the block above is real,
# not a blanket npm deny).
begin_test "crlf-func: enforce-pkg-manager allows npm when no lockfile present"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_input":{"command":"npm install lodash"},"cwd":"%s"}' "$PROJ")
printf '%s' "$INPUT" | bash "$HOOK" >/dev/null 2>&1
EC=$?
rm -rf "$PROJ"
[ "$EC" -eq 0 ] && pass || fail "expected allow (exit 0) with no lockfile, got $EC"

report
