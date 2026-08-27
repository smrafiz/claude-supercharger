#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/env-file-guard.sh"

echo "=== Env File Guard Tests ==="

run_input() {
  local input="$1"
  printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1
  return $?
}

begin_test "env-guard: blocks 'cat .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
[ "$?" = "2" ] && pass || fail "cat .env not blocked"

begin_test "env-guard: blocks 'vim .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"vim .env"}}'
[ "$?" = "2" ] && pass || fail "vim .env not blocked"

begin_test "env-guard: blocks 'grep KEY .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"grep API_KEY .env"}}'
[ "$?" = "2" ] && pass || fail "grep .env not blocked"

begin_test "env-guard: blocks 'cp .env elsewhere'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cp .env /tmp/backup"}}'
[ "$?" = "2" ] && pass || fail "cp .env not blocked"

begin_test "env-guard: allows 'cat .env.example'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}'
[ "$?" = "0" ] && pass || fail ".env.example incorrectly blocked"

begin_test "env-guard: allows 'cat .env.template'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env.template"}}'
[ "$?" = "0" ] && pass || fail ".env.template incorrectly blocked"

begin_test "env-guard: allows git commit mentioning .env"
run_input '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"update .env handling\""}}'
[ "$?" = "0" ] && pass || fail "git commit incorrectly blocked"

begin_test "env-guard: allows gh pr create mentioning .env"
run_input '{"tool_name":"Bash","tool_input":{"command":"gh pr create --body \"changed .env\""}}'
[ "$?" = "0" ] && pass || fail "gh pr create incorrectly blocked"

begin_test "env-guard: allows unrelated commands"
run_input '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
[ "$?" = "0" ] && pass || fail "ls incorrectly blocked"

begin_test "env-guard: blocks Read of .env"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env"}}'
[ "$?" = "2" ] && pass || fail "Read .env not blocked"

begin_test "env-guard: blocks Read of .env.local"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env.local"}}'
[ "$?" = "2" ] && pass || fail "Read .env.local not blocked"

begin_test "env-guard: allows Read of .env.example"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env.example"}}'
[ "$?" = "0" ] && pass || fail ".env.example Read incorrectly blocked"

begin_test "env-guard: allows Read of regular file"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/main.py"}}'
[ "$?" = "0" ] && pass || fail "regular file Read incorrectly blocked"

begin_test "env-guard: blocks redirect to .env (write)"
run_input '{"tool_name":"Bash","tool_input":{"command":"echo SECRET=foo > .env"}}'
[ "$?" = "2" ] && pass || fail "redirect to .env not blocked"

# v2.6.83: /proc and /sys reads — process-env exfil vector
begin_test "env-guard: blocks Read of /proc/self/environ (v2.6.83)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proc/self/environ"}}'
[ "$?" = "2" ] && pass || fail "/proc/self/environ Read not blocked"

begin_test "env-guard: blocks Read of /proc/<pid>/environ (v2.6.83)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proc/12345/environ"}}'
[ "$?" = "2" ] && pass || fail "/proc/<pid>/environ Read not blocked"

begin_test "env-guard: blocks Read of /sys/* (v2.6.83)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/sys/class/net/eth0/address"}}'
[ "$?" = "2" ] && pass || fail "/sys Read not blocked"

begin_test "env-guard: allows Read of unrelated absolute path"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/tmp/normal.txt"}}'
[ "$?" = "0" ] && pass || fail "regular /tmp Read incorrectly blocked"

# v2.8.9: Read-channel parity with the Bash-channel credential set. Reading these
# via the Read tool bypassed the guard (it only matched .env*).
begin_test "env-guard: blocks Read of SSH private key (v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}'
[ "$?" = "2" ] && pass || fail "Read of id_rsa not blocked"

begin_test "env-guard: blocks Read of *.pem (v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/server.pem"}}'
[ "$?" = "2" ] && pass || fail "Read of .pem not blocked"

begin_test "env-guard: blocks Read of .netrc (v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.netrc"}}'
[ "$?" = "2" ] && pass || fail "Read of .netrc not blocked"

begin_test "env-guard: blocks Read of ~/.aws/credentials (v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.aws/credentials"}}'
[ "$?" = "2" ] && pass || fail "Read of aws credentials not blocked"

begin_test "env-guard: blocks Read of .git-credentials (v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.git-credentials"}}'
[ "$?" = "2" ] && pass || fail "Read of .git-credentials not blocked"

begin_test "env-guard: allows Read of a normal source file (no false positive, v2.8.9)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/index.ts"}}'
[ "$?" = "0" ] && pass || fail "normal source Read wrongly blocked"

# v2.10.4: kubeconfig read parity — Bash channel blocked `cat kubeconfig` but the
# Read tool bypassed it (from adityaarakeri/claude-on-a-leash overlap audit).
begin_test "env-guard: blocks Read of ~/.kube/config (v2.10.4)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.kube/config"}}'
[ "$?" = "2" ] && pass || fail "Read of .kube/config not blocked"

begin_test "env-guard: blocks Read of bare kubeconfig (v2.10.4)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/home/u/kubeconfig"}}'
[ "$?" = "2" ] && pass || fail "Read of bare kubeconfig not blocked"

begin_test "env-guard: allows Read of kubeconfig.md doc (no false positive, v2.10.4)"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/docs/kubeconfig.md"}}'
[ "$?" = "0" ] && pass || fail "kubeconfig.md doc wrongly blocked"

# --- v2.29.37: credential files, verified on BOTH channels -------------------
# Three separate causes, all ending in "allowed", found by a matrix that tested
# Bash and Read in BOTH directions. An earlier one-directional probe reported 8
# gaps where there were 12.
#
#   DEAD RULES  .docker/config.json and pip.conf were in safety-detect.py's regex
#               but NOT in safety.sh's fast-path gate, so _NEED_PY never flipped
#               and the detector never ran -- written, reviewed, shipped and
#               unreachable. Same two-gate trap that shipped tool-preferences inert.
#   DRIFT       cargo/credentials.toml, secrets.yaml and credentials.json were
#               blocked on Bash and allowed on Read -- the opposite direction to
#               the docker/aws pair, which is why one-way probing missed them.
#   NOT KNOWN   gh hosts.yml, *.kdbx, *.keystore, and the agent configs.
#
# Generic basenames (hosts.yml, auth.json, config.json) are matched by PATH, never
# by basename: the secret is the LOCATION, and a basename rule would fire on every
# project's config.json.
for _f in "/home/u/.aws/credentials" "/home/u/.docker/config.json" \
          "/home/u/.config/gh/hosts.yml" "/home/u/.claude.json" \
          "/home/u/.codex/auth.json" "/home/u/.cursor/config.json" \
          "/proj/vault.kdbx" "/proj/server.keystore" "/proj/credentials.toml" \
          "/proj/secrets.yaml" "/proj/credentials.json" "/etc/pip.conf"; do
  begin_test "env-guard: Read blocks credential file $(basename "$_f")"
  run_input "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$_f\"}}"
  [ "$?" = "2" ] && pass || fail "Read allowed $_f"
done

# Ordinary project files carrying the same generic basenames must stay readable.
for _f in "/proj/src/config.json" "/proj/package.json" "/proj/tsconfig.json" \
          "/proj/docs/credentials-policy.md"; do
  begin_test "env-guard: Read allows ordinary file $(basename "$_f")"
  run_input "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$_f\"}}"
  [ "$?" = "0" ] && pass || fail "over-blocked $_f"
done

report
