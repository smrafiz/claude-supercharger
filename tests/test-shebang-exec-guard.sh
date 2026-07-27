#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/shebang-exec-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Shebang Exec Guard Tests ==="

TMP=$(mktemp -d)
# write CONTENT to a real file at MODE, emit its JSON payload (hook stats on-disk)
mkfile() { printf '%s' "$4" > "$2"; chmod "$3" "$2"; FP="$2" C="$4" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"], "content": os.environ["C"]}, "session_id": "sb"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" | \
    python3 -c "import json,sys;s=sys.stdin.read().strip();print('WARN' if s and json.loads(s).get('hookSpecificOutput',{}).get('additionalContext') else 'SILENT')"
}
n=0
check() { n=$((n+1)); mkfile "$TMP/c$n" "$TMP/f$n" "$3" "$4"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$2" ] && pass || fail "expected $2 got $g"; }

# arg order: name  expect  mode  content
check "shebang bash at 0644"   WARN    644 $'#!/usr/bin/env bash\necho hi\n'
check "shebang python at 0644" WARN    644 $'#!/usr/bin/env python3\nprint(1)\n'
check "shebang sh 0600"        WARN    600 $'#!/bin/sh\nls\n'

check "shebang already +x 0755" SILENT 755 $'#!/usr/bin/env bash\necho hi\n'
check "no shebang 0644"        SILENT  644 $'echo hi\nnot a script\n'
check "shebang not first line" SILENT  644 $'\n#!/bin/sh\necho hi\n'
check "shebang +x 0700"        SILENT  700 $'#!/bin/sh\nls\n'

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_SHEBANG_EXEC_GUARD=0 bash "$HOOK" < "$TMP/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
