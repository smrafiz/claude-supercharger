#!/usr/bin/env bash
# 2026-09-13 — force-push / delete protection of the repo's RECORDED default
# branch, not just the hardcoded main|master|production|prod|release.
#
# From AhmadShayan/claude-code-guardrails, whose force-push guard reads
# refs/remotes/origin/HEAD so a repo that deploys from `develop`/`trunk` is
# protected. Ours added that as ADDITIVE and never fail-closed: on any failure to
# read the default, the hardcoded list still applies. This test builds a real
# repo whose origin default is `develop` and a second repo with no recorded
# default, and proves both directions.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== git default-branch protection ==="

HOOK="$REPO_DIR/hooks/git-safety.sh"
H=$(mktemp -d); export HOME="$H"; export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@t.t 2>/dev/null
git config --global user.name t 2>/dev/null
git config --global init.defaultBranch main 2>/dev/null

T=$(mktemp -d)
git init -q --bare "$T/origin.git"
git init -q "$T/work"
( cd "$T/work" \
  && git remote add origin "$T/origin.git" \
  && git checkout -q -b develop \
  && git commit -q --allow-empty -m init \
  && git push -q origin develop \
  && git remote set-head origin develop ) >/dev/null 2>&1

# A repo with a remote but NO recorded default (no set-head).
git init -q "$T/nodefault"
( cd "$T/nodefault" && git remote add origin "$T/origin.git" \
  && git commit -q --allow-empty -m init ) >/dev/null 2>&1

verdict() { # command  cwd  ->  BLOCK | rewrite | allow
  local js out rc
  js=$(CMD="$1" CWD="$2" python3 -c 'import json,os;print(json.dumps({"tool_name":"Bash","cwd":os.environ["CWD"],"tool_input":{"command":os.environ["CMD"]}}))')
  out=$(printf '%s' "$js" | bash "$HOOK" 2>/dev/null); rc=$?
  if [ "$rc" = 2 ]; then echo BLOCK
  elif printf '%s' "$out" | grep -q updatedInput; then echo rewrite
  else echo allow; fi
}

W="$T/work"; ND="$T/nodefault"

begin_test "force-push to the recorded default (develop) is blocked"
[ "$(verdict 'git push --force origin develop' "$W")" = BLOCK ] && pass || fail "develop not protected"

begin_test "native +refspec force-push to develop is blocked"
[ "$(verdict 'git push origin +develop' "$W")" = BLOCK ] && pass || fail "+develop not protected"

begin_test "force-push to a feature branch is still allowed (stripped)"
[ "$(verdict 'git push --force origin feature-x' "$W")" = rewrite ] && pass || fail "feature-x wrongly blocked"

begin_test "hardcoded main is still protected in a develop-default repo"
[ "$(verdict 'git push --force origin main' "$W")" = BLOCK ] && pass || fail "main protection regressed"

# The no-fail-closed contract: a repo with no recorded default must NOT start
# blocking ordinary feature-branch force-pushes.
begin_test "no recorded default: feature-branch force-push still allowed"
[ "$(verdict 'git push --force origin feature-y' "$ND")" = rewrite ] && pass || fail "fail-closed regression: feature-y blocked"

begin_test "no recorded default: hardcoded main still protected"
[ "$(verdict 'git push --force origin main' "$ND")" = BLOCK ] && pass || fail "main protection lost without a default"

rm -rf "$T" "$H"
report
