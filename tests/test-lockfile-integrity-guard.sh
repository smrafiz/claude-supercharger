#!/usr/bin/env bash
# Suite for hooks/lockfile-integrity-guard.sh — asks before hand-editing a
# machine-generated dependency lockfile (regenerate via the package manager).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/lockfile-integrity-guard.sh"

# run guard: $1=file_path $2=tool $3=session → stdout; fresh state dir each call
run_guard() {
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  printf '{"tool_name":"%s","cwd":"/proj","session_id":"%s","tool_input":{"file_path":"%s"}}' \
    "${2:-Edit}" "${3:-s1}" "$1" | { SUPERCHARGER_STATE="$st" bash "$GUARD" 2>/dev/null; }
  rm -rf "$st"
}
asks() { run_guard "$1" "${2:-Edit}" | grep -q '"permissionDecision":"ask"'; }

for lf in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum Gemfile.lock \
          composer.lock poetry.lock bun.lockb npm-shrinkwrap.json flake.lock; do
  begin_test "lockfile-guard: ASK on editing $lf"
  asks "$lf" && pass || fail "no ask on $lf"
done

begin_test "lockfile-guard: ASK on a nested lockfile path"
asks "packages/web/yarn.lock" && pass || fail "no ask on nested lockfile"

begin_test "lockfile-guard: Write to bun.lockb (binary) ASKS"
asks "bun.lockb" Write && pass || fail "no ask on bun.lockb write"

# --- must NOT fire on manifests or normal source ---
for ok in package.json Cargo.toml go.mod pyproject.toml src/app.ts README.md yarn.lock.md lockfile.js; do
  begin_test "lockfile-guard: silent on '$ok' (not a lockfile)"
  [ -z "$(run_guard "$ok")" ] && pass || fail "false ask on $ok"
done

begin_test "lockfile-guard: asks once per lockfile per session (2nd silent)"
ST=$(mktemp -d); mkdir -p "$ST/scope"
J='{"tool_name":"Edit","cwd":"/proj","session_id":"sDup","tool_input":{"file_path":"yarn.lock"}}'
first=$(printf '%s' "$J" | SUPERCHARGER_STATE="$ST" bash "$GUARD" 2>/dev/null)
second=$(printf '%s' "$J" | SUPERCHARGER_STATE="$ST" bash "$GUARD" 2>/dev/null)
echo "$first" | grep -q '"permissionDecision":"ask"' && [ -z "$second" ] && pass || fail "dedup failed (2nd=[$second])"
rm -rf "$ST"

begin_test "lockfile-guard: SUPERCHARGER_LOCKFILE_GUARD=0 disables it"
out=$(printf '{"tool_name":"Edit","cwd":"/proj","session_id":"sK","tool_input":{"file_path":"yarn.lock"}}' | SUPERCHARGER_LOCKFILE_GUARD=0 bash "$GUARD" 2>/dev/null)
[ -z "$out" ] && pass || fail "kill switch did not disable"

begin_test "lockfile-guard: corrective hint names the right package manager"
run_guard "pnpm-lock.yaml" | grep -q "pnpm install" && pass || fail "hint did not name pnpm"

report
