#!/usr/bin/env bash
# Generated coverage for CREDENTIAL FILE ACCESS across both channels (v2.29.39).
#
# Companion to test-command-prelude-matrix.sh, and here for the same reason: the
# hand-written cases encode the combinations someone thought of, and every defect
# in this area came from a combination nobody did.
#
# v2.29.37 closed twelve gaps here, from three causes that a one-directional probe
# could not have found together:
#
#   DEAD RULES  .docker/config.json and the pip config were present in
#               safety-detect.py's regex but absent from safety.sh's fast-path
#               gate, so _NEED_PY never flipped and the detector never ran. Rules
#               written, reviewed, shipped — and unreachable.
#   DRIFT       cargo/credentials.toml, secrets.yaml and credentials.json were
#               blocked on Bash and allowed on Read. The docker/aws pair drifted
#               the OTHER way. Testing one direction found 8 gaps; testing both
#               found 12.
#   NOT KNOWN   gh hosts.yml (a live OAuth token), *.kdbx, *.keystore, and the
#               agent config files.
#
# READERS matters as much as targets: a guard that stops `cat` but not `head` is
# not protection, and that is exactly how ~/.aws/credentials read as "covered".
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SAFETY="$REPO_DIR/hooks/safety.sh"
ENVGUARD="$REPO_DIR/hooks/env-file-guard.sh"

echo "=== Credential access matrix (target x reader x channel) ==="

# Assembled so this file never contains a literal the installed guard blocks,
# which would stop the runner reading its own fixtures.
PIPCONF="pip"".conf"

bash_blocked() { # reader, path -> BLOCK | allow
  local j
  j=$(CMD="$1 $2" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "cwd": "/tmp",
                  "tool_input": {"command": os.environ["CMD"]}}))')
  printf '%s' "$j" | bash "$SAFETY" >/dev/null 2>&1 && echo allow || echo BLOCK
}

read_blocked() { # path -> BLOCK | allow
  local j
  j=$(FP="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Read",
                  "tool_input": {"file_path": os.environ["FP"]}}))')
  printf '%s' "$j" | bash "$ENVGUARD" >/dev/null 2>&1 && echo allow || echo BLOCK
}

# Every ordinary way to read a file. Adding one extends coverage over every target.
READERS=("cat" "less" "head -20" "tail -5" "grep -i token" "od -c")

TARGETS=(
  "/home/u/.aws/credentials"
  "/home/u/.docker/config.json"
  "/home/u/.kube/config"
  "/home/u/.config/gcloud/credentials.db"
  "/home/u/.config/gh/hosts.yml"
  "/home/u/.ssh/id_rsa"
  "/home/u/.netrc"
  "/home/u/.npmrc"
  "/home/u/.pypirc"
  "/home/u/.git-credentials"
  "/home/u/.cargo/credentials"
  "/home/u/.cargo/credentials.toml"
  "/home/u/.gem/credentials"
  "/home/u/.claude.json"
  "/home/u/.codex/auth.json"
  "/home/u/.cursor/config.json"
  "/proj/vault.kdbx"
  "/proj/server.keystore"
  "/proj/secrets.yaml"
  "/proj/credentials.json"
)
TARGETS+=("/etc/$PIPCONF")

for _t in "${TARGETS[@]}"; do
  for _rd in "${READERS[@]}"; do
    begin_test "credential: '$_rd' cannot read $(basename "$_t")"
    [ "$(bash_blocked "$_rd" "$_t")" = BLOCK ] && pass \
      || fail "$_rd read $_t on the Bash channel"
  done
  begin_test "credential: Read tool cannot open $(basename "$_t")"
  [ "$(read_blocked "$_t")" = BLOCK ] && pass \
    || fail "Read tool opened $_t"
done

# --- precision --------------------------------------------------------------
# The generic-basename targets above (config.json, hosts.yml, auth.json) are
# matched by PATH. These carry the SAME basenames in ordinary locations and must
# stay readable, or the rule is a nag rather than a guard.
BENIGN=(
  "/proj/src/config.json"
  "/proj/package.json"
  "/proj/tsconfig.json"
  "/proj/.github/workflows/hosts.yml"
  "/proj/test/fixtures/auth.json"
  "/proj/docs/credentials-policy.md"
  "/proj/README.md"
)
for _b in "${BENIGN[@]}"; do
  begin_test "credential: ordinary file stays readable: ${_b#/proj/}"
  if [ "$(bash_blocked cat "$_b")" = allow ] && [ "$(read_blocked "$_b")" = allow ]; then
    pass
  else
    fail "over-blocked ordinary file $_b"
  fi
done

report
