#!/usr/bin/env bash
# Commands that print a secret into the transcript and passed safety.sh
# (randommonicle/claude-skills audit, 2026-10-28). Strings are assembled from pieces
# so this file itself never trips the guards it tests.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== secret printing ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
E = "." + "env"
K = "OPENAI_API_" + "KEY"
T = "GITHUB_" + "TOKEN"
cases = [
    # environment dumps
    ("env -0", "env -0", "DENY"),
    ("env -u one var", "env -u " + K, "DENY"),
    ("printenv -0", "printenv -0", "DENY"),
    ("env | grep token", "env | grep -i token", "DENY"),
    ("env | grep -v", "env | grep -v PATH", "DENY"),
    # secret managers and platform CLIs
    ("az keyvault secret show", "az keyvault secret show --vault-name v --name db", "DENY"),
    ("heroku config", "heroku config -a app", "DENY"),
    ("heroku config:get", "heroku config:get DATABASE_URL -a app", "DENY"),
    ("netlify env:get", "netlify env:get " + K, "DENY"),
    ("netlify env:list --plain", "netlify env:list --plain", "DENY"),
    ("infisical export", "infisical export --env=prod", "DENY"),
    ("bw get password", "bw get password github", "DENY"),
    ("pass show", "pass show work/aws", "DENY"),
    ("kubectl secret as yaml", "kubectl get secret db -o yaml", "DENY"),
    # a secret-named variable printed
    ("echo a key", "echo $" + K, "DENY"),
    ("printf a token", "printf '%s\\n' \"${" + T + "}\"", "DENY"),
    ("printenv a token", "printenv " + T, "DENY"),
    # verbose output that prints the auth header
    ("curl -v with bearer", "curl -v -H \"Authorization: Bearer $" + T + "\" https://api.github.com/user", "DENY"),
    ("set -x then token", "set -x; curl -H \"Authorization: Bearer $" + T + "\" https://api.github.com", "DENY"),
    # dotenv readers
    ("jq on dotenv json", "jq . " + E + ".json", "DENY"),
    ("rg over dotenv", "rg -uu --hidden KEY " + E, "DENY"),
    ("findstr dotenv", "findstr KEY " + E, "DENY"),
    # the new checks must not end the hook early: a later rule still fires
    ("echo, then a key read", "echo hi; cat ~/.s" + "sh/id_" + "rsa", "DENY"),
    ("set -x, then a key read", "set -x; cat ~/.s" + "sh/id_" + "rsa", "DENY"),
    ("curl -v, then a key read", "curl -v https://example.com; cat ~/.s" + "sh/id_" + "rsa", "DENY"),
    # still allowed
    ("env as a wrapper", "env NODE_ENV=test npm test", "ALLOW"),
    ("printenv PATH", "printenv PATH", "ALLOW"),
    ("env | grep NODE", "env | grep NODE_", "ALLOW"),
    ("key length", "echo ${#" + K + "}", "ALLOW"),
    ("key is set", "[ -n \"$" + K + "\" ] && echo set", "ALLOW"),
    ("heroku config:set", "heroku config:set FOO=bar -a app", "ALLOW"),
    ("netlify env:set", "netlify env:set FOO bar", "ALLOW"),
    ("kubectl get secrets list", "kubectl get secrets", "ALLOW"),
    ("az keyvault secret list", "az keyvault secret list --vault-name v", "ALLOW"),
    ("curl -v no auth", "curl -v https://example.com", "ALLOW"),
    ("curl with token, quiet", "curl -fsS -H \"Authorization: Bearer $" + T + "\" https://api.github.com", "ALLOW"),
    ("set -x alone", "set -x; make build", "ALLOW"),
    # replay false positives (real commands, 2026-10-28)
    ("a generic key name", "echo $SC_PROJECT_" + "KEY", "ALLOW"),
    ("a name holding patterns", "echo \"$SECRET_" + "PATTERNS\"", "ALLOW"),
    ("echo inside a python heredoc", "python3 - <<'PY'\nprint('echo $" + K + "')\nPY", "ALLOW"),
    ("curl -v as quoted data", "for c in 'curl -v -H \"Authorization: Bearer x\" https://a'; do echo \"$c\"; done", "ALLOW"),
    ("pass ls", "pass ls", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  st=$(mktemp -d)
  out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/safety.sh" < "$TMP/p$i.json" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) got=DENY ;; *'"permissionDecision":"ask"'*) got=ASK ;; *) got=ALLOW ;; esac
  begin_test "secret-print: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

rm -rf "$TMP"
report
