#!/usr/bin/env bash
# Dependency preflight (v2.26.0)
#
# install.sh refuses without jq/python3 (install.sh:8, :25). A PLUGIN install has no
# install step, so nothing checked — while 103 of 138 hooks shell out to jq and 122 to
# python3. Missing them, the guards do not fail loudly; they degrade quietly, and a
# guard that cannot run is indistinguishable from a guard with nothing to do.
#
# The two properties that make this safe to ship on by default are that it stays
# SILENT on a healthy machine, and that it re-reports when the missing set CHANGES
# (a warn-once flag alone would hide a dependency lost later).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/dependency-preflight.sh"

# Run with a PATH containing only the tools we choose to expose.
run_with() { # $1=state dir, $2=fake bin dir ("" = real PATH), rest = env
  local st="$1" bin="$2"; shift 2
  local p="$PATH"
  [ -n "$bin" ] && p="$bin"
  env SUPERCHARGER_STATE="$st" PATH="$p" "$@" bash "$HOOK" </dev/null 2>&1 >/dev/null
}

# A bin dir exposing only the named tools (symlinked from the real ones).
mk_bin() {
  local dir="$1"; shift
  # The hook still needs ordinary coreutils to write its marker. Omitting them made
  # the "warns once" case fail for the wrong reason: mkdir was unavailable, so the
  # marker was never created and it warned every run.
  shim_tools "$dir" "$@" bash uname mkdir tr date rm ls cat sed grep
}

echo "=== Dependency Preflight Tests ==="

begin_test "silent when jq and python3 are both present"
ST=$(mktemp -d)
OUT=$(run_with "$ST" "")
[ -z "$OUT" ] && pass || fail "warned on a healthy machine: $OUT"
rm -rf "$ST"

begin_test "warns when jq is missing"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN" python3
OUT=$(run_with "$ST" "$BIN")
printf '%s' "$OUT" | grep -q 'jq' && pass || fail "no warning for missing jq: $OUT"
rm -rf "$ST" "$BIN"

begin_test "warns when python3 is missing"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN" jq
OUT=$(run_with "$ST" "$BIN")
printf '%s' "$OUT" | grep -q 'python3' && pass || fail "no warning for missing python3: $OUT"
rm -rf "$ST" "$BIN"

begin_test "warning names the impact, not just the tool"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN" python3
OUT=$(run_with "$ST" "$BIN")
printf '%s' "$OUT" | grep -qi 'degrade silently\|will not block' && pass || fail "warning does not say what breaks: $OUT"
rm -rf "$ST" "$BIN"

begin_test "warns ONCE for the same missing set (no per-session noise)"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN" python3
run_with "$ST" "$BIN" >/dev/null
OUT=$(run_with "$ST" "$BIN")
[ -z "$OUT" ] && pass || fail "warned twice for the same missing set"
rm -rf "$ST" "$BIN"

begin_test "re-warns when the missing set CHANGES (a lost dependency is new news)"
ST=$(mktemp -d)
BIN1=$(mktemp -d); mk_bin "$BIN1" python3          # jq missing
run_with "$ST" "$BIN1" >/dev/null
BIN2=$(mktemp -d); mk_bin "$BIN2" jq               # now python3 missing instead
OUT=$(run_with "$ST" "$BIN2")
printf '%s' "$OUT" | grep -q 'python3' && pass || fail "stayed silent after the missing set changed"
rm -rf "$ST" "$BIN1" "$BIN2"

begin_test "honors the /sc off kill-switch"
ST=$(mktemp -d); mkdir -p "$ST/scope"; : > "$ST/scope/.supercharger-disabled"
BIN=$(mktemp -d); mk_bin "$BIN" python3
OUT=$(run_with "$ST" "$BIN")
[ -z "$OUT" ] && pass || fail "warned while Supercharger was disabled: $OUT"
rm -rf "$ST" "$BIN"

begin_test "SUPERCHARGER_DEPENDENCY_PREFLIGHT=0 opts out"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN" python3
OUT=$(run_with "$ST" "$BIN" SUPERCHARGER_DEPENDENCY_PREFLIGHT=0)
[ -z "$OUT" ] && pass || fail "opt-out ignored: $OUT"
rm -rf "$ST" "$BIN"

begin_test "never blocks the session (always exits 0)"
ST=$(mktemp -d); BIN=$(mktemp -d); mk_bin "$BIN"   # both missing
env SUPERCHARGER_STATE="$ST" PATH="$BIN" bash "$HOOK" </dev/null >/dev/null 2>&1
[ $? -eq 0 ] && pass || fail "preflight exited non-zero — a warning must never break startup"
rm -rf "$ST" "$BIN"

report
