#!/usr/bin/env bash
# Claude Supercharger — Cloud CLI Destructive Guard
# Event: PreToolUse | Matcher: Bash
#
# Cross-channel parity with mcp-destructive-guard: that hook ASKS before a
# destructive infra op on an MCP provider server (mcp__aws__/gcloud/azure/k8s/…);
# the same operations run through the NATIVE CLI (`aws`, `gcloud`, `az`, `kubectl`,
# `helm`, `gsutil`, `doctl`, `flyctl`) hit the Bash channel instead, where safety.sh
# only covers cloud CREDENTIAL-theft / container-escape / RBAC — NOT bulk deletes.
# So `aws ec2 terminate-instances`, `aws rds delete-db-instance`, `az group delete`,
# `kubectl delete namespace`, `helm uninstall`, `gsutil rm -r`, `gcloud … delete`
# slipped through. This ASKS (user confirms) on those — matching the MCP channel.
# (terraform/tofu destroy is already blocked by safety.sh, so it is not covered here.)
# Advisory + fail-open; disable with SUPERCHARGER_CLOUD_CLI_GUARD=0.
# Disable: SUPERCHARGER_CLOUD_CLI_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_CLOUD_CLI_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Fast-path: no cloud CLI mentioned → nothing to do. Superset of every provider
# matched below, so this can never skip a real match.
case "$_INPUT" in
  *aws*|*gcloud*|*gsutil*|*kubectl*|*helm*|*doctl*|*flyctl*|*eksctl*|*'az '*|*'az\"'*|*azure*) : ;;
  # v2.29.28: IaC state tooling. Widened WITH the patterns below, never after --
  # a pattern added under a fast-path that cannot reach it is a silently inert
  # guard, which is exactly how tool-preferences shipped dead in v2.29.23.
  *terraform*|*tofu*|*terragrunt*) : ;;
  *) exit 0 ;;
esac

check_hook_disabled "cloud-cli-destructive-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# Destructive bulk-delete operations per provider. Each pattern targets an
# irreversible resource teardown; ordinary reads/list/describe do not match.
op=""
if   printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*s3[[:space:]]+(rm[^;&|]*--recursive|rb[^;&|]*--force)';                      then op="aws s3 bulk delete (rm --recursive / rb --force)"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*ec2[[:space:]]+terminate-instances';                                        then op="aws ec2 terminate-instances"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*rds[[:space:]]+delete-db-(instance|cluster)';                               then op="aws rds delete-db-instance/cluster"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*(dynamodb[[:space:]]+delete-table|cloudformation[[:space:]]+delete-stack|eks[[:space:]]+delete-cluster|ecr[[:space:]]+delete-repository|lambda[[:space:]]+delete-function|elasticache[[:space:]]+delete)'; then op="aws bulk resource delete"
elif printf '%s' "$CMD" | grep -Eq -- 'gcloud[^;&|]*projects[[:space:]]+delete';                                             then op="gcloud projects delete"
elif printf '%s' "$CMD" | grep -Eq -- 'gcloud[^;&|]*(compute|sql|container|storage|functions|run|redis|spanner)[^;&|]*[[:space:]]delete([[:space:]]|$)'; then op="gcloud resource delete"
elif printf '%s' "$CMD" | grep -Eq -- 'gsutil[[:space:]]+(rm[[:space:]]+-[rR]|rb)';                                          then op="gsutil bucket/recursive delete"
elif printf '%s' "$CMD" | grep -Eq -- '(^|[[:space:];&|])az[[:space:]]+(group|vm|aks|sql|webapp|storage)[^;&|]*[[:space:]]delete([[:space:]]|$)'; then op="az resource delete"
elif printf '%s' "$CMD" | grep -Eq -- 'kubectl[^;&|]*delete[^;&|]*(namespace|deployment|statefulset|daemonset|pvc|persistentvolume|--all([[:space:]]|$))'; then op="kubectl delete (namespace/workload/--all)"
elif printf '%s' "$CMD" | grep -Eq -- 'helm[[:space:]]+(uninstall|delete)[[:space:]]';                                       then op="helm uninstall/delete"
elif printf '%s' "$CMD" | grep -Eq -- '(^|[[:space:];&|])(doctl|flyctl|fly)[^;&|]*(delete|destroy)([[:space:]]|$)';          then op="doctl/flyctl delete/destroy"
# v2.29.28: found by diffing this guard against hamzazulfiqar2/Devops-architect.
# The existing arms key on "delete" and "terminate", but AWS spells destruction
# several other ways -- and none of the IaC state verbs were covered at all.
# KMS first: it is the worst item here. Deleting a key makes EVERY object
# encrypted under it permanently unreadable, and the blast radius is invisible
# from the command itself. ASK, not deny -- both KMS and Secrets Manager have a
# recovery window, so the honest tier is "confirm", not "never".
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*kms[[:space:]]+(schedule-key-deletion|disable-key)';       then op="aws kms key deletion/disable (every object encrypted with it becomes unreadable)"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*secretsmanager[[:space:]]+delete-secret';                  then op="aws secretsmanager delete-secret"
# Deliberately the specific calls, not a bare deregister-/purge-/batch-delete-
# prefix: `ecs deregister-task-definition` is routine in a normal deploy and a
# broad arm would fire on ordinary work. Precision over reach.
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*ec2[[:space:]]+deregister-image';                          then op="aws ec2 deregister-image (AMI destruction)"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*sqs[[:space:]]+purge-queue';                               then op="aws sqs purge-queue"
elif printf '%s' "$CMD" | grep -Eq -- 'aws[^;&|]*ecr[[:space:]]+batch-delete-image';                        then op="aws ecr batch-delete-image"
# IaC state. `terraform destroy` is already DENIED by human-approval-gate, so it is
# absent here on purpose; these are the verbs that mutate state directly and can
# orphan or destroy live resources without the plan ever showing it.
elif printf '%s' "$CMD" | grep -Eq -- '(terraform|tofu|opentofu|terragrunt)[[:space:]]+state[[:space:]]+(rm|mv)'; then op="terraform state rm/mv (orphans or destroys real resources)"
elif printf '%s' "$CMD" | grep -Eq -- '(terraform|tofu|opentofu|terragrunt)[[:space:]]+force-unlock';             then op="terraform force-unlock (causes the corruption locking prevents)"
elif printf '%s' "$CMD" | grep -Eq -- '(terraform|tofu|opentofu|terragrunt)[[:space:]]+(taint|untaint)';          then op="terraform taint/untaint (forces replacement on next apply)"
# drain only, NOT cordon: cordon just marks a node unschedulable and uncordon
# reverses it. drain EVICTS running pods -- without a PodDisruptionBudget that
# can take every replica down at once.
elif printf '%s' "$CMD" | grep -Eq -- 'kubectl[^;&|]*[[:space:]]drain([[:space:]]|$)';                       then op="kubectl drain (evicts running workloads)"
fi

[ -z "$op" ] && exit 0

reason="destructive cloud operation via the native CLI: ${op}. This tears down cloud infrastructure/data and is typically irreversible — the same op is confirmed on the MCP channel (mcp-destructive-guard), so it is confirmed here too. Verify the target account/project/cluster and that this is intended."
RSN=$(printf '%s' "$reason" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$reason")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] cloud-cli-destructive-guard: ASK on ${op}" >&2
exit 0
