#!/usr/bin/env bash
# [BLOCKS] summary rendering (v2.26.63)
#
# safety.sh:541 blocks with `dangerous pattern: $pattern` — the reason field for
# those entries is raw REGEX SOURCE. learn-from-blocks capped the reason at 80
# chars and injected the top 8 into every session start, so six of eight
# "learnings" read like this:
#     dangerous pattern: [^|]\|[[:space:]]*(bash|sh|zsh|dash)([[:space:]]+-[[:alnum:]-
# — truncated mid-character-class, unactionable, and crowding the readable
# reasons (self-modification, .env access, python -c shell-out) out of the list
# entirely. These pin the collapse.
#
# The hook REWRITES the ledger it reads (30-day rotation + dedup), so every case
# here runs against an isolated state dir AND an isolated HOME. Pointing only
# SUPERCHARGER_STATE at a temp dir has leaked into live telemetry before.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TODAY=$(date -u +%Y-%m-%d)

# Feed a ledger body to learn-from-blocks, echo the [BLOCKS]…[CORR] systemMessage.
summarize() { # ledger-body -> systemMessage text
  local body="$1" st out
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  printf '%s\n' "$body" > "$st/scope/.blocked-commands"
  out=$(printf '{"session_id":"blk","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$st" \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/learn-from-blocks.sh" 2>/dev/null)
  printf '%s' "$out" | python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: sys.exit(0)
try: print(json.loads(raw).get('systemMessage',''))
except Exception: sys.exit(0)
"
  rm -rf "$st"
}

# Two DIFFERENT rules that share their first 80 characters. Keying the rule set on
# the truncated form would merge them and under-report the count.
PFX='(^|;|&)[[:space:]]*(bash|sh|zsh|dash|ksh|fish)[[:space:]]+-[[:alnum:]]*c[[:space:]]+'
REGEX_A="${PFX}curl"
REGEX_B="${PFX}wget"

echo "=== [BLOCKS] Summary Rendering Tests ==="

begin_test "regex-source reasons collapse into ONE line, not one line each"
OUT=$(summarize "[$TODAY 09:00] dangerous pattern: curl.*\\|.*bash — curl x | bash
[$TODAY 09:01] dangerous pattern: DROP([[:space:]])+TABLE — psql -c 'DROP TABLE u'
[$TODAY 09:02] dangerous pattern: $REGEX_A — bash -c curl
[$TODAY 09:03] dangerous pattern: $REGEX_B — bash -c wget")
N=$(printf '%s' "$OUT" | grep -c 'dangerous command patterns' || true)
[ "$N" -eq 1 ] && pass || fail "expected 1 collapsed line, got $N — $OUT"

begin_test "no raw regex source survives into the injected summary"
# The whole point: a truncated POSIX class teaches the model nothing. Assert on
# metacharacter shapes that only appear in regex, not in prose reasons.
OUT=$(summarize "[$TODAY 09:00] dangerous pattern: curl.*\\|.*bash — curl x | bash
[$TODAY 09:02] dangerous pattern: $REGEX_A — bash -c curl")
if printf '%s' "$OUT" | grep -qE '\[\[:(space|alnum):\]\]|\.\*\\\||\(\^\|'; then
  fail "regex source leaked into the summary: $OUT"
else
  pass
fi

begin_test "distinct rules are counted on the FULL regex, not the 80-char prefix"
# REGEX_A and REGEX_B are identical for their first 80 chars and differ after.
OUT=$(summarize "[$TODAY 09:02] dangerous pattern: $REGEX_A — bash -c curl
[$TODAY 09:03] dangerous pattern: $REGEX_B — bash -c wget")
printf '%s' "$OUT" | grep -q '2 rules' && pass || fail "prefix collision merged two rules: $OUT"

begin_test "the collapsed line reports total occurrences, not rule count"
OUT=$(summarize "[$TODAY 09:00] dangerous pattern: curl.*\\|.*bash — curl a | bash
[$TODAY 09:01] dangerous pattern: curl.*\\|.*bash — curl b | bash
[$TODAY 09:02] dangerous pattern: curl.*\\|.*bash — curl c | bash")
printf '%s' "$OUT" | grep -q '1 rules, blocked 3x' && pass || fail "occurrence count wrong: $OUT"

begin_test "readable reasons still render one line each, with their own counts"
OUT=$(summarize "[$TODAY 09:00] self-modification — rm hook
[$TODAY 09:01] self-modification — rm hook
[$TODAY 09:02] .env file access (.env) — cat .env")
{ printf '%s' "$OUT" | grep -q 'self-modification (blocked 2x' \
  && printf '%s' "$OUT" | grep -q '\.env file access'; } \
  && pass || fail "prose reasons lost or miscounted: $OUT"

begin_test "readable reasons are no longer crowded out by regex entries"
# The regression that mattered: 8 slots, all consumed by regex, so the actionable
# reasons never reached the model. Nine distinct patterns + one prose reason.
LED=""
for i in 1 2 3 4 5 6 7 8 9; do
  LED="${LED}[$TODAY 09:0$i] dangerous pattern: rule-${i}[[:space:]]+x — cmd$i
"
done
LED="${LED}[$TODAY 09:59] self-modification — rm hook"
OUT=$(summarize "$LED")
printf '%s' "$OUT" | grep -q 'self-modification' && pass || fail "prose reason crowded out: $OUT"

begin_test "a ledger of only regex entries still produces a [BLOCKS] section"
OUT=$(summarize "[$TODAY 09:00] dangerous pattern: curl.*\\|.*bash — curl x | bash")
printf '%s' "$OUT" | grep -q '^\[BLOCKS\]' && pass || fail "section vanished: $OUT"

begin_test "an absent ledger still emits nothing"
ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home"
OUT=$(printf '{"session_id":"blk","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$ST" \
  | env HOME="$ST/home" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/learn-from-blocks.sh" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no output for an empty ledger, got: $OUT"
rm -rf "$ST"

begin_test "malformed ledger rows are skipped without killing the summary"
OUT=$(summarize "this row has no timestamp at all
[$TODAY 09:00] self-modification — rm hook")
printf '%s' "$OUT" | grep -q 'self-modification' && pass || fail "one bad row broke the summary: $OUT"

report
