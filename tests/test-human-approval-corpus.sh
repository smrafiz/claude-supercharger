#!/usr/bin/env bash
# Verdict corpus for human-approval-gate — 38 commands, one expected answer each.
#
# Written when the matchers moved off grep. Each of the eight categories ran TWO
# greps (one for the skip list, one to match), so a gated command forked grep up
# to 16 times to do work bash does natively — 21 forks and 74ms for a bare
# `docker ps` on macOS, and Git Bash pays ~29ms per process START. The swap to
# `[[ =~ ]]` was verified by running every line below through both the grep
# implementation and the new one and diffing the verdicts: 38 cases, 0
# mismatches.
#
# That differential is gone the moment the old version is no longer on disk.
# This file is what survives it: the verdicts themselves, pinned independently
# of how they are computed, so the NEXT refactor of this matcher has the same
# safety net rather than a promise that one once existed.
#
# The negatives are the load-bearing half. `echo "drop the ball"`, `git tag -d`
# with no argument, `docker ps`, `terraform plan` and `echo truncate` all pass
# the cheap pre-filter and must still come out allowed — a matcher that gates
# them is worse than no matcher, because a gate that cries wolf gets disabled.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/human-approval-gate.sh"

echo "=== human-approval-gate verdict corpus ==="

CORPUS_DIR=$(mktemp -d)
N=0

# command|expected-category  ("allow" = must not gate)
while IFS='|' read -r CMD WANT; do
  [ -z "$CMD" ] && continue
  N=$((N + 1))
  printf '%s' "$CMD" > "$CORPUS_DIR/cmd.txt"
  SC_CMD_FILE="$CORPUS_DIR/cmd.txt" SC_SID="c$N" python3 -c "
import json, os
print(json.dumps({'tool_name': 'Bash',
                  'tool_input': {'command': open(os.environ['SC_CMD_FILE']).read()},
                  'cwd': os.environ['PWD'],
                  'session_id': os.environ['SC_SID']}))" > "$CORPUS_DIR/pay.json" 2>/dev/null

  OUT=$(SUPERCHARGER_STATE="$CORPUS_DIR/s$N" SUPERCHARGER_HUMAN_GATE=1 \
        CLAUDE_CODE_SESSION_ID="c$N" bash "$HOOK" < "$CORPUS_DIR/pay.json" 2>/dev/null || true)

  if printf '%s' "$OUT" | grep -q '"permissionDecision"'; then
    GOT=$(printf '%s' "$OUT" | sed -n 's/.*\[\([a-z]*\)\].*/\1/p' | head -1)
  else
    GOT="allow"
  fi

  begin_test "gate: $CMD -> $WANT"
  [ "$GOT" = "$WANT" ] && pass || fail "expected '$WANT', got '$GOT'"
done <<'CORPUS'
DROP TABLE users|sql
psql -c "drop database app"|sql
truncate table sessions|sql
ALTER TABLE t DROP COLUMN c|sql
prisma migrate reset|migration
npx prisma db push --force-reset|migration
drizzle-kit push --force|migration
git reset --hard HEAD~1|git
git branch -D feature|git
git tag -d v1.0.0|git
git reflog delete|git
kubectl delete namespace prod|infra
terraform destroy|infra
helm uninstall myrelease|infra
npm publish|publish
twine upload dist/*|publish
gh pr merge 123|merge
gh pr merge 123 --admin --squash|merge
gh pr merge --merge feature-x|merge
gh api -X PUT repos/o/r/pulls/17/merge|merge
cd /tmp && gh pr merge 9|merge
gh pr view 123|allow
gh pr merge-queue status|allow
git merge feature-x|allow
gh pr list --search merge|allow
gh api repos/o/r/pulls/17|allow
cargo publish|publish
gem push mygem.gem|publish
redis-cli flushall|db
redis-cli FLUSHDB|db
mongosh --eval "db.users.drop()"|db
docker system prune|docker
docker volume rm data|docker
docker rm -f abc|docker
dd if=/dev/zero of=/dev/disk2|disk
mkfs.ext4 /dev/sdb1|disk
fdisk /dev/sda|disk
diskutil erase disk2|disk
git status|allow
npm install lodash|allow
ls -la|allow
echo "drop the ball"|allow
git tag -d|allow
docker ps|allow
kubectl get pods|allow
terraform plan|allow
npm run build|allow
echo truncate|allow
CORPUS

rm -rf "$CORPUS_DIR"

# --- the skip list is config state, not ambient environment -------------------
# Found while moving these matchers off grep, and it predates that change: the
# hook did `SKIP_CATS="${SKIP_CATS:-}"` with nothing initialising it, so an
# INHERITED environment variable seeded the skip list. `SKIP_CATS` is a plausible
# name for someone's own exported shell variable, and hitting it switched off
# whole categories of a security gate silently. Every other switch in this hook
# is SUPERCHARGER_*.
SK=$(mktemp -d)
printf '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"},"cwd":"%s","session_id":"sk1"}' "$SK" > "$SK/infra.json"

begin_test "an inherited bare SKIP_CATS cannot disable a category"
OUT_I=$(SUPERCHARGER_STATE="$SK/a" SUPERCHARGER_HUMAN_GATE=1 SKIP_CATS="infra" \
        CLAUDE_CODE_SESSION_ID=sk1 bash "$HOOK" < "$SK/infra.json" 2>/dev/null || true)
printf '%s' "$OUT_I" | grep -q '"permissionDecision"' && pass \
  || fail "a bare environment SKIP_CATS switched off the infra category"

begin_test "the namespaced override still works"
OUT_N=$(SUPERCHARGER_STATE="$SK/b" SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_HUMAN_GATE_SKIP="infra" \
        CLAUDE_CODE_SESSION_ID=sk2 bash "$HOOK" < "$SK/infra.json" 2>/dev/null || true)
printf '%s' "$OUT_N" | grep -q '"permissionDecision"' \
  && fail "SUPERCHARGER_HUMAN_GATE_SKIP did not suppress the category" || pass

begin_test "and it suppresses only the category named"
printf '{"tool_name":"Bash","tool_input":{"command":"docker system prune"},"cwd":"%s","session_id":"sk3"}' "$SK" > "$SK/docker.json"
OUT_D=$(SUPERCHARGER_STATE="$SK/c" SUPERCHARGER_HUMAN_GATE=1 SUPERCHARGER_HUMAN_GATE_SKIP="infra" \
        CLAUDE_CODE_SESSION_ID=sk3 bash "$HOOK" < "$SK/docker.json" 2>/dev/null || true)
printf '%s' "$OUT_D" | grep -q '"permissionDecision"' && pass \
  || fail "skipping infra also switched off docker"
rm -rf "$SK"

report
