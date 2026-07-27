#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/phantom-import-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Phantom Import Guard Tests ==="

W=$(mktemp -d); mkdir -p "$W/services" "$W/pkg"
printf 'export const send=1\n' > "$W/services/mailer.ts"
printf 'export const util=1\n' > "$W/util.ts"
mkdir -p "$W/components/Button"; printf 'export default 1\n' > "$W/components/Button/index.tsx"
printf 'x=1\n' > "$W/pkg/real.py"; : > "$W/pkg/__init__.py"

mkin() { FP="$2" C="$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"], "content": os.environ["C"]}, "session_id": "p"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" 2>/dev/null | \
    python3 -c "import json,sys;s=sys.stdin.read().strip();print('WARN' if s and json.loads(s).get('hookSpecificOutput',{}).get('additionalContext') else 'SILENT')"
}
n=0
check() { n=$((n+1)); mkin "$W/c$n" "$2" "$3"; begin_test "$1"; local g; g=$(verdict "$W/c$n"); [ "$g" = "$4" ] && pass || fail "expected $4 got $g"; }

# --- WARN: relative import that resolves to nothing ---
check "js wrong filename"   "$W/app.ts"     "import { send } from './services/email'"   WARN
check "js wrong depth"      "$W/app.ts"     "import x from '../util'"                   WARN
check "js require() phantom" "$W/app.js"    "const x = require('./nope')"              WARN
check "py missing module"   "$W/pkg/a.py"   "from .ghost import thing"                 WARN

# --- SILENT: resolves, or not a checkable relative import ---
check "js real file"        "$W/app.ts"     "import { send } from './services/mailer'"  SILENT
check "js real sibling"     "$W/app.ts"     "import x from './util'"                    SILENT
check "js dir index"        "$W/app.ts"     "import B from './components/Button'"       SILENT
check "js bare package"     "$W/app.ts"     "import React from 'react'"                 SILENT
check "js path alias"       "$W/app.ts"     "import x from '@/lib/foo'"                 SILENT
check "py real module"      "$W/pkg/a.py"   "from .real import x"                       SILENT
check "py stdlib import"    "$W/pkg/a.py"   "import os, sys"                            SILENT
check "non-code file"       "$W/notes.md"   "import { x } from './missing'"             SILENT

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_PHANTOM_IMPORT_GUARD=0 bash "$HOOK" < "$W/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$W"
report
