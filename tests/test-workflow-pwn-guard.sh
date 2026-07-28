#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/workflow-pwn-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Workflow Pwn-Request Guard Tests ==="

TMP=$(mktemp -d)
mkin() { FP="$2" C="$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Write",
    "tool_input": {"file_path": os.environ["FP"], "content": os.environ["C"]}, "session_id": "wp"}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" > "$TMP/o" 2>/dev/null
  python3 -c "import json;s=open('$TMP/o').read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'ALLOW')"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n.json" "$2" "$3"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n.json"); [ "$g" = "$4" ] && pass || fail "expected $4 got $g"; }

WF="/p/.github/workflows/ci.yml"

# --- DENY: the explicit unsafe-checkout opt-out ---
check "allow-unsafe-pr-checkout true" "$WF" $'on: pull_request_target\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v7\n        with:\n          allow-unsafe-pr-checkout: true\n' DENY

# --- ASK: privileged trigger + untrusted PR-head checkout ---
check "pr_target + head.sha checkout" "$WF" $'on: pull_request_target\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - run: npm ci && npm test\n' ASK
check "workflow_run + refs/pull merge" "$WF" $'on:\n  workflow_run:\n    workflows: [ci]\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          ref: refs/pull/42/merge\n' ASK

# --- ALLOW: safe / non-matching ---
check "plain push workflow"        "$WF" $'on: push\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v4\n      - run: npm test\n' ALLOW
check "pr_target labeler (no head checkout)" "$WF" $'on: pull_request_target\njobs:\n  label:\n    steps:\n      - uses: actions/labeler@v5\n' ALLOW
check "safe pull_request + head.sha" "$WF" $'on: pull_request\njobs:\n  t:\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n' ALLOW
check "non-workflow file mentions it" "/p/docs/ci.md" $'Use pull_request_target with github.event.pull_request.head.sha carefully.\n' ALLOW
check "workflow dir but .txt"        "/p/.github/workflows/notes.txt" $'pull_request_target head.sha\n' ALLOW

# --- Edit adds checkout to an existing pull_request_target file (on-disk combine) ---
mkdir -p "$TMP/.github/workflows"
printf 'on: pull_request_target\njobs:\n  t:\n    steps:\n      - run: echo hi\n' > "$TMP/.github/workflows/x.yml"
begin_test "Edit adds PR-head checkout to existing pr_target file -> ASK"
FP="$TMP/.github/workflows/x.yml" python3 - "$TMP/edit.json" <<'PY'
import json, os, sys
open(sys.argv[1],"w").write(json.dumps({"tool_name":"Edit","tool_input":{"file_path":os.environ["FP"],
  "new_string":"      - uses: actions/checkout@v4\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n"},"session_id":"wp"}))
PY
g=$(verdict "$TMP/edit.json"); [ "$g" = "ASK" ] && pass || fail "expected ASK got $g"

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_WORKFLOW_PWN_GUARD=0 bash "$HOOK" < "$TMP/c1.json" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
