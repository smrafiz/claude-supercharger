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
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

# v2.6.77: drain stdin BEFORE check_hook_disabled. Previously an early exit
# left CC writing into a closed pipe → SIGPIPE on stricter shells (macOS).
# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

check_hook_disabled "human-approval-gate" && exit 0

# The skip list is CONFIG state, so it starts empty and only .supercharger.json
# (or the namespaced override below) may fill it. Without this line an inherited
# environment variable seeded it: `SKIP_CATS` is a plausible name for someone's
# own shell variable, and exporting it silently switched off whole categories of
# a security gate. Every other switch here is SUPERCHARGER_*; this one was not.
SKIP_CATS=""

# v2.7.42 perf: this gate only ever acts on a fixed set of high-risk commands
# (SQL DDL, terraform/kubectl/helm, git reset --hard, publish, redis flush, dd/
# mkfs, docker prune, ...). If the raw payload contains NONE of their trigger
# keywords, exit BEFORE the python cwd-parse + 5-level parent-dir walk + config
# reads (~149ms measured) that previously ran on EVERY Bash call. One cheap grep
# vs 2-4 python forks. A keyword hit just proceeds to the precise checks below.
if ! printf '%s' "$_INPUT" | grep -qiE 'terraform|prisma|drizzle|drop|kubectl|reset[[:space:]]+--hard|branch[[:space:]]+-D|reflog|tag[[:space:]]+-d|publish|twine|gem[[:space:]]+push|flushall|flushdb|\.drop\(|docker|dd[[:space:]]+if=|mkfs|fdisk|parted|diskutil|helm|truncate|alter[[:space:]]+table'; then
  exit 0
