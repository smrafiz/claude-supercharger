#!/usr/bin/env bash
# Claude Supercharger — False-positive triage for the block ledger (maintainer tool)
#
# Every guard fix this month started the same way: read scope/.blocked-commands
# by hand, find the blocks where the trigger was TEXT (a commit message, a grep
# pattern, heredoc code, a quoted string) rather than a command, then replay.
# This does the first pass mechanically. For each ledger entry from the Bash
# guards it:
#
#   1. recovers the full command from the local transcripts (the ledger keeps
#      400 masked characters), falling back to the ledger text;
#   2. re-runs today's guards (safety, git-safety, harness-tamper) on it:
#      allowed now = already fixed;
#   3. re-runs them with quoted strings and heredoc bodies blanked. Blocks that
#      disappear depended on text alone: the likely false positives. Arguments
#      that EXECUTE (sh -c, python -c, eval, ssh, interpreter heredocs) are left
#      intact, because blanking them hides a real command.
#
# Output is a ranked list per rule. It is a triage list, not a verdict: every
# "text-only" entry still needs a human read, then a replay of the fix against
# the full transcript corpus (docs/HOOK_AUTHORING.md).
#
# Runs the guards in a throwaway state dir, so it never writes to the real
# ledger or telemetry. Printed commands are masked with the shared secret
# patterns (hooks/lib-secret-patterns.sh).
#
# Usage: tools/fp-triage.sh [--ledger FILE] [--projects DIR] [--examples N]
set -euo pipefail
# The engine prints commands; a Windows console would default Python to cp1252.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.blocked-commands"
PROJECTS="$HOME/.claude/projects"
EXAMPLES=3
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="$2"; shift 2 ;;
    --projects) PROJECTS="$2"; shift 2 ;;
    --examples) EXAMPLES="$2"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "fp-triage: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -f "$LEDGER" ] || { echo "fp-triage: no ledger at $LEDGER" >&2; exit 1; }

# shellcheck source=hooks/lib-secret-patterns.sh
. "$REPO_DIR/hooks/lib-secret-patterns.sh"
PATTERNS=$(mktemp)
trap 'rm -f "$PATTERNS"' EXIT
printf '%s\n' "${SECRET_PATTERNS[@]}" '[A-Fa-f0-9]{32,}' > "$PATTERNS"

FPT_REPO="$REPO_DIR" FPT_LEDGER="$LEDGER" FPT_PROJECTS="$PROJECTS" FPT_EXAMPLES="$EXAMPLES" \
FPT_PATTERNS="$PATTERNS" python3 "$REPO_DIR/tools/fp-triage.py"
