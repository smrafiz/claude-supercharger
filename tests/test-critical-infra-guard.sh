#!/usr/bin/env bash
# Suite for the critical-infra write gate.
#   hooks/lib-critical-infra.sh    (shared path matcher — single source of truth)
#   hooks/critical-infra-guard.sh  (PreToolUse: force a confirm on CI/CD/container/migration/auth edits)
#   hooks/lib-smart-approve.sh     (must NOT auto-approve critical paths, even under autopilot)
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/critical-infra-guard.sh"

new_state() { local d; d=$(mktemp -d); mkdir -p "$d/scope"; echo "$d"; }
edit_json() { printf '{"tool_name":"Edit","cwd":"/proj","session_id":"%s","tool_input":{"file_path":%s}}' "${2:-sX}" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }
# echo the guard's stdout for a given file_path (+ optional session id), in state dir $1
guard_out() { SUPERCHARGER_STATE="$1" bash "$GUARD" <<<"$(edit_json "$2" "${3:-sX}")" 2>/dev/null; }

# ---- matcher: true positives ----
source "$REPO_DIR/hooks/lib-critical-infra.sh"
for p in ".github/workflows/ci.yml" "/abs/.github/workflows/deploy.yaml" ".gitlab-ci.yml" ".circleci/config.yml" \
         "Jenkinsfile" "Dockerfile" "Dockerfile.prod" "docker-compose.yml" "compose.yaml" "infra/main.tf" "prod.tfvars" \
         "migrations/001.sql" "app/db/migrate/002.rb" "alembic/versions/x.py" "prisma/schema.prisma" \
         "auth/login.ts" "src/authentication/i.js" "middleware/auth.js" "config/passport.js" "google.strategy.ts"; do
  begin_test "matcher: '$p' is critical-infra"
  is_critical_infra_path "$p" >/dev/null && pass || fail "expected match"
done

# ---- matcher: false-positive guards ----
for p in "src/author.js" "docs/authors.md" "README.md" "src/Button.tsx" "package.json" "authenticity.test.js" "src/oauth.md"; do
  begin_test "matcher: '$p' is NOT critical-infra"
  is_critical_infra_path "$p" >/dev/null && fail "false positive" || pass
done

# ---- guard: emits permissionDecision ask on a critical file ----
begin_test "guard: critical file → permissionDecision ask"
D=$(new_state)
guard_out "$D" ".github/workflows/ci.yml" | grep -q '"permissionDecision":"ask"' && pass || fail "no ask emitted"
rm -rf "$D"

# ---- guard: non-critical file is silent ----
begin_test "guard: non-critical file → no output"
D=$(new_state)
[ -z "$(guard_out "$D" "src/app.ts")" ] && pass || fail "unexpected output on plain file"
rm -rf "$D"

# ---- guard: asks once per file per session ----
begin_test "guard: second edit of same file/session is silent (ack)"
D=$(new_state)
guard_out "$D" "Dockerfile" sA >/dev/null
[ -z "$(guard_out "$D" "Dockerfile" sA)" ] && pass || fail "re-prompted an acked file"
rm -rf "$D"

begin_test "guard: same file in a DIFFERENT session still asks"
D=$(new_state)
guard_out "$D" "Dockerfile" sA >/dev/null
guard_out "$D" "Dockerfile" sB | grep -q '"permissionDecision":"ask"' && pass || fail "ack leaked across sessions"
rm -rf "$D"

# ---- autopilot override: critical paths never auto-approved ----
source "$REPO_DIR/hooks/lib-smart-approve.sh"
begin_test "autopilot: critical-infra edit is NOT auto-approved"
D=$(new_state); printf '%s' "$(( $(date +%s) + 9999 ))" > "$D/scope/.autopilot-until"
SUPERCHARGER_STATE="$D" smart_approve_verdict '{"session_id":"sX","tool_name":"Edit","tool_input":{"file_path":".github/workflows/ci.yml"}}' \
  && fail "auto-approved a critical file under autopilot" || pass
rm -rf "$D"

begin_test "autopilot: a normal in-project edit IS auto-approved (no regression)"
D=$(new_state); printf '%s' "$(( $(date +%s) + 9999 ))" > "$D/scope/.autopilot-until"
SUPERCHARGER_STATE="$D" smart_approve_verdict '{"session_id":"sX","tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' \
  && pass || fail "normal file not auto-approved under autopilot"
rm -rf "$D"

report
