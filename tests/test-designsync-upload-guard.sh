#!/usr/bin/env bash
# Claude Supercharger — DesignSync upload guard
#
# write_files uploads local files BY PATH: the tool reads them from disk itself,
# so per its own description the contents never enter the session. That makes
# this hook the only layer that can see those bytes — the output scanners, the
# commit guard and the artifact guard all work on text that passed through the
# conversation, and this never does.
#
# The load-bearing test is therefore the localPath one: a secret in a file that
# is referenced only by name.

set -uo pipefail
. "${BASH_SOURCE[0]%/*}/helpers.sh"

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$REPO_DIR/hooks/designsync-upload-guard.sh"
echo "=== DesignSync upload guard ==="

WORK=$(mktemp -d)
# The guard opens localPath from inside python, so the payload must carry a path
# NATIVE python can resolve. MSYS rewrites paths passed as env vars and plain
# arguments, but NOT string content inside a JSON payload - so an mktemp path
# reaches Windows python as /tmp/tmp.XXXX, open() throws, the guard fails open,
# and all three localPath assertions reported passthrough on the runner while
# passing on macOS. Same transport rule that produced the v2.27-2.29 Windows arc;
# native_path (cygpath -m) is the fix already in helpers.sh, and is a plain
# passthrough off Windows.
WORK_N=$(native_path "$WORK")
# An AWS-shaped key, assembled here rather than written as one literal: the
# credential guards block such a literal on a command line, and splicing it to
# dodge that check has hidden a real bug in this repo before.
printf 'const AWS_KEY = "AKIA%s";\n' "IOSFODNN7EXAMPLE" > "$WORK/leaky.js"
printf 'export const Button = () => null;\n' > "$WORK/clean.js"

_decide() {  # $1 = tool_input JSON -> decision or "passthrough"
  printf '{"tool_name":"DesignSync","tool_input":%s,"cwd":"%s"}' "$1" "$WORK_N" \
    | bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read().strip()
print('passthrough' if not t else json.loads(t)['hookSpecificOutput']['permissionDecision'])"
}

begin_test "a secret in a file uploaded BY PATH is denied"
# The whole point: these bytes never reach the session, so no other check exists.
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"localDir\":\"$WORK_N\",\"files\":[{\"path\":\"c/leaky.js\",\"localPath\":\"leaky.js\"}]}")
[ "$R" = "deny" ] && pass || fail "expected deny, got $R"

begin_test "a clean file uploaded by path is allowed"
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"localDir\":\"$WORK_N\",\"files\":[{\"path\":\"c/clean.js\",\"localPath\":\"clean.js\"}]}")
[ "$R" = "passthrough" ] && pass || fail "expected passthrough, got $R"

begin_test "an absolute localPath is resolved too"
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"files\":[{\"path\":\"c/x.js\",\"localPath\":\"$WORK_N/leaky.js\"}]}")
[ "$R" = "deny" ] && pass || fail "expected deny for absolute path, got $R"

begin_test "a secret in INLINE data is denied as well"
# Both shapes of the same call must agree on what counts as a secret.
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"files\":[{\"path\":\"c/i.js\",\"data\":\"const k='AKIAIOSFODNN7EXAMPLE';\"}]}")
[ "$R" = "deny" ] && pass || fail "expected deny for inline secret, got $R"

begin_test "the leaky file is found even when it is not the first entry"
# An early clean file must not short-circuit the scan.
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"localDir\":\"$WORK_N\",\"files\":[{\"path\":\"a\",\"localPath\":\"clean.js\"},{\"path\":\"b\",\"localPath\":\"leaky.js\"}]}")
[ "$R" = "deny" ] && pass || fail "expected deny, got $R"

begin_test "read methods send nothing and are untouched"
for m in list_projects get_project list_files get_file; do
  R=$(_decide "{\"method\":\"$m\",\"projectId\":\"p\"}")
  [ "$R" = "passthrough" ] || { fail "method $m should pass through, got $R"; break; }
done
[ "$R" = "passthrough" ] && pass

