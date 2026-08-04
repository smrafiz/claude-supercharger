#!/usr/bin/env bash
# Claude Supercharger — Claim/Evidence Gate
# Event: Stop | Matcher: *
#
# Checks a stated test result against what actually ran. CLAUDE.md's Verification
# Gate already says "run the check and confirm it passes, never say 'should work'"
# — but that is a prompt rule, and prompt rules are advisory. This is the
# enforcement half: the claim is compared against the recorded tool results in
# the transcript, which the model cannot retroactively edit.
#
# Two outcomes, deliberately different in severity:
#
#   CONTRADICTED  a pass was stated AND the most recent test run in the
#                 transcript reported failures  -> BLOCK the stop (exit 2).
#                 Unambiguous: the evidence is right there and says otherwise.
#
#   UNEVIDENCED   a pass was stated and no test command ran at all -> advisory
#                 note only. Genuinely ambiguous — the claim may be about a
#                 previous session, a CI run, or the user's own report — so this
#                 must not hold the session open.
#
# Idea from K-sushi/claude-notary's out-of-band verification, minus the
# re-execution: re-running the suite on every Stop would cost minutes per turn in
# any real repo. Reading what actually ran is the same check at no runtime cost.
#
# NOTE: Stop fires at the end of EVERY assistant turn, not once at session end.
# Everything here is bounded and read-only for that reason.
#
# Fully fail-open. Disable: SUPERCHARGER_CLAIM_EVIDENCE_GATE=0

set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-timing.sh
. "$HOOKS_DIR/lib-timing.sh" 2>/dev/null || true
# shellcheck source=hooks/lib-paths.sh
. "$HOOKS_DIR/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

[ "${SUPERCHARGER_CLAIM_EVIDENCE_GATE:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Never re-enter. Without this, blocking the stop and the model answering again
# with the same wording would loop forever.
case "$_INPUT" in *'"stop_hook_active":true'*) exit 0 ;; esac

TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Fast path. Stop runs every turn, so nothing expensive may happen before we know
# a claim was even made. grep over the tail is far cheaper than parsing JSON, and
# the overwhelming majority of turns exit here.
tail -c 20000 "$TRANSCRIPT" 2>/dev/null \
  | LC_ALL=C grep -qiE 'tests? (are )?(now )?pass|all tests|suite (is )?green|0 failed|no failures|build succeed|lint (is )?clean' \
  || exit 0

