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
#   PLACEHOLDER   the turn stated the work is COMPLETE while itself writing a
#                 TODO/FIXME/NotImplementedError into a code file, and the marker
#                 is still on disk -> BLOCK (exit 2). Same contradiction shape as
#                 the first case, against a different piece of evidence: the code
#                 the turn wrote, not the run it recorded. CLAUDE.md's
#                 verification gate level 2 ("real implementation, not placeholder
#                 — no TODO, FIXME, stubs") was prose with no mechanism; this is
#                 the mechanism. Disable this arm alone:
#                 SUPERCHARGER_PLACEHOLDER_CLAIM=0
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
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Never re-enter. Without this, blocking the stop and the model answering again
# with the same wording would loop forever.
case "$_INPUT" in *'"stop_hook_active":true'*) exit 0 ;; esac

TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Fast path. Stop runs every turn, so nothing expensive may happen before we know
# a claim was even made. grep over the tail is far cheaper than parsing JSON, and
# the overwhelming majority of turns exit here.
#
# The completion alternatives belong in THIS grep, not only in the python: an arm
# whose evidence never reaches the detector is dead code that tests still pass
# (see [[two-gate-trap]] — six instances of exactly this).
tail -c 20000 "$TRANSCRIPT" 2>/dev/null \
  | LC_ALL=C grep -qiE 'tests? (are )?(now )?pass|all tests|suite (is )?green|0 failed|no failures|build succeed|lint (is )?clean|implemented|implementation is (complete|done)|nothing (left|else) to |production.?ready|ready to (ship|merge)|(it.s|this is|that.s|all) (done|complete|finished)' \
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

# v2.29.27: a sentence that DISCLAIMS a figure is not a claim about it. The gate
# fired on "...is accurate the way it was measured, and wrong in a clean checkout"
# -- a sentence whose whole point was that the quoted number does not hold. HEDGE
# covers conditionals ("once tests pass"); this covers retractions.
DISCLAIM = re.compile(
    r"\b(wrong|incorrect|inaccurate|misleading|stale|outdated|no longer|used to|"
    r"overstated|does not hold|did not hold|not\s+(accurate|true|correct|the case))\b",
    re.I)

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

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
PASS_LINE = re.compile(r"^\s*(?:PASS|OK|ok|\u2713|\u2714)\b")

# v2.29.27: a line whose OWN verdict marker is PASS is not failure evidence, no
# matter what its test NAME contains. This repo's suite emits the green line
#   PASS pytest FAILED markers are detected
# and FAIL_UPPER matched "FAILED" inside that name -- so a fully green run read as
# failing, and the block quoted a PASSING line as proof of failure. Strip ANSI
# first: the suite colours its markers, so the prefix match would never fire.
def _line_fails(line):
    s = ANSI_RE.sub("", line)
    if PASS_LINE.match(s):
        return False
    return bool(FAIL_NUM.search(s) or FAIL_UPPER.search(s))

def is_failure(text):
    return any(_line_fails(ln) for ln in text.splitlines())

# v2.29.29: a test command that ran NOTHING is not evidence of a passing suite.
# Borrowed from ggwhite/4x's ac_checks linter, which rejects `true`, `echo` and
# bare `grep` as verification on the principle that a check must EXECUTE the thing
# under test. Our version of that hole is the invocation that collects, deselects
# or finds nothing: it matches TEST_CMD, exits 0, and reports no failures, so the
# gate read it as a green run. Probed before the fix -- all five shapes below were
# waved through while the turn claimed "All tests pass."
ZERO_OUT = re.compile(
    r"\bcollected 0 items\b"
    r"|\bno tests ran\b"
    r"|\bno tests found\b"
    r"|\bno tests to run\b"
    r"|\bran 0 tests\b"
    r"|\b0 tests? (?:ran|executed|passed|selected)\b"
    # Exactly zero passed AND zero failed. The lookbehind stops this matching the
    # "0 passed" inside "10 passed, 0 failed", which is a real (if small) run.
    r"|(?<![\d,])0\s+passed,\s*0\s+failed\b"
    # pytest: everything collected was deselected, so nothing executed.
    r"|\bcollected (\d+) items? / \1 deselected\b",
    re.I)
