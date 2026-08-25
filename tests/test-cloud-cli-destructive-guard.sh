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

# --- v2.29.28: destruction verbs and IaC state ops this guard did not cover ----
# Found by diffing against hamzazulfiqar2/Devops-architect. The arms above key on
# "delete" and "terminate"; AWS spells destruction several other ways, and none of
# the IaC state verbs were covered at all. Probed against the real hook before the
# fix: all eleven returned allow.
#
# KMS is the worst of them -- deleting a key makes every object encrypted under it
# permanently unreadable, and nothing in the command shows that blast radius.
check "aws-kms-schedule-deletion" "aws kms schedule-key-deletion --key-id abc"        ASK
check "aws-kms-disable-key"       "aws kms disable-key --key-id abc"                  ASK
check "aws-secret-delete"         "aws secretsmanager delete-secret --secret-id s"    ASK
check "aws-ami-deregister"        "aws ec2 deregister-image --image-id ami-1"         ASK
check "aws-sqs-purge"             "aws sqs purge-queue --queue-url u"                 ASK
check "aws-ecr-batch-delete"      "aws ecr batch-delete-image --repository-name r"    ASK
check "tf-state-rm"               "terraform state rm aws_db_instance.prod"          ASK
check "tf-state-mv"               "terraform state mv a.b a.c"                       ASK
check "tf-force-unlock"           "terraform force-unlock -force 1234"               ASK
check "tf-taint"                  "terraform taint aws_instance.web"                 ASK
check "kubectl-drain"             "kubectl drain node-1"                              ASK

# --- the precision half: these must NOT fire -----------------------------------
# Every one of these is routine work. A guard that fires here is a guard people
# learn to click through, which costs exactly the signal it exists to give.
check "tf-plan-allowed"           "terraform plan -out=tfplan"                       SILENT
check "tf-state-list-allowed"     "terraform state list"                             SILENT
check "tf-show-allowed"           "terraform show"                                   SILENT
# cordon only marks a node unschedulable and uncordon reverses it; drain evicts.
check "kubectl-cordon-allowed"    "kubectl cordon node-1"                             SILENT
# Deliberately NOT a bare deregister- arm: this is a normal deploy step.
check "ecs-deregister-taskdef-allowed" "aws ecs deregister-task-definition --task-definition t" SILENT
check "aws-kms-describe-allowed"  "aws kms describe-key --key-id abc"                 SILENT

# --- accepted, and asserted so it stays a DECISION rather than a surprise -------
# The guard matches the verb wherever it appears, including inside a quoted string,
# so prose mentioning a destructive command asks too. That is deliberate: stripping
# quoted regions before matching (as the source repo does) is a BYPASS, because the
# verb itself can be quoted -- "rm" -rf / runs perfectly well. The new patterns must
# behave exactly like the pre-existing ones here, neither better nor worse.
check "quoted-prose-preexisting"  "echo 'aws s3 rm s3://b --recursive'"               ASK
check "quoted-prose-new-pattern"  "echo 'the runbook mentions terraform state rm'"   ASK

rm -rf "$TMP"
report
