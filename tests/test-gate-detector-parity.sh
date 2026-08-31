#!/usr/bin/env bash
# safety.sh's _NEED_PY gate must stay a SUPERSET of safety-detect.py's patterns.
#
# safety.sh runs a cheap bash `case` gate and only forks python when it matches.
# Every pattern in safety-detect.py is therefore unreachable unless the gate lets
# the command through. The invariant is stated twice in comments
# (hooks/safety.sh:941 and :947) and NOTHING enforced it — it has drifted at
# least twice:
#
#   v2.7.14   patterns added to the detector, gate updated by hand
#   v2.29.37  gate found BELOW the detector: `.docker/config.json` and `pip.conf`
#             were in the detector and not the gate, so _NEED_PY never flipped.
#             "rules written, reviewed and shipped that could not fire."
#             Measured then: every reader allowed ~/.docker/config.json.
#
# Same two-gate trap that shipped tool-preferences inert in v2.29.23, that hid a
# PowerShell poll in v4.0.5, and that this project has now found four times. Two
# hand-maintained lists in two languages drift, and the drift is SILENT: nothing
# errors, the rule simply stops firing.
#
# Checked BEHAVIOURALLY, not by diffing a glob list against a regex: for every
# sensitive filename, if safety-detect.py flags it on its own then the full
# safety.sh must flag it too. If the detector says yes and the hook says nothing,
# the gate swallowed it.
#
# Technique borrowed from intutic's anomaly-taxonomy package, which has the same
# two-language problem and solves it the same way: "two hand-maintained lists
# drift. Drift here is silent... The proxy therefore parses this file at test
# time and fails its build on any divergence."
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DETECT="$REPO_DIR/hooks/safety-detect.py"
SAFETY="$REPO_DIR/hooks/safety.sh"

echo "=== gate / detector parity ==="

# Does the DETECTOR flag this path on its own?
_detector() { CMD="cat /home/u/$1" python3 "$DETECT" 2>/dev/null; }
# Does the WHOLE HOOK flag it (i.e. did the gate let it reach the detector)?
_hook() {
  local d; d=$(mktemp -d)
  printf '{"session_id":"gp","cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"cat /home/u/%s"}}' "$1" \
    | SUPERCHARGER_STATE="$d" SUPERCHARGER_NO_DEDUP=1 bash "$SAFETY" 2>/dev/null
  local rc=$?
  rm -rf "$d"
  [ "$rc" = 2 ] && echo deny
}

SWALLOWED=""
CHECKED=0
while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  case "$NAME" in \#*) continue ;; esac
  CHECKED=$((CHECKED + 1))
  if [ -n "$(_detector "$NAME")" ] && [ -z "$(_hook "$NAME")" ]; then
    SWALLOWED="$SWALLOWED $NAME"
  fi
done <<'NAMES'
.env
.envrc
.npmrc
.pypirc
.pgpass
.my.cnf
.authinfo
.netrc
.git-credentials
id_rsa
id_ed25519
id_ecdsa
id_dsa
server.pem
private.key
cert.crt
cert.cer
store.p12
store.pfx
key.ppk
terraform.tfvars
secrets.tokens.json
kubeconfig
.kube/config
.docker/config.json
pip.conf
.aws/credentials
vault.kdbx
release.keystore
.config/gh/hosts.yml
.claude.json
.codex/auth.json
.cursor/config.json
.cargo/credentials
.gem/credentials
credentials.toml
secrets.yaml
credentials.json
NAMES

begin_test "gate is a superset: every name the detector flags reaches it through safety.sh"
[ "$CHECKED" -ge 30 ] || fail "only $CHECKED names checked — the list did not load, refusing to pass vacuously"
[ -z "$SWALLOWED" ] && pass || fail "the gate swallows:$SWALLOWED (detector flags them, safety.sh does not)"

begin_test "the name list has not fallen behind the detector"
# The list above is hand-maintained, which makes it a THIRD list that can drift —
# a name added to safety-detect.py and not here is untested, and the test would
# report parity it never checked. This canary counts the literal filename tokens
# in the detector's pattern and fails when that grows, so the addition is noticed
# at the moment it happens rather than at the next incident.
#
# It does NOT hash the pattern: the source carries long explanatory comments, and
# a canary that fires on every comment edit gets pinned to whatever silences it.
PINNED=31
ACTUAL=$(python3 -c "
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'_SENSITIVE_NAME_RE\s*=\s*re\.compile\((.*?)\n\s*\)', src, re.S)
if not m:
    print('PARSE_FAIL'); raise SystemExit
body = re.sub(r'#[^\n]*', '', m.group(1))
print(len(set(re.findall(r'\\\\\.[A-Za-z][\w.-]*|\bid_[a-z0-9]+', body))))
" "$DETECT" 2>/dev/null)
case "$ACTUAL" in
  PARSE_FAIL|"") fail "could not read _SENSITIVE_NAME_RE — the canary cannot pass vacuously" ;;
  "$PINNED")     pass ;;
  *) if [ "$ACTUAL" -gt "$PINNED" ] 2>/dev/null; then
       fail "detector grew to $ACTUAL literal tokens (pinned $PINNED). Add any new filenames to the NAMES list above, then re-pin."
     else
       fail "detector shrank to $ACTUAL literal tokens (pinned $PINNED). If a pattern was removed deliberately, re-pin."
     fi ;;
esac

report