# Command-side tells, for runners that print nothing conclusive.
ZERO_CMD = re.compile(r"--collect-only|--passwithnotests|--list-tests|--dry-run", re.I)

def zero_test_reason(cmd, text):
    m = ZERO_CMD.search(cmd)
    if m:
        return "the command carried %s, which runs no tests" % m.group(0)
    for ln in text.splitlines():
        if ZERO_OUT.search(ln):
            return ln.strip()[:160]
    return ""

def blocks(entry):
    msg = entry.get("message") or {}
    c = msg.get("content")
    return c if isinstance(c, list) else []

# --- placeholder arm --------------------------------------------------------
# Idea from ezBuilder/code-brain's completion_guard signal 4, with its scoping fix
# kept: only markers the turn ITSELF introduced count, else every repo with a TODO
# backlog fires forever. Where it diffs the tree, this reads the transcript's own
# Write/Edit inputs — added text by definition, and no git fork on a Stop hook.
#
# Case-SENSITIVE on purpose. Under re.I, "todo" matches `todos.map(...)` and a
# prose "to do"; the runner-marker lesson above is the same lesson.
PLACEHOLDER = re.compile(r"\bTODO\b|\bFIXME\b|\bNotImplementedError\b")

# A marker in prose is a note, not a stub. The rule being enforced is about
# implementations, so only code files can contradict a completion claim.
PROSE_EXT = frozenset({".md", ".markdown", ".rst", ".txt", ".adoc", ".org"})

DONE = re.compile(
    r"\b(fully|now|already)\s+implemented\b"
    r"|\bimplementation\s+is\s+(complete|done|finished)\b"
    r"|\bcomplete(d)?\s+the\s+implementation\b"
    r"|\bno\s+(remaining\s+)?(todos?|placeholders?|stubs?)\b"
    r"|\bnothing\s+(left|else)\s+to\s+(do|implement)\b"
    r"|\bproduction[- ]ready\b"
    r"|\bready\s+to\s+(ship|merge)\b"
    r"|\b(it'?s|this is|that'?s|all)\s+(done|complete|finished)\b"
    r"|\bfully\s+working\b", re.I)

def edits_of(name, inp):
    """(path, added, removed) per edit, for the three file-writing tools."""
    if name == "Write":
        return [(inp.get("file_path") or "", inp.get("content") or "", "")]
    if name == "Edit":
        return [(inp.get("file_path") or "",
                 inp.get("new_string") or "", inp.get("old_string") or "")]
    if name == "MultiEdit":
        p = inp.get("file_path") or ""
        return [(p, e.get("new_string") or "", e.get("old_string") or "")
                for e in (inp.get("edits") or []) if isinstance(e, dict)]
    return []

def placeholder_hit(writes):
    """First marker this turn ADDED that is STILL on disk, or None.

    Two filters, and both are load-bearing. `line not in removed` keeps an Edit
    from being blamed for a marker it merely carried through unchanged context.
    The disk read then drops the common honest sequence: write a stub, replace
    it later in the same turn, say it is done -- which it now is.
    """
    for path, added, removed in writes:
        if not path or os.path.splitext(path)[1].lower() in PROSE_EXT:
            continue
        for line in added.splitlines():
            s = line.strip()
            if not s or not PLACEHOLDER.search(line) or s in removed:
                continue
            try:
                with open(path, "r", errors="replace") as f:
                    on_disk = s in f.read(400000)
            except Exception:
                on_disk = False       # unwritten or deleted: no evidence, no block
            if on_disk:
                return path, s[:160]
    return None

last_claim = None
test_calls = {}      # tool_use_id -> command
last_result = None   # (command, is_error, text)
writes = []          # (path, added, removed) — CURRENT turn only
done_claim = None    # completion stated in the CURRENT turn

