#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/package-source-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Package Source Guard Tests ==="

TMP=$(mktemp -d)

# Each check runs with a FRESH state dir + unique session so the ask-once-per-source
# dedup never suppresses an expected ASK. TOOL/paths assembled via env → no quoting pain.
mkin() { OLD="$3" NEW="$4" FP="$2" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({
    "tool_name": "Edit",
    "tool_input": {"file_path": os.environ["FP"],
                   "old_string": os.environ["OLD"],
                   "new_string": os.environ["NEW"]},
}))
PY
}
verdict() {
  local st; st=$(mktemp -d)
  SUPERCHARGER_STATE="$st" CLAUDE_CODE_SESSION_ID="sid-$RANDOM-$RANDOM" \
    bash "$HOOK" < "$1" > "$TMP/out" 2>/dev/null
  rm -rf "$st"
  python3 - "$TMP/out" <<'PY'
import sys, json
s = open(sys.argv[1]).read().strip()
print("ASK" if s and json.loads(s).get("hookSpecificOutput", {}).get("permissionDecision") == "ask" else "SILENT")
PY
}
check() { # name filepath old new expected
  mkin "$TMP/$1.json" "$2" "$3" "$4"
  begin_test "$1"
  local got; got=$(verdict "$TMP/$1.json")
  [ "$got" = "$5" ] && pass || fail "expected $5, got $got"
}

# --- should ASK: non-registry sources ---
check "npm tarball url"   /p/package.json '"lodash": "^4.0.0"'  '"lodash": "https://e.tld/l.tgz"'          ASK
check "npm git+ dep"      /p/package.json '"a": "^1.0.0"'       '"auth": "git+http://attacker.tld/a"'      ASK
check "npm github short"  /p/package.json '"a": "^1.0.0"'       '"pkg": "github:evil/pkg"'                  ASK
check "npm file dep"      /p/package.json '"a": "^1.0.0"'       '"pkg": "file:../../../etc"'                ASK
check "pyreq url dep"     /p/requirements.txt 'requests==2.0'   'lib @ https://e.tld/lib.whl'               ASK
check "pyreq git+"        /p/requirements.txt 'requests==2.0'   'lib @ git+https://e.tld/lib.git'           ASK
check "pyreq index-url"   /p/requirements.txt 'requests==2.0'   '--extra-index-url https://evil.tld/simple' ASK
check "cargo git source"  /p/Cargo.toml 'serde = "1.0"'         'serde = { git = "https://gh/x/serde" }'    ASK
check "cargo path source" /p/Cargo.toml 'serde = "1.0"'         'serde = { path = "../vendor/serde" }'      ASK
check "gemfile git"       /p/Gemfile 'gem "rails"'              'gem "rails", git: "https://e/rails"'       ASK
check "gemfile github"    /p/Gemfile 'gem "rails"'              'gem "rails", github: "evil/rails"'         ASK
check "go replace local"  /p/go.mod 'require x v1.0.0'          'replace x => ../local/x'                   ASK
check "pyproject git"     /p/pyproject.toml 'dep = "^1.0"'      'dep = { git = "https://e/dep" }'           ASK

# --- should stay SILENT: normal registry ranges ---
check "npm caret range"   /p/package.json '"a": "^1.0.0"'       '"react": "^18.2.0"'                        SILENT
check "npm exact pin"     /p/package.json '"a": "^1.0.0"'       '"react": "18.2.0"'                         SILENT
check "npm workspace"     /p/package.json '"a": "^1.0.0"'       '"ui": "workspace:*"'                       SILENT
check "pyreq pinned"      /p/requirements.txt 'requests==2.0'   'flask==3.0.0'                              SILENT
check "cargo version"     /p/Cargo.toml 'serde = "1.0"'         'tokio = "1.35"'                            SILENT
check "gemfile plain"     /p/Gemfile 'gem "rails"'              'gem "puma", "~> 6.0"'                       SILENT
check "non-manifest file" /p/README.md 'x'                      'see https://example.com/x.tgz for docs'    SILENT

# ask-once-per-source: second identical edit in the same session stays silent
SS=$(mktemp -d); SID="dedup-sid-42"
mkin "$TMP/dd.json" /p/package.json '"a": "^1.0.0"' '"x": "git+http://e/x"'
begin_test "asks the first time"
first=$(SUPERCHARGER_STATE="$SS" CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" < "$TMP/dd.json" 2>/dev/null)
[ -n "$first" ] && pass || fail "expected ASK on first occurrence"
begin_test "silent on the same source again (ask-once-per-session)"
second=$(SUPERCHARGER_STATE="$SS" CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" < "$TMP/dd.json" 2>/dev/null)
[ -z "$second" ] && pass || fail "expected SILENT on repeat, got: $second"
rm -rf "$SS"

# kill switch
begin_test "kill switch disables"
out=$(SUPERCHARGER_PACKAGE_SOURCE_GUARD=0 bash "$HOOK" < "$TMP/npm tarball url.json" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

# malformed json → fail-open
begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
