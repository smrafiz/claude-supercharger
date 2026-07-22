#!/usr/bin/env bash
# Suite for v2.22.8 safety-detect.py aliased-os-shellout detection.
# `os.system` via an alias (`import os as o; o.system(`) or `__import__('os').system(`
# evaded the \bos\.system\b / bare-system( patterns (dot-prefixed).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/safety.sh"

jcmd() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
verdict() { local j; j=$(printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s}}' "$(jcmd "$1")"); bash "$H" <<<"$j" >/dev/null 2>&1 && echo ALLOW || echo BLOCK; }

# ---- aliased / indirect os shellout must be blocked ----
begin_test "safety-detect: 'import os as o; o.system(...)' is blocked"
[ "$(verdict "python3 -c \"import os as o; o.system('id')\"")" = BLOCK ] && pass || fail "aliased os.system evaded"
begin_test "safety-detect: '__import__(os).system(...)' is blocked"
[ "$(verdict "python3 -c \"__import__('os').system('id')\"")" = BLOCK ] && pass || fail "__import__ os.system evaded"
begin_test "safety-detect: getattr(os,'system')(...) is blocked"
[ "$(verdict "python3 -c \"import os; getattr(os,'system')('id')\"")" = BLOCK ] && pass || fail "getattr os.system evaded"

# ---- regression: direct forms still blocked ----
begin_test "safety-detect: direct 'import os; os.system(...)' still blocked"
[ "$(verdict "python3 -c \"import os; os.system('id')\"")" = BLOCK ] && pass || fail "direct os.system regressed"

# ---- regression: benign python one-liner allowed ----
begin_test "safety-detect: benign 'print(1+1)' allowed"
[ "$(verdict "python3 -c \"print(1+1)\"")" = ALLOW ] && pass || fail "benign python over-blocked"
begin_test "safety-detect: benign 'json.dumps' one-liner allowed"
[ "$(verdict "python3 -c \"import json; print(json.dumps({'a':1}))\"")" = ALLOW ] && pass || fail "benign json over-blocked"

report