def is_turn_start(entry):
    """A user entry that is a real message, not a tool_result carrier.

    The placeholder arm must be scoped to this turn: a stub written five turns
    ago and since replaced is not evidence against anything said now.
    """
    c = (entry.get("message") or {}).get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        return not any(isinstance(b, dict) and b.get("type") == "tool_result"
                       for b in c)
    return False

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
                    hedged = HEDGE.search(sent) or DISCLAIM.search(sent)
                    if CLAIM.search(sent) and not hedged:
                        last_claim = sent.strip()[:180]
                    if DONE.search(sent) and not hedged:
                        done_claim = sent.strip()[:180]
            elif b.get("type") == "tool_use" and b.get("name") == "Bash":
                cmd = (b.get("input") or {}).get("command", "") or ""
                if TEST_CMD.search(cmd):
                    test_calls[b.get("id")] = cmd
            elif b.get("type") == "tool_use":
                writes.extend(edits_of(b.get("name") or "", b.get("input") or {}))
    elif t == "user":
        if is_turn_start(e):
            writes = []
            done_claim = None
            continue
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

# Evaluated BEFORE the test-claim exits below, not after. Placed after them it
# would be unreachable on any turn that made no test claim -- which is most turns
# that say "implemented" -- and its tests would still pass. Both verdicts block,
# so precedence costs nothing but the wording of the message.
if os.environ.get("SUPERCHARGER_PLACEHOLDER_CLAIM", "1") != "0" and done_claim:
    _hit = placeholder_hit(writes)
    if _hit:
        print(json.dumps({"verdict": "placeholder", "claim": done_claim,
                          "cmd": _hit[0], "evidence": _hit[1]}))
        sys.exit(0)

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

# Guarded on `not is_error and not is_failure`, not on position: a run that both
# failed AND ran nothing is a FAILING run, and must fall through to the
# contradicted block below rather than be softened to this advisory tier.
if not is_error and not is_failure(out):
    _zt = zero_test_reason(cmd, out)
    if _zt:
        print(json.dumps({"verdict": "zerotest", "claim": last_claim,
                          "cmd": cmd[:120], "evidence": _zt}))
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

if [ "$KIND" = "placeholder" ]; then
  CLAIM=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('claim',''))" 2>/dev/null || true)
  CMD=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cmd',''))" 2>/dev/null || true)
  EV=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('evidence',''))" 2>/dev/null || true)
  {
    echo "[Supercharger] claim-evidence-gate: you stated the work is complete, but this turn wrote a placeholder into the code and it is still there."
    echo "  You wrote : ${CLAIM}"
    echo "  In file   : ${CMD}"
    echo "  The line  : ${EV}"
    echo "  Finish it, or say plainly what is left and why it is left. Do not restate the claim."
  } >&2
  BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] completion claimed with a placeholder this turn wrote — stop blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  exit 2
fi

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
# Zero-test: advisory, never a block. The run did not FAIL -- it proved nothing,
# which is the same standing as no run at all, so it gets the same soft tier.
if [ "$KIND" = "zerotest" ]; then
  CLAIM=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('claim',''))" 2>/dev/null || true)
  CMD=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cmd',''))" 2>/dev/null || true)
  EV=$(printf '%s' "$VERDICT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('evidence',''))" 2>/dev/null || true)
  {
    echo "[Supercharger] claim-evidence-gate: you stated a passing result, but the last test run executed NO tests."
    echo "  You wrote : ${CLAIM}"
    echo "  Last ran  : ${CMD}"
    echo "  It said   : ${EV}"
    echo "  A run that collected, deselected or found nothing is not evidence. Run the real suite before restating this."
  } >&2
fi

if [ "$KIND" = "unevidenced" ]; then
  echo "[Supercharger] claim-evidence-gate: a passing test result was stated, but no test command ran in this session. If the result is from earlier or from CI, say so; otherwise run it." >&2
fi

exit 0
