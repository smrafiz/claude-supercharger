#!/usr/bin/env bash
# 4.4: environment variables that make a program load extra code ask before running.
# From gadievron/raptor's dangerous-env list (audited 2026-10-26); all were allowed.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== code-injection environment variables ==="

_v() {
  local p st out rc
  # stdin, not an env var: Git Bash rewrites /tmp/... in env values handed to Windows python
  p=$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":sys.stdin.read()}}))')
  st=$(mktemp -d)
  out=$(printf '%s' "$p" | SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/safety.sh" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) echo DENY ;; *'"permissionDecision":"ask"'*) echo ASK ;; *) echo ALLOW ;; esac
}
_case() { begin_test "injection env: $1 -> $3"; local g; g=$(_v "$2"); [ "$g" = "$3" ] && pass || fail "got $g for: $2"; }

_case "LD_PRELOAD prefix"        'LD_PRELOAD=/tmp/x.so ls'                           ASK
_case "export LD_PRELOAD"        'export LD_PRELOAD=/tmp/x.so'                       ASK
_case "LD_AUDIT"                 'LD_AUDIT=/tmp/a.so ls'                             ASK
_case "DYLD_INSERT_LIBRARIES"    'DYLD_INSERT_LIBRARIES=/tmp/x.dylib ls'             ASK
_case "BASH_ENV"                 'BASH_ENV=/tmp/x.sh bash -c true'                   ASK
_case "NODE_OPTIONS --require"   "NODE_OPTIONS='--require /tmp/x.js' npm test"       ASK
_case "export NODE_OPTIONS"      'export NODE_OPTIONS=--require=/tmp/x.js'           ASK
_case "PYTHONSTARTUP"            'PYTHONSTARTUP=/tmp/x.py python3'                   ASK
_case "PYTHONPATH in /tmp"       'PYTHONPATH=/tmp/evil python3 -m pytest'            ASK
_case "GCONV_PATH"               'GCONV_PATH=/tmp/g iconv -l'                        ASK
_case "SSLKEYLOGFILE"            'SSLKEYLOGFILE=/tmp/k.log curl https://example.com' ASK
_case "JAVA_TOOL_OPTIONS agent"  'JAVA_TOOL_OPTIONS=-javaagent:/tmp/a.jar java -version' ASK
_case "env wrapper"              'env -i LD_PRELOAD=/tmp/x.so ls'                    ASK
# must stay allowed
_case "PYTHONPATH=src"           'PYTHONPATH=src python3 -m pytest'                  ALLOW
_case "NODE_OPTIONS heap size"   'NODE_OPTIONS=--max-old-space-size=4096 npm run build' ALLOW
_case "export PATH"              'export PATH=$HOME/.local/bin:$PATH'                ALLOW
_case "commit message naming it" 'git commit -m "docs: explain why LD_PRELOAD=/x is asked"' ALLOW

report
