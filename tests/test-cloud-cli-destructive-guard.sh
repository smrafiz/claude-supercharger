#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cloud-cli-destructive-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Cloud CLI Destructive Guard Tests ==="

TMP=$(mktemp -d)
mkcmd() { CMD="$2" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}, "cwd": "/x"}))
PY
}
verdict() { bash "$HOOK" < "$1" 2>/dev/null | python3 -c '
import sys, json
s = sys.stdin.read().strip()
print("SILENT" if not s else json.loads(s).get("hookSpecificOutput", {}).get("permissionDecision", "?").upper())'
}
check() { mkcmd "$TMP/$1.json" "$2"; begin_test "$1"; local g; g=$(verdict "$TMP/$1.json"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- should ASK (destructive) ---
check "aws-s3-recursive-rm"   "aws s3 rm s3://b/ --recursive"                          ASK
check "aws-ec2-terminate"     "aws ec2 terminate-instances --instance-ids i-1"        ASK
check "aws-rds-delete"        "aws rds delete-db-instance --db-instance-identifier p" ASK
check "aws-cfn-delete-stack"  "aws cloudformation delete-stack --stack-name prod"     ASK
check "az-group-delete"       "az group delete --name prod-rg --yes"                  ASK
check "kubectl-delete-ns"     "kubectl delete namespace production"                   ASK
check "kubectl-delete-all"    "kubectl delete pods --all"                             ASK
check "helm-uninstall"        "helm uninstall myrelease"                              ASK
check "gsutil-recursive-rm"   "gsutil rm -r gs://b/p"                                 ASK
check "gcloud-instance-delete" "gcloud compute instances delete web-1"                ASK
check "gcloud-projects-delete" "gcloud projects delete my-proj"                       ASK
check "flyctl-destroy"        "flyctl destroy myapp"                                  ASK

# --- should PASS (read / list / describe / unrelated) ---
check "aws-s3-ls"             "aws s3 ls s3://b/"                                      SILENT
check "aws-ec2-describe"      "aws ec2 describe-instances"                            SILENT
check "kubectl-get"           "kubectl get pods"                                      SILENT
check "gcloud-list"           "gcloud compute instances list"                         SILENT
check "helm-list"             "helm list"                                             SILENT
check "aws-s3-cp"             "aws s3 cp file.txt s3://b/"                             SILENT
check "plain-command"         "git status"                                            SILENT

# --- kill switch + fail-open ---
begin_test "kill switch SUPERCHARGER_CLOUD_CLI_GUARD=0 suppresses"
mkcmd "$TMP/ks.json" "aws ec2 terminate-instances --instance-ids i-1"
OUT=$(SUPERCHARGER_CLOUD_CLI_GUARD=0 bash "$HOOK" < "$TMP/ks.json" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch should suppress"

begin_test "fail-open on malformed input"
printf 'not json' > "$TMP/bad.json"
OUT=$(bash "$HOOK" < "$TMP/bad.json" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass || fail "should fail-open silently (rc=$RC)"

begin_test "ignores non-Bash tools"
printf '{"tool_name":"Read","tool_input":{"file_path":"a"}}' > "$TMP/nb.json"
OUT=$(bash "$HOOK" < "$TMP/nb.json" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should only act on Bash"

rm -rf "$TMP"
report
