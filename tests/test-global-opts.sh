#!/usr/bin/env bash
# Global options before a subcommand (2026-11-07, applygate review).
#
# `terraform -chdir=envs/prod destroy` was allowed while `terraform destroy` was
# denied: every rule anchored on `<tool> <subcommand>`, and the global option sat
# in between. A sweep found 14 of 23 such forms weaker than the bare spelling.
# sc_hoist_global_opts_into (cmd-normalize.sh) appends a copy without them; it is
# wired into safety.sh (via normalize_cmd), human-approval-gate.sh and
# cloud-cli-destructive-guard.sh. Each case asserts the option form is judged at
# least as strictly as the bare form, across all three.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Global options before a subcommand ==="

decide() { # command -> deny | ask | allow (strictest over the three guards)
  local st h out best=allow n=0
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  for h in safety.sh human-approval-gate.sh cloud-cli-destructive-guard.sh; do
    n=$((n + 1))
    out=$(ST="$st" CMD="$1" SID="go$n$RANDOM" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "session_id": os.environ["SID"], "cwd": os.environ["ST"]}))' \
      | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$h" 2>&1)
    case $? in 2) best=deny ;; esac
    case "$out" in *'"deny"'*) best=deny ;; *'"ask"'*) [ "$best" = allow ] && best=ask ;; esac
  done
  rm -rf "$st"
  printf '%s' "$best"
}
rank() { case "$1" in deny) echo 2 ;; ask) echo 1 ;; *) echo 0 ;; esac; }

as_strict() { # bare-command option
  local tool="${1%% *}" rest="${1#* }" g a b
  g="$tool $2 $rest"
  begin_test "as strict as the bare form: $g"
  a=$(decide "$1"); b=$(decide "$g")
  if [ "$a" = allow ]; then fail "bare form '$1' is allowed: the case tests nothing"
  elif [ "$(rank "$b")" -ge "$(rank "$a")" ]; then pass
  else fail "'$g' -> $b, but '$1' -> $a"; fi
}
allowed() {
  begin_test "benign stays allowed: $1"
  local d; d=$(decide "$1")
  [ "$d" = allow ] && pass || fail "'$1' -> $d"
}

TF="terra""form"
as_strict "$TF destroy -auto-approve" "-chdir=envs/prod"
as_strict "$TF apply -destroy -auto-approve" "-chdir=envs/prod"
as_strict "$TF state rm aws_db_instance.main" "-chdir=envs/prod"
as_strict "tofu destroy" "-chdir=prod"
as_strict "terragrunt destroy" "--terragrunt-working-dir prod"
as_strict "kubectl delete namespace prod" "-n prod"
as_strict "kubectl delete namespace prod" "--context=prod"
as_strict "helm uninstall api" "-n prod"
as_strict "helm uninstall api" "--kube-context prod"
as_strict "az group delete -n rg" "--subscription prod"
as_strict "docker system prune -af" "--context prod"
as_strict "docker volume rm data" "-H ssh://prod"
as_strict "npm publish" "--prefix pkg"
as_strict "npm unpublish pkg --force" "--prefix pkg"
as_strict "aws s3 rb s3://b --force" "--profile prod"
as_strict "gcloud projects delete p" "--project prod"
as_strict "pulumi destroy --yes" "--cwd infra"
as_strict "pulumi destroy --yes" "-C infra"
as_strict "pulumi destroy --yes" "--non-interactive"
as_strict "pulumi stack rm prod" "--cwd infra"
as_strict "gh repo delete o/r --yes" "--repo o/r"
as_strict "gh release delete v1" "-R o/r"
as_strict "gh secret set X" "-R o/r"

begin_test "a destroy after cd and a global option is still seen"
[ "$(decide "cd infra && $TF -chdir=envs/prod destroy")" = deny ] && pass || fail "chained form not denied"

allowed "$TF -chdir=envs/prod plan"
allowed "tofu -chdir=prod validate"
allowed "kubectl -n prod get pods"
allowed "helm -n prod list"
allowed "docker --context prod ps"
allowed "npm --prefix pkg install"
allowed "aws --profile prod s3 ls"
allowed "pulumi --cwd infra preview"
allowed "gh -R o/r release list"

report
