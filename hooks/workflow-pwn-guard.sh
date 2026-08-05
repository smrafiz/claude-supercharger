#!/usr/bin/env bash
# Claude Supercharger — GitHub Actions "pwn request" Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# A privileged workflow trigger (`pull_request_target` / `workflow_run`) runs with the
# BASE repo's GITHUB_TOKEN + secrets. If such a workflow then checks out the UNTRUSTED
# fork-PR head (`github.event.pull_request.head.sha`, `refs/pull/N/merge`, …) and runs
# it (npm ci, build, test), attacker PR code executes with those secrets — the classic
# "pwn request" supply-chain vector (the July-2026 AsyncAPI npm compromise; GitHub
# shipped an actions/checkout v7 default-block in 2026). An agent editing
# `.github/workflows/*.yml` can be nudged into adding this while "fixing CI".
#
# DENY the explicit opt-out `allow-unsafe-pr-checkout: true` (its only purpose is to
# re-enable the now-blocked unsafe checkout — never legitimate for an agent to add).
# ASK on the privileged-trigger + PR-head-checkout combination (rare-but-legit uses
# exist). Gated to workflow files; the trigger alone (labelers, comment-bots) does NOT
# fire — the untrusted-head reference must co-occur. Fail-open; disable with
# SUPERCHARGER_WORKFLOW_PWN_GUARD=0.
# Disable: SUPERCHARGER_WORKFLOW_PWN_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_WORKFLOW_PWN_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: a privileged-trigger / opt-out token, OR an untrusted-PR-head reference
# (an Edit may add only the checkout, with the trigger already on-disk — python then
# combines the two). Superset; precise judgement happens in python, workflow-path-gated.
case "$_INPUT" in
  *pull_request_target*|*workflow_run*|*allow-unsafe-pr-checkout*) : ;;
  *head.sha*|*head.ref*|*pull_request.head*|*refs/pull*) : ;;
  *) exit 0 ;;
esac
check_hook_disabled "workflow-pwn-guard" 2>/dev/null && exit 0
hook_profile_skip "workflow-pwn-guard" 2>/dev/null && exit 0

_WP_OUT=$(mktemp 2>/dev/null) || _WP_OUT="${TMPDIR:-/tmp}/wfpwn.$$"
HOOK_INPUT="$_INPUT" python3 > "$_WP_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ""
norm = path.replace("\\", "/")
# Only GitHub Actions workflow files.
if not re.search(r'\.github/workflows/[^/]+\.ya?ml$', norm):
    sys.exit(0)

# What's being added this write.
add = ti.get("content") or ti.get("new_string") or ""
if not add and isinstance(ti.get("edits"), list):
    add = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
if not add:
    sys.exit(0)

# For an Edit, the trigger and the checkout may live in different parts of the file —
# combine the current on-disk file with the additions to judge the RESULTING workflow.
combined = add
if os.path.isfile(path):
    try:
        with open(path, "r", errors="replace") as f:
            combined = f.read(256 * 1024) + "\n" + add
    except Exception:
        combined = add

# DENY: the explicit unsafe-checkout opt-out being written.
if re.search(r'allow-unsafe-pr-checkout\s*:\s*true', add, re.I):
    print("DENY|allow-unsafe-pr-checkout: true")
    sys.exit(0)

# ASK: privileged trigger AND a checkout of the untrusted PR head co-occur.
trigger = re.search(r'\b(pull_request_target|workflow_run)\b', combined)
pr_head = re.search(
    r'github\.event\.pull_request\.head|refs/pull/\d+/(?:head|merge)|\.head\.(?:sha|ref)\b',
    combined)
if trigger and pr_head:
    print("ASK|%s + checkout of the untrusted PR head" % trigger.group(1))
PYEOF
_RES=$(cat "$_WP_OUT" 2>/dev/null); rm -f "$_WP_OUT" 2>/dev/null
[ -z "$_RES" ] && exit 0

_VERDICT="${_RES%%|*}"
_LABEL="${_RES#*|}"

if [ "$_VERDICT" = "DENY" ]; then
  _MSG="Blocked: this workflow sets ${_LABEL} — it re-enables the untrusted fork-PR checkout that actions/checkout v7 blocks by default, so attacker PR code would run with the base repo's GITHUB_TOKEN + secrets (the 'pwn request' vector; 2026 AsyncAPI npm compromise class). Don't add this. If a maintainer truly needs it, they should set it deliberately, not an agent editing CI. (Disable: SUPERCHARGER_WORKFLOW_PWN_GUARD=0)"
  RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] workflow-pwn-guard: DENY allow-unsafe-pr-checkout" >&2
  exit 2
fi

_MSG="This workflow combines a privileged trigger (${_LABEL}). A pull_request_target/workflow_run job runs with the base repo's GITHUB_TOKEN + secrets, and checking out the untrusted fork-PR head then running it (npm ci/build/test) executes attacker code with those secrets — the 'pwn request' supply-chain vector. Confirm this is intended and the job does NOT expose secrets to PR-controlled code (or check out a trusted ref instead). (Disable: SUPERCHARGER_WORKFLOW_PWN_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] workflow-pwn-guard: ASK pwn-request workflow (${_LABEL})" >&2
exit 0
