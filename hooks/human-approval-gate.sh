#!/usr/bin/env bash
# Claude Supercharger — Human Approval Gate
# Event: PreToolUse | Matcher: Bash,PowerShell
# Soft gate: pauses on high-risk commands and forces Claude to ask the user
# before retrying. Unlike safety.sh (permanent block), this allows through
# on retry — assuming Claude only retries after the user confirms.
#
# Opt-in (disabled by default). Enable via:
#   env var:            SUPERCHARGER_HUMAN_GATE=1
#   .supercharger.json: { "humanApprovalGate": true }
#
# How it works:
#   1st encounter: writes a pending file, returns deny with "ask user" message
#   2nd encounter: pending file exists → allows through (user was asked)
#
# Disable specific categories in .supercharger.json:
#   { "humanApprovalGate": true, "humanApprovalGateSkip": ["sql", "infra"] }

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "human-approval-gate" && exit 0

_INPUT=$(cat)

# ── Check if gate is enabled ─────────────────────────────────────────────────
GATE_ENABLED=""
if [ -n "${SUPERCHARGER_HUMAN_GATE:-}" ]; then
  GATE_ENABLED="1"
else
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  SEARCH_DIR="$PROJECT_DIR"
  for _ in 1 2 3 4 5; do
    if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
      GATE_ENABLED=$(python3 -c "
import json
try:
    with open('$SEARCH_DIR/.supercharger.json') as f:
        d = json.load(f)
    print('1' if d.get('humanApprovalGate') else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
      SKIP_CATS=$(python3 -c "
import json
try:
    with open('$SEARCH_DIR/.supercharger.json') as f:
        d = json.load(f)
    cats = d.get('humanApprovalGateSkip', [])
    print(','.join(cats))
except Exception:
    print('')
" 2>/dev/null || echo "")
      break
    fi
    PARENT=$(dirname "$SEARCH_DIR")
    [ "$PARENT" = "$SEARCH_DIR" ] && break
    SEARCH_DIR="$PARENT"
  done
fi

[ -z "$GATE_ENABLED" ] && exit 0

# ── Extract command ───────────────────────────────────────────────────────────
COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cmd = d.get('tool_input', {}).get('command', '')
    print(cmd)
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$COMMAND" ] && exit 0

# Normalize: collapse whitespace, lowercase for matching
CMD_NORM=$(printf '%s\n' "$COMMAND" | tr '[:upper:]' '[:lower:]' | tr -s ' \t' ' ' | sed 's/^ //; s/ $//')

# ── Pattern matching ──────────────────────────────────────────────────────────
SKIP_CATS="${SKIP_CATS:-}"
MATCH_REASON=""
MATCH_CAT=""

# SQL — DROP/TRUNCATE/ALTER TABLE DATABASE SCHEMA
if ! printf ',%s,' "$SKIP_CATS" | grep -q ',sql,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qiE '(drop[[:space:]]+(table|database|schema|index)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_]|alter[[:space:]]+table[[:space:]]+[a-z_]+[[:space:]]+drop)'; then
    MATCH_REASON="SQL destructive operation"
    MATCH_CAT="sql"
  fi
fi

# Git — reset --hard, branch -D, tag -d, reflog delete
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',git,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '^git[[:space:]].*(reset[[:space:]]+--hard|branch[[:space:]]+-D[[:space:]]|tag[[:space:]]+-d[[:space:]]|reflog[[:space:]]+delete)'; then
    MATCH_REASON="destructive git operation"
    MATCH_CAT="git"
  fi
fi

# Infra — kubectl delete, terraform destroy, helm uninstall
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',infra,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '^(kubectl[[:space:]]+delete|terraform[[:space:]]+destroy|helm[[:space:]]+(uninstall|delete))'; then
    MATCH_REASON="infrastructure destructive operation"
    MATCH_CAT="infra"
  fi
fi

# Publish — npm publish, pip upload, cargo publish, docker push to prod
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',publish,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '^(npm[[:space:]]+publish|twine[[:space:]]+upload|cargo[[:space:]]+publish|gem[[:space:]]+push)'; then
    MATCH_REASON="package registry publish"
    MATCH_CAT="publish"
  fi
fi

# Database tools — redis FLUSHALL/FLUSHDB, mongo drop, psql DROP
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',db,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '(redis-cli[[:space:]]+(flushall|flushdb)|mongosh?[[:space:]].*\.drop\(\)|psql[[:space:]].*-c[[:space:]].*drop)'; then
    MATCH_REASON="database destructive operation"
    MATCH_CAT="db"
  fi
fi

# Docker — system prune, rm all containers, volume rm
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',docker,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '^docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+(rm|prune)|rm[[:space:]]+-f)'; then
    MATCH_REASON="Docker destructive operation"
    MATCH_CAT="docker"
  fi
fi

# Disk — dd, mkfs, fdisk, parted
if [ -z "$MATCH_REASON" ] && ! printf ',%s,' "$SKIP_CATS" | grep -q ',disk,'; then
  if printf '%s\n' "$CMD_NORM" | grep -qE '^(dd[[:space:]]+if=|mkfs\.|fdisk[[:space:]]|parted[[:space:]]|diskutil[[:space:]]+(erase|format|partition))'; then
    MATCH_REASON="disk operation"
    MATCH_CAT="disk"
  fi
fi

[ -z "$MATCH_REASON" ] && exit 0

# ── Pending-file gate ─────────────────────────────────────────────────────────
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Hash the command for a stable pending-file name
CMD_HASH=$(printf '%s' "$COMMAND" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:12])" 2>/dev/null || printf '%s' "$COMMAND" | cksum | cut -d' ' -f1)
PENDING_FILE="$SCOPE_DIR/.gate-pending-${CMD_HASH}"

if [ -f "$PENDING_FILE" ]; then
  # Check TTL — pending files older than 1 hour are stale (session ended without retry)
  FILE_TS=$(tail -1 "$PENDING_FILE" 2>/dev/null || echo "0")
  NOW=$(date -u +%s 2>/dev/null || echo "0")
  AGE=$(( NOW - FILE_TS ))
  if [ "$AGE" -gt 3600 ]; then
    # Stale — delete and block again
    rm -f "$PENDING_FILE"
  else
    # Fresh — user was asked and Claude is retrying, allow through
    rm -f "$PENDING_FILE"
    exit 0
  fi
fi

# First encounter — create pending file and block
printf '%s\n%s\n' "$MATCH_CAT" "$(date -u +%s 2>/dev/null || echo 0)" > "$PENDING_FILE"

DISPLAY_CMD=$(printf '%s' "$COMMAND" | head -c 200)
MSG="Human approval required [${MATCH_CAT}]: ${MATCH_REASON}.

Command: ${DISPLAY_CMD}

Ask the user to confirm before retrying. If approved, retry the exact same command."

echo "[Supercharger] human-approval-gate: blocking — ${MATCH_REASON}" >&2
RSN=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
exit 2
