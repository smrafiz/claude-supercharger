#!/usr/bin/env bash
# Hooks must not reintroduce avoidable forks on the hot path (v2.26.35)
#
# 18 blocking hooks fire on every Bash tool call, so a fork added to one hook is
# paid ~18 times per tool call and hundreds of times per session. Measured on an
# M-series mac:
#
#   bash process start   3.2 ms   <- irreducible, one process per hook
#   /bin/cat             2.2 ms
#   grep                 2.4 ms
#   jq                   3.0 ms
#   python3             20.6 ms   <- never on a common path
#
# `_INPUT=$(cat)` forked /bin/cat in 115 hooks. Removing it took the PreToolUse
# chain from 130ms to 93ms per Bash call. These assertions keep it gone: the
# saving is invisible day to day, so nothing else would catch its return.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Hook Fork Budget Tests ==="

begin_test "no hook reads stdin with \$(cat) — that is a fork per hook per call"
OFFENDERS=$(grep -lE '^[A-Za-z_][A-Za-z0-9_]*=\$\(cat\)$' "$REPO_DIR"/hooks/*.sh 2>/dev/null | xargs -n1 basename 2>/dev/null || true)
[ -z "$OFFENDERS" ] && pass || fail "forking cat to read stdin: $(printf '%s' "$OFFENDERS" | tr '\n' ' ')"

begin_test "the fork-free read is the one actually in use"
grep -q "IFS= read -r -d '' _INPUT" "$REPO_DIR/hooks/safety.sh" && pass \
  || fail "safety.sh no longer uses the builtin read"

# The read must stay byte-identical to $(cat), including trailing-newline
# handling — several hooks do exact substring matching on the raw payload.
begin_test "the builtin read reproduces \$(cat) trailing-newline behaviour"
TD=$(mktemp -d)
printf 'A=$(cat)\nprintf "%%s" "${#A}"\n' > "$TD/a.sh"
{
  printf "IFS= read -r -d '' A || true\n"
  printf 'A="${A%%"${A##*[!$'"'"'\\n'"'"']}"}"\n'
  printf 'printf "%%s" "${#A}"\n'
} > "$TD/b.sh"
IN=$'{"x":1}\n\n\n'
CAT_LEN=$(printf '%s' "$IN" | bash "$TD/a.sh")
RD_LEN=$(printf '%s' "$IN" | bash "$TD/b.sh")
[ "$CAT_LEN" = "$RD_LEN" ] && pass || fail "cat=$CAT_LEN read=$RD_LEN — payload bytes differ"
rm -rf "$TD"

# python3 costs ~20ms to start — 7x any other fork. It is fine as a FALLBACK
# (jq failed) or on a block path (already exiting), but never unconditionally on
# a hook that fires for every command.
begin_test "no hot-path hook forks python3 unconditionally at top level"
BAD=""
for h in safety.sh git-safety.sh path-guard.sh harness-tamper-guard.sh; do
  f="$REPO_DIR/hooks/$h"
  [ -f "$f" ] || continue
  # Top level = column 0, not indented inside an if/case/function body, and not
  # part of an `||` fallback chain.
  if grep -nE '^[A-Za-z_][A-Za-z0-9_]*=\$\(printf[^|]*\| *python3' "$f" | grep -qv '||'; then
    BAD="$BAD $h"
  fi
done
[ -z "$BAD" ] && pass || fail "unconditional python3 fork in:$BAD"

begin_test "safety.sh keeps a fork-free clock on bash 5, and still stamps on 3.2"
grep -q "printf -v _sfx_ts '%(" "$REPO_DIR/hooks/safety.sh" \
  && grep -q "date '+%Y-%m-%dT%H:%M:%SZ'" "$REPO_DIR/hooks/safety.sh" && pass \
  || fail "the trace timestamp lost either its fork-free path or its bash 3.2 fallback"

begin_test "the forensic trace still records a timestamp"
TD=$(mktemp -d); mkdir -p "$TD/scope"
printf '{"tool_name":"Bash","cwd":"/tmp/p","tool_input":{"command":"grep -rn foo src/"}}' \
  | SUPERCHARGER_STATE="$TD" bash "$REPO_DIR/hooks/safety.sh" >/dev/null 2>&1
grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] cwd=' "$TD/scope/.safety-trace.log" \
  && pass || fail "trace line lost its timestamp: $(head -1 "$TD/scope/.safety-trace.log" 2>/dev/null)"
rm -rf "$TD"

# prompt-secret-guard partitions the pattern list and runs two greps. That work
# must sit behind a single combined grep — before v2.26.35 it ran on every
# prompt, including the vast majority with nothing secret-shaped in them, and
# cost +6.6ms per prompt (a 50% regression introduced in 2.26.29).
begin_test "prompt-secret-guard pre-filters before partitioning the pattern list"
awk '/COMBINED_PATTERN=/{seen=1} /grep -qE "\$COMBINED_PATTERN"/{if(seen) hit=1} /BLOCK_LIST=\(\)/{if(!hit) bad=1} END{exit bad?1:0}' \
  "$REPO_DIR/hooks/prompt-secret-guard.sh" && pass \
  || fail "the partition loop runs before the combined-pattern pre-filter"

report
