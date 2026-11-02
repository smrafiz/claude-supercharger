#!/usr/bin/env bash
# 4.4.3: test-integrity-guard asks when an edit to ordinary code ADDS a comment that
# silences a type checker or linter (@ts-ignore, # noqa, //nolint ...). Counted as a
# delta, so removing or keeping an existing one stays quiet.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== Suppression guard ==="
R="$REPO_DIR"
edit() { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" '{session_id:"sp",tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
run() { # want payload name [env]
  begin_test "$3"
  local out g=ok
  out=$(printf '%s' "$2" | env HOME="$(mktemp -d)" ${4:-} bash "$R/hooks/test-integrity-guard.sh" 2>/dev/null)
  case "$out" in *'"ask"'*) g=ASK ;; esac
  [ "$g" = "$1" ] && pass || fail "want $1 got $g: $out"
}
run ASK "$(edit /p/src/a.ts 'const x: number = y;' '// @ts-ignore
const x: number = y;')" "ts-ignore added in .ts"
run ASK "$(edit /p/app/m.py 'import os' 'import os  # noqa: F401')" "noqa added in .py"
run ASK "$(edit /p/app/m.py 'x = f()' 'x = f()  # type: ignore')" "type: ignore added"
run ASK "$(edit /p/web/c.jsx 'foo()' '// eslint-disable-next-line
foo()')" "eslint-disable-next-line added"
run ASK "$(edit /p/x/m.go 'return err' 'return err //nolint')" "go nolint"
run ASK "$(edit /p/x/A.java 'void f(){}' '@SuppressWarnings(\"unchecked\") void f(){}')" "java SuppressWarnings"
run ASK "$(edit /p/x/lib.rs 'fn f(){}' '#[allow(dead_code)]
fn f(){}')" "rust allow"
run ok "$(edit /p/src/a.ts '// @ts-ignore
const x = y;' 'const x = y;')" "ts-ignore removed"
run ok "$(edit /p/src/a.ts '// @ts-ignore
const x = y;' '// @ts-ignore
const x = z;')" "existing ts-ignore kept"
run ok "$(edit /p/docs/notes.md 'a' 'use // @ts-ignore sparingly')" "markdown mentions it"
run ok "$(edit /p/src/a.ts 'a()' 'b()')" "ordinary edit"
run ok "$(edit /p/src/a.ts 'x' '// @ts-ignore
x')" "SUPERCHARGER_SUPPRESSION_GUARD=0 turns it off" "SUPERCHARGER_SUPPRESSION_GUARD=0"
report