begin_test "finalize_plan is untouched — it moves no bytes"
R=$(_decide '{"method":"finalize_plan","projectId":"p","writes":["a/**"]}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough, got $R"

begin_test "a batch larger than the scan cap ASKS rather than passing silently"
# A clean verdict that only covered part of the batch would be a silent cap, and
# nothing downstream can check the remainder.
BIG=$(WORK="$WORK_N" python3 -c "
import json,os
w=os.environ['WORK']
print(json.dumps({'method':'write_files','planId':'p1','localDir':w,
                  'files':[{'path':'c/%d.js'%i,'localPath':'clean.js'} for i in range(200)]}))")
R=$(printf '{"tool_name":"DesignSync","tool_input":%s,"cwd":"%s"}' "$BIG" "$WORK_N" \
  | bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read().strip()
print('passthrough' if not t else json.loads(t)['hookSpecificOutput']['permissionDecision'])")
[ "$R" = "ask" ] && pass || fail "expected ask for an over-cap batch, got $R"

begin_test "a localPath that resolves nowhere is ASKED about, not skipped"
# v2.29.12: this used to pass through. Skipping a file we cannot locate is the
# same silent gap the >128 branch already refuses to take - the bytes never enter
# the session, so nothing downstream checks them either.
R=$(_decide "{\"method\":\"write_files\",\"planId\":\"p1\",\"localDir\":\"$WORK_N\",\"files\":[{\"path\":\"c/x.js\",\"localPath\":\"does-not-exist.js\"}]}")
[ "$R" = "ask" ] && pass || fail "expected ask, got $R"

begin_test "finalize_plan's localDir is remembered and used by a later write_files"
# write_files carries only a planId, so without this the relative localPath below
# resolves against cwd - a different directory - and the secret goes unseen.
SUB=$(mktemp -d); printf 'const K = "AKIA%s";\n' "IOSFODNN7EXAMPLE" > "$SUB/hidden.js"
SUB_N=$(native_path "$SUB")
SID="ds-memo-test"
printf '{"tool_name":"DesignSync","tool_input":{"method":"finalize_plan","projectId":"p","localDir":"%s","writes":["c/**"]},"cwd":"%s","session_id":"%s"}' "$SUB_N" "$WORK_N" "$SID" \
  | bash "$HOOK" >/dev/null 2>&1
R=$(printf '{"tool_name":"DesignSync","tool_input":{"method":"write_files","planId":"p1","files":[{"path":"c/h.js","localPath":"hidden.js"}]},"cwd":"%s","session_id":"%s"}' "$WORK_N" "$SID" \
  | bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read().strip()
print('passthrough' if not t else json.loads(t)['hookSpecificOutput']['permissionDecision'])")
rm -rf "$SUB"
[ "$R" = "deny" ] && pass || fail "expected deny via the remembered localDir, got $R"

begin_test "opt-out env var disables the guard"
R=$(printf '{"tool_name":"DesignSync","tool_input":{"method":"write_files","planId":"p","localDir":"%s","files":[{"path":"a","localPath":"leaky.js"}]},"cwd":"%s"}' "$WORK_N" "$WORK_N" \
  | SUPERCHARGER_DESIGNSYNC_GUARD=0 bash "$HOOK" 2>/dev/null)
[ -z "$R" ] && pass || fail "opt-out ignored: $R"

begin_test "an unparseable payload fails open"
R=$(printf 'write_files but not json' | bash "$HOOK" 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$R" ] && pass || fail "should be silent+0, got rc=$RC out=$R"

begin_test "registered on PreToolUse for DesignSync"
python3 - "$REPO_DIR" <<'PY' && pass || fail "not registered in hooks.json"
import json,re,sys,pathlib
d=json.loads((pathlib.Path(sys.argv[1])/"hooks/hooks.json").read_text())["hooks"]
ok=any('DesignSync' in [t.strip() for t in re.split(r'[|,]', g.get('matcher',''))]
       and any('designsync-upload-guard' in h.get('command','') for h in g.get('hooks',[]))
       for g in d.get('PreToolUse',[]))
sys.exit(0 if ok else 1)
PY

rm -rf "$WORK"
report