VERDICT=$(TRANSCRIPT_PATH="$TRANSCRIPT" python3 <<'PYEOF' 2>/dev/null || true
import json, os, re, sys

path = os.environ.get("TRANSCRIPT_PATH", "")
try:
    with open(path, "r", errors="replace") as f:
        lines = f.readlines()[-800:]
except Exception:
    sys.exit(0)

# A stated result about tests that ran. Present tense and unhedged only.
CLAIM = re.compile(
    r"\b("
    r"(all\s+)?tests?\s+(are\s+)?(now\s+)?pass(ing|ed|es)?"
    r"|suite\s+(is\s+)?green"
    r"|\d[\d,]*\s+passed,\s*0\s+failed"
    r"|no\s+failures"
    r"|build\s+succeed(s|ed)"
    r"|lint\s+(is\s+)?clean"
    r")\b", re.I)

# Hedged or conditional forms are not claims — they are plans.
HEDGE = re.compile(
    r"\b(if|once|when|after|assuming|unless|should|would|hope|expect|let'?s|need to|"
    r"make sure|verify that|check (that|whether)|to confirm)\b", re.I)

TEST_CMD = re.compile(
    r"\b(npm\s+(run\s+)?test|yarn\s+test|pnpm\s+(run\s+)?test|bun\s+test"
    r"|cargo\s+test|pytest|go\s+test|jest|vitest|mocha|rspec|phpunit"
    r"|dotnet\s+test|gradle\s+test|mvn\s+test|make\s+test"
    r"|tests?/run\.sh|run_tests|test\.sh)\b", re.I)

# Failure markers, split by case sensitivity — this distinction is the whole
# correctness of the hook. The uppercase forms are runner markers (pytest's
# "FAILED test_x::test_y", a red FAIL row) and MUST stay case-sensitive: under
# re.I, r"\bFAILED\b" matches the ordinary word "failed" in "3043 passed, 0
# failed", so a perfectly green run read as a failing one and blocked the stop.
# Caught by the clean-run test below, which is why that test exists.
FAIL_NUM = re.compile(
    r"(?<![\d,])(?!0\b)\d[\d,]*\s+(tests?\s+)?fail(ed|ures?)\b", re.I)
FAIL_UPPER = re.compile(r"\bFAILED\b|\bFAIL\b|\bAssertionError\b|✗|✘")

def is_failure(text):
    return bool(FAIL_NUM.search(text) or FAIL_UPPER.search(text))

def blocks(entry):
    msg = entry.get("message") or {}
    c = msg.get("content")
    return c if isinstance(c, list) else []

last_claim = None
test_calls = {}      # tool_use_id -> command
last_result = None   # (command, is_error, text)

for ln in lines:
    try:
        e = json.loads(ln)
    except Exception:
        continue
    t = e.get("type")
    if t == "assistant":
        for b in blocks(e):
            if b.get("type") == "text":
                txt = b.get("text") or ""
                for sent in re.split(r"(?<=[.!?\n])\s+", txt):
                    if CLAIM.search(sent) and not HEDGE.search(sent):
                        last_claim = sent.strip()[:180]
            elif b.get("type") == "tool_use" and b.get("name") == "Bash":
                cmd = (b.get("input") or {}).get("command", "") or ""
                if TEST_CMD.search(cmd):
                    test_calls[b.get("id")] = cmd
    elif t == "user":
        for b in blocks(e):
            if b.get("type") != "tool_result":
                continue
            tid = b.get("tool_use_id")
            if tid not in test_calls:
                continue
            content = b.get("content")
            if isinstance(content, list):
                text = " ".join(x.get("text", "") for x in content if isinstance(x, dict))
            else:
                text = str(content or "")
            last_result = (test_calls[tid], bool(b.get("is_error")), text[-4000:])

if not last_claim:
    sys.exit(0)

if last_result is None:
    print(json.dumps({"verdict": "unevidenced", "claim": last_claim}))
    sys.exit(0)

cmd, is_error, out = last_result

# v2.26.47: a run KILLED before it finished is not a run that reported failures.
# `is_error` is set for any non-zero exit, including SIGTERM from a harness
# timeout (143) and SIGINT (130). Blocking on that told the author "the tests
# failed" when nothing had failed — the command simply never produced a verdict.
# Observed on a suite run cut off by a 10-minute tool timeout: the completed run
# immediately before it was 3251/0.
#
# Treat it as NO EVIDENCE rather than contradiction: an interrupted run genuinely
# tells us nothing about whether the tests pass, so the honest response is the
# advisory ("no result in this session"), not a hard block asserting failure.
# Only when the output carries no failure markers of its own — a real failure
# that also happened to be killed still contradicts the claim.
TERMINATED_RE = re.compile(
    r'command timed out after'
    r'|\\bexit code (13[0-9]|14[0-9]|15[0-9])\\b'
    r'|terminated by signal|\\bsigterm\\b|\\bsigkill\\b|\\bsigint\\b',
    re.IGNORECASE)

if is_error and not is_failure(out) and TERMINATED_RE.search(out):
    print(json.dumps({"verdict": "unevidenced", "claim": last_claim}))
    sys.exit(0)

if is_error or is_failure(out):
    excerpt = ""
    for line in out.splitlines():
        if is_failure(line):
            excerpt = line.strip()[:160]
            break
    print(json.dumps({"verdict": "contradicted", "claim": last_claim,
                      "cmd": cmd[:120], "evidence": excerpt or "the run exited non-zero"}))
PYEOF
)

[ -z "$VERDICT" ] && exit 0

KIND=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('verdict',''))" 2>/dev/null || true)

if [ "$KIND" = "contradicted" ]; then
  CLAIM=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('claim',''))" 2>/dev/null || true)
  CMD=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cmd',''))" 2>/dev/null || true)
  EV=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('evidence',''))" 2>/dev/null || true)
  {
    echo "[Supercharger] claim-evidence-gate: you stated a passing result, but the last test run in this session reported failures."
    echo "  You wrote : ${CLAIM}"
    echo "  Last ran  : ${CMD}"
    echo "  It said   : ${EV}"
    echo "  Re-run it and report the real result, or say plainly which tests fail and why. Do not restate the claim."
  } >&2
  BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] claim contradicted by recorded test result — stop blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  exit 2
fi

# Unevidenced: advisory only. The claim may legitimately be about a prior
# session, a CI run, or something the user reported, and this must never hold a
# session open on that guess.
if [ "$KIND" = "unevidenced" ]; then
  echo "[Supercharger] claim-evidence-gate: a passing test result was stated, but no test command ran in this session. If the result is from earlier or from CI, say so; otherwise run it." >&2
fi

exit 0