fi

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
  # v2.6.36: walk from main worktree root if PROJECT_DIR is a linked worktree
  SEARCH_DIR=$(_resolve_project_root "$PROJECT_DIR")
  # v2.6.77: pass SEARCH_DIR via env var. Shell-interpolating it into a
  # python3 -c string broke on paths containing single quotes (`o'malley`)
  # — Python parse-error silently disabled the gate for that project.
  for _ in 1 2 3 4 5; do
    if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
      # ONE fork reads both keys. This was two python3 interpreters opening and
      # parsing the SAME file back to back — and python3 is the dearest fork this
      # hook makes (23.1ms measured on macOS, and this platform is the cheap one).
      # Line 1 = gate flag, line 2 = skip categories. Same shape as path-guard's
      # config read.
      _HAG_CFG=$(SC_CFG="$SEARCH_DIR/.supercharger.json" python3 -c "
import json, os
try:
    with open(os.environ['SC_CFG']) as f:
        d = json.load(f)
    print('1' if d.get('humanApprovalGate') else '')
    cats = d.get('humanApprovalGateSkip', [])
    print(','.join(c for c in cats if isinstance(c, str)))
except Exception:
    print(''); print('')
" 2>/dev/null || printf '\n\n')
      GATE_ENABLED=${_HAG_CFG%%$'\n'*}
      SKIP_CATS=${_HAG_CFG#*$'\n'}
      SKIP_CATS=${SKIP_CATS%%$'\n'*}
      break
    fi
    # Parameter expansion, not `dirname`: this loop forked up to FIVE times to do
    # string manipulation bash can do without leaving the process. Trailing
    # slashes are stripped first so `/a/b/` walks to `/a`, not to `/a/b`.
    while [ "${SEARCH_DIR%/}" != "$SEARCH_DIR" ] && [ "$SEARCH_DIR" != "/" ]; do
      SEARCH_DIR="${SEARCH_DIR%/}"
    done
    case "$SEARCH_DIR" in
      */*) PARENT="${SEARCH_DIR%/*}"; [ -z "$PARENT" ] && PARENT="/" ;;
      # A path with no slash: dirname answers "." and so must this, or a
      # single-component relative dir would stop the walk one directory early.
      .|"") PARENT="$SEARCH_DIR" ;;
      *)   PARENT="." ;;
    esac
    [ "$PARENT" = "$SEARCH_DIR" ] && break
    SEARCH_DIR="$PARENT"
  done
fi

# v2.6.83: high-risk subset is gated BY DEFAULT — even when humanApprovalGate
# is unset. These are the unrecoverable shapes with documented real-world
# incidents (terraform destroy, prisma migrate reset, drizzle-kit push --force,
# DROP DATABASE). Opt-out: set `humanApprovalGate: false` in .supercharger.json
# or `SUPERCHARGER_NO_HUMAN_GATE_DEFAULT=1` env var.
if [ -z "$GATE_ENABLED" ] && [ "${SUPERCHARGER_NO_HUMAN_GATE_DEFAULT:-0}" != "1" ]; then
  COMMAND_PEEK=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    ti = json.load(sys.stdin).get('tool_input', {})
    # v2.23.22: PowerShell payloads carry the body in .script/.code, not .command —
    # reading only .command made this gate a silent no-op on the PowerShell channel.
    print(ti.get('command') or ti.get('script') or ti.get('code') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  if printf '%s\n' "$COMMAND_PEEK" | grep -qiE '(terraform[[:space:]]+destroy|prisma[[:space:]]+migrate[[:space:]]+reset|drizzle-kit[[:space:]]+push[[:space:]]+([^&|;]*[[:space:]])?--force([[:space:]]|$)|drop[[:space:]]+database|kubectl[[:space:]]+delete[[:space:]]+namespace)'; then
    GATE_ENABLED="1"
  fi
fi

[ -z "$GATE_ENABLED" ] && exit 0

# ── Extract command ───────────────────────────────────────────────────────────
COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    ti = json.load(sys.stdin).get('tool_input', {})
    cmd = ti.get('command') or ti.get('script') or ti.get('code') or ''  # v2.23.22: PowerShell parity
    print(cmd)
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$COMMAND" ] && exit 0

# Normalize: collapse whitespace, lowercase for matching
CMD_NORM=$(printf '%s\n' "$COMMAND" | tr '[:upper:]' '[:lower:]' | tr -s ' \t' ' ' | sed 's/^ //; s/ $//')

# ── Pattern matching ──────────────────────────────────────────────────────────
# Config wins; the namespaced env var is the documented override.
SKIP_CATS="${SKIP_CATS:-${SUPERCHARGER_HUMAN_GATE_SKIP:-}}"
MATCH_REASON=""
MATCH_CAT=""

# Eight categories each ran TWO greps — one to test the skip list, one to match
# the command — so a gated command forked grep up to 16 times to do work bash
# does natively. Measured on the terraform payload: 24 forks, 187.9ms on macOS,
# and this is the cheap platform (Git Bash pays ~29ms just to start a process).
#
# `_hag_re` takes the pattern as an ARGUMENT and matches through an unquoted
# variable: in bash 3.2+ a quoted right-hand side of =~ is a literal string, not
# a regex, so `[[ $s =~ "$re" ]]` would silently stop matching anything. Both
# engines are POSIX ERE, so the patterns are unchanged — verified case by case
# against the grep implementation before this landed.
_hag_skipped() { case ",$SKIP_CATS," in *",$1,"*) return 0 ;; esac; return 1; }
_hag_re() { local _s="$1" _re="$2"; [[ $_s =~ $_re ]]; }

# SQL — DROP/TRUNCATE/ALTER TABLE DATABASE SCHEMA
if ! _hag_skipped sql; then
  if _hag_re "$CMD_NORM" '(drop[[:space:]]+(table|database|schema|index)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_]|alter[[:space:]]+table[[:space:]]+[a-z_]+[[:space:]]+drop)'; then
    MATCH_REASON="SQL destructive operation"
    MATCH_CAT="sql"
  fi
fi

# Migration reset — prisma/drizzle. v2.22.4: these are named in the default-enable
# list (line ~102) but had NO precise matcher, so the gate turned ON and then
# every category missed → the flagship "unrecoverable" commands were never
# actually blocked. Unanchored so a leading prefix can't dodge it.
if [ -z "$MATCH_REASON" ] && ! _hag_skipped migration; then
  if _hag_re "$CMD_NORM" '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[[:space:]][^&|;]*--force-reset|drizzle-kit[[:space:]]+push[[:space:]][^&|;]*--force)'; then
    MATCH_REASON="destructive database migration reset"
    MATCH_CAT="migration"
  fi
fi

# Git — reset --hard, branch -D, tag -d, reflog delete
if [ -z "$MATCH_REASON" ] && ! _hag_skipped git; then
  # Git flags are case-sensitive (-d safe vs -D force); match against original
  # COMMAND not lowercased CMD_NORM.
  if _hag_re "$COMMAND" '(^|[[:space:]&|;])git[[:space:]].*(reset[[:space:]]+--hard|branch[[:space:]]+-D[[:space:]]|tag[[:space:]]+-d[[:space:]]|reflog[[:space:]]+delete)'; then
    MATCH_REASON="destructive git operation"
    MATCH_CAT="git"
  fi
fi

# Infra — kubectl delete, terraform destroy, helm uninstall
if [ -z "$MATCH_REASON" ] && ! _hag_skipped infra; then
  if _hag_re "$CMD_NORM" '(^|[[:space:]&|;])(kubectl[[:space:]]+delete|terraform[[:space:]]+destroy|helm[[:space:]]+(uninstall|delete))'; then
    MATCH_REASON="infrastructure destructive operation"
    MATCH_CAT="infra"
  fi
fi

# Publish — npm publish, pip upload, cargo publish, docker push to prod
if [ -z "$MATCH_REASON" ] && ! _hag_skipped publish; then
  if _hag_re "$CMD_NORM" '(^|[[:space:]&|;])(npm[[:space:]]+publish|twine[[:space:]]+upload|cargo[[:space:]]+publish|gem[[:space:]]+push)'; then
    MATCH_REASON="package registry publish"
    MATCH_CAT="publish"
  fi
fi

# Database tools — redis FLUSHALL/FLUSHDB, mongo drop, psql DROP
if [ -z "$MATCH_REASON" ] && ! _hag_skipped db; then
  if _hag_re "$CMD_NORM" '(redis-cli[[:space:]]+(flushall|flushdb)|mongosh?[[:space:]].*\.drop\(\)|psql[[:space:]].*-c[[:space:]].*drop)'; then
    MATCH_REASON="database destructive operation"
    MATCH_CAT="db"
  fi
fi

# Docker — system prune, rm all containers, volume rm
if [ -z "$MATCH_REASON" ] && ! _hag_skipped docker; then
  if _hag_re "$CMD_NORM" '(^|[[:space:]&|;])docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+(rm|prune)|rm[[:space:]]+-f)'; then
    MATCH_REASON="Docker destructive operation"
    MATCH_CAT="docker"
  fi
fi

# Disk — dd, mkfs, fdisk, parted
if [ -z "$MATCH_REASON" ] && ! _hag_skipped disk; then
  if _hag_re "$CMD_NORM" '(^|[[:space:]&|;])(dd[[:space:]]+if=|mkfs\.|fdisk[[:space:]]|parted[[:space:]]|diskutil[[:space:]]+(erase|format|partition))'; then
    MATCH_REASON="disk operation"
    MATCH_CAT="disk"
  fi
fi

[ -z "$MATCH_REASON" ] && exit 0

# ── Pending-file gate ─────────────────────────────────────────────────────────
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR"

# Hash the command for a stable pending-file name.
#
# The CR strip is load-bearing. Windows python print() ends every line with
# CRLF, and $(...) removes the trailing newline but NOT the carriage return —
# so the hash carried one into the FILENAME below, where CR is illegal on
# Windows and the write simply fails. That leaves this gate unable to record
# that it already asked, which is the same mechanism that silenced
# tool-history-tracker. A digest can never legitimately contain a CR.
CMD_HASH=$(printf '%s' "$COMMAND" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:12])" 2>/dev/null || printf '%s' "$COMMAND" | cksum | cut -d' ' -f1)
CMD_HASH=${CMD_HASH//$'\r'/}
# 2.21.4: scope the pending-approval marker to THIS session. Keyed on the
# command hash alone, a second concurrent session (or another project) running
# the same high-risk command found session A's "already asked" marker, consumed
# it, and was let through WITHOUT its own user ever being prompted — a silent
# bypass of the approval gate. Suffix with the session id so each session must
# clear its own gate.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SID" ] && SID="nosession"
PENDING_FILE="$SCOPE_DIR/.gate-pending-${SID}-${CMD_HASH}"

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
