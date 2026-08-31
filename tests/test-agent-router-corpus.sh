#!/usr/bin/env bash
# Routing corpus for agent-router — one expected agent per prompt.
#
# The existing suite asserts positives: error->Detective, review->Critic,
# implement->Engineer. That catches a router that stops working. It does not
# catch a router that answers CONFIDENTLY WRONG, which is the failure that
# actually happens, because the chain is ordered and an early rule's vocabulary
# can capture a prompt belonging to a later one.
#
# Measured 2026-08-31, before the verb-guard fix: four clear misroutes, all the
# same shape — the Detective and Analyst rules match on NOUNS (error, csv,
# report) while the VERB stated a different intent.
#
#   explain how the error handling works  -> Detective   (wanted Scientist)
#   document the error codes              -> Detective   (wanted Writer)
#   fix the csv parser                    -> Analyst     (wanted Engineer)
#   write a quarterly report              -> Analyst     (wanted Writer)
#
# The NEAR-MISS half is the load-bearing one. Every negative below carries an
# earlier rule's trigger word and must still route past it; a corpus of only
# clean positives would have passed against the broken router.
#
# Two cases are deliberately pinned to CURRENT behaviour and marked AMBIGUOUS:
# they have a defensible answer either way, and pinning them stops a future
# regex edit from changing them silently without claiming they are ideal.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/hooks/agent-router.sh"
echo "=== agent-router routing corpus ==="

_route() {  # $1 = prompt -> first token of the classified agent
  local d f
  d=$(mktemp -d); mkdir -p "$d/.claude/supercharger/scope"
  P="$1" python3 -c "import json,os;print(json.dumps({'prompt':os.environ['P']}))" \
    | HOME="$d" bash "$ROUTER" >/dev/null 2>&1
  f="$d/.claude/supercharger/scope/.agent-classified-default"
  if [ -f "$f" ]; then head -1 "$f" | awk '{print $1}'; else echo "(none)"; fi
  rm -rf "$d"
}

N=0
while IFS='|' read -r PROMPT WANT; do
  [ -z "$PROMPT" ] && continue
  case "$PROMPT" in \#*) continue ;; esac
  N=$((N + 1))
  begin_test "route: ${PROMPT:0:58} -> $WANT"
  GOT=$(_route "$PROMPT")
  [ "$GOT" = "$WANT" ] && pass || fail "got $GOT, wanted $WANT"
done <<'CORPUS'
# --- positives: the intent is unambiguous ---
there is a null pointer exception at line 42|Sherlock
the build is failing with exit code 1|Sherlock
review this PR for security issues|Gordon
check my error handling for edge cases|Gordon
analyze this csv and show top sellers|Albert
how many users signed up last month|Albert
where is the retry logic defined|Ferdinand
which file handles session expiry|Ferdinand
find all callers of the legacy auth client|Ferdinand
write a function that validates emails|Tony
write a test for the parser|Tony
write a blog post about our outage last week|Ernest
draft release notes for v4.0|Ernest
how should I structure the API|Leonardo
plan the rollout for the new feature|Sun
break down this project into phases|Sun
what is the difference between a heatmap and a choropleth|Marie
compare redis vs memcached for our cache|Marie
# --- near misses: each carries an EARLIER rule's trigger word ---
explain how the error handling in this module works|Marie
document the error codes for the API reference|Ernest
fix the csv parser, it drops the last column|Tony
write a quarterly report for the board|Ernest
build a dashboard that renders our metrics|Tony
create a script that queries the dataset nightly|Tony
refactor the sql builder so it is testable|Tony
document why the crash happens on startup|Ernest
explain what a stack trace actually contains|Marie
describe the metrics we report to the board|Ernest
summarize the audit findings for the team|Ernest
# --- AMBIGUOUS: pinned to current behaviour, not asserted as ideal ---
review the plan before I start building|Gordon
design a logo for the docs site|Leonardo
CORPUS

report
