#!/usr/bin/env bash
# Nothing in this repo may silently not run.
#
# Two failures in one week shared a shape: a discovery mechanism matched nothing
# and reported success.
#   - v2.24.5: every hook registered with the bare 'mcp__' matcher was inert.
#     An unmatched matcher fires nothing and errors nothing.
#   - fuzz-safety.sh: run.sh globs test-*.sh, so the fuzzer never ran. A test
#     that isn't collected is indistinguishable from a test that passes.
#
# Both were invisible because absence has no error path. This file gives absence
# one. Every hook script must be registered, a sourced lib, or explicitly listed
# below with a reason; likewise every script in tests/. An unexplained orphan
# fails the build with the filename.
#
# When this fails, the fix is usually to wire the file up — NOT to add it to an
# allowlist. Allowlisting is for files that genuinely should not be collected,
# and the reason string is the price of admission.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Orphan Registration Tests ==="

# --- Allowlists: filename<TAB>reason ------------------------------------------
# hooks/*.sh that are deliberately absent from hooks.json.
HOOK_ALLOW="
cmd-normalize.sh	sourced by safety/commit-guard/git-safety, not a hook itself
notify-helper.sh	sourced by elicitation-guard/notify-permission/notify-stop
detect-stack.sh	standalone CLI utility (tools/claude-check.sh, docs/HOOKS.md)
statusline.sh	registered as settings.json statusLine via lib/hooks.sh, not hooks.json
"

# tests/*.sh not matched by run.sh's test-*.sh glob.
TEST_ALLOW="
run.sh	the runner itself
helpers.sh	shared assertions, sourced by every test
perf-chain.sh	latency harness, invoked by test-perf-chain.sh
eval-agents.sh	opt-in agent evals, gated behind RUN_EVAL=true (costs real API tokens)
fuzz-safety.sh	NOT COLLECTED - see HOOK-LATENCY-PLAN; wire in once the runner is parallel
"

allow_reason() { printf '%s' "$1" | awk -F'\t' -v f="$2" '$1==f {print $2; found=1} END {exit !found}'; }

# --- A. Every hook script is registered, a lib, or allowlisted -----------------
REGISTERED=$(python3 - "$REPO_DIR" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1]+'/hooks/hooks.json')); h=d.get('hooks',d)
out=set()
for ev,v in h.items():
    for m in v:
        for e in m.get('hooks',[]):
            out.update(x+'.sh' for x in re.findall(r'([A-Za-z0-9_-]+)\.sh', json.dumps(e)))
print('\n'.join(sorted(out)))
PY
)

for path in "$REPO_DIR"/hooks/*.sh; do
  f=$(basename "$path")
  case "$f" in lib-*) continue ;; esac
  printf '%s\n' "$REGISTERED" | grep -qx "$f" && continue

  begin_test "hook not in hooks.json is allowlisted with a reason: $f"
  if reason=$(allow_reason "$HOOK_ALLOW" "$f"); then
    pass
  else
    fail "orphan — registered nowhere and not allowlisted. Wire it into hooks.json, or add it to HOOK_ALLOW with a reason."
  fi
done

# --- B. Every registered hook has a file on disk -------------------------------
# The reverse direction: a registration pointing at a deleted script also fires
# nothing, and is equally silent.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  begin_test "registered hook exists on disk: $f"
  [ -f "$REPO_DIR/hooks/$f" ] && pass || fail "hooks.json registers $f but hooks/$f is missing"
done <<< "$REGISTERED"

# --- C. Every tests/*.sh is collected by run.sh or allowlisted -----------------
# run.sh:20 globs test-*.sh. Anything else in tests/ never runs.
for path in "$REPO_DIR"/tests/*.sh; do
  f=$(basename "$path")
  case "$f" in test-*) continue ;; esac

  begin_test "uncollected test script is allowlisted with a reason: $f"
  if reason=$(allow_reason "$TEST_ALLOW" "$f"); then
    pass
  else
    fail "orphan — run.sh's test-*.sh glob will never collect it. Rename to test-*.sh, or add it to TEST_ALLOW with a reason."
  fi
done

# --- D. Allowlists don't outlive their entries ---------------------------------
# A stale allowlist entry is its own silent failure: it documents a file that no
# longer exists, and would mask a future file of the same name.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  f=$(printf '%s' "$line" | cut -f1)
  begin_test "HOOK_ALLOW entry still exists: $f"
  [ -f "$REPO_DIR/hooks/$f" ] && pass || fail "allowlisted hooks/$f no longer exists — drop the entry"
done <<< "$(printf '%s' "$HOOK_ALLOW" | sed '/^$/d')"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  f=$(printf '%s' "$line" | cut -f1)
  begin_test "TEST_ALLOW entry still exists: $f"
  [ -f "$REPO_DIR/tests/$f" ] && pass || fail "allowlisted tests/$f no longer exists — drop the entry"
done <<< "$(printf '%s' "$TEST_ALLOW" | sed '/^$/d')"

report
