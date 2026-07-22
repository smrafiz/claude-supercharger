#!/usr/bin/env bash
# Suite for the 2.21.1 phantom-deny sweep.
# When python3 is absent/crashes, a guard that captures VAR=$(python3 …) under
# `set -e` without `|| VAR=""` exits non-zero with EMPTY stderr, which Claude
# Code renders as a bogus "hook error: No stderr output" DENY on every edit.
# These hooks must instead FAIL OPEN (exit 0) — same contract as the 2.17.3
# safety.sh fix. jq and the rest of PATH stay intact; only python3 is broken.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Shim a python3 that exits non-zero, prepended so it shadows the real one.
FAKEBIN=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/python3"
chmod +x "$FAKEBIN/python3"
BROKEN_PATH="$FAKEBIN:$PATH"

PROJ=$(mktemp -d)

run_rc() { # <hook> <json>  → prints exit code, python3 broken
  PATH="$BROKEN_PATH" bash "$REPO_DIR/hooks/$1" >/dev/null 2>&1 <<<"$2"
  echo $?
}

WRITE_JSON="{\"tool_name\":\"Write\",\"cwd\":\"$PROJ\",\"tool_input\":{\"file_path\":\"$PROJ/src/app.ts\",\"content\":\"x\"}}"

begin_test "path-guard: python3 broken → fails OPEN (exit 0), no phantom-deny"
[ "$(run_rc path-guard.sh "$WRITE_JSON")" = 0 ] && pass || fail "path-guard aborted non-zero when python3 broke"

begin_test "memory-write-guard: python3 broken → fails OPEN (exit 0)"
[ "$(run_rc memory-write-guard.sh "$WRITE_JSON")" = 0 ] && pass || fail "memory-write-guard aborted non-zero when python3 broke"

BASH_JSON="{\"tool_name\":\"Bash\",\"cwd\":\"$PROJ\",\"tool_input\":{\"command\":\"ls -la\"}}"
begin_test "safety.sh: python3 broken → benign command still allowed (exit 0)"
[ "$(run_rc safety.sh "$BASH_JSON")" = 0 ] && pass || fail "safety.sh aborted non-zero when python3 broke"

# ---- positive control: with REAL python3 the deny path still denies ----
begin_test "path-guard: real python3 → write to /etc still denied (deny path intact)"
BAD_JSON="{\"tool_name\":\"Write\",\"cwd\":\"$PROJ\",\"tool_input\":{\"file_path\":\"/etc/passwd\",\"content\":\"x\"}}"
OUT=$(printf '%s' "$BAD_JSON" | bash "$REPO_DIR/hooks/path-guard.sh" 2>&1)
printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"' && pass || fail "deny path broke: $OUT"

rm -rf "$FAKEBIN" "$PROJ"
report
