#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/config-validity-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Config Validity Guard Tests ==="

TMP=$(mktemp -d)
HAS_TOML=$(python3 -c "import tomllib" 2>/dev/null && echo 1 || echo 0)
HAS_YAML=$(python3 -c "import yaml" 2>/dev/null && echo 1 || echo 0)

# write CONTENT to a real file (hook parses the on-disk file), emit its JSON payload
mkfile() { printf '%s' "$3" > "$2"; FP="$2" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"]}, "session_id": "cv"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" | \
    python3 -c "import json,sys;s=sys.stdin.read().strip();print('WARN' if s and json.loads(s).get('hookSpecificOutput',{}).get('additionalContext') else 'SILENT')"
}
n=0
check() { n=$((n+1)); local f="$TMP/f$n$2"; mkfile "$TMP/c$n" "$f" "$3"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$4" ] && pass || fail "expected $4 got $g"; }

# --- WARN: genuinely broken structured config ---
check "unbalanced brace json"  ".json" '{"name":"x","version":"1.0"'                    WARN
check "stray token json"       ".json" '{"a": }'                                         WARN
check "trailing garbage json"  ".json" '{"a":1} oops'                                    WARN

# --- SILENT: valid, or JSONC, or empty ---
check "valid package.json"     ".json" '{"name":"x","dependencies":{"a":"1.0"}}'         SILENT
check "jsonc tsconfig"         ".json" '{
  // compiler opts
  "compilerOptions": { "strict": true, },
}'                                                                                        SILENT
check "empty json file"        ".json" ''                                                SILENT
check "non-config extension"   ".ts"   '{"a": }'                                         SILENT

# --- YAML (only asserted when pyyaml present) ---
if [ "$HAS_YAML" = 1 ]; then
  check "valid yaml"           ".yaml" 'name: x
list:
  - a
  - b'                                                                                    SILENT
  check "broken yaml indent"   ".yaml" 'name: x
  bad:
 wrong: indent'                                                                           WARN
fi

# --- TOML (only asserted when tomllib present, else skipped by the hook) ---
if [ "$HAS_TOML" = 1 ]; then
  check "valid toml"           ".toml" 'name = "x"
[table]
k = 1'                                                                                    SILENT
  check "broken toml"          ".toml" 'name = "x
[table'                                                                                   WARN
else
  check "toml skipped (no tomllib)" ".toml" 'name = "x'                                   SILENT
fi

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_CONFIG_VALIDITY_GUARD=0 bash "$HOOK" < "$TMP/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
