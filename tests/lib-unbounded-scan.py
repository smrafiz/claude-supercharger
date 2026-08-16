"""Find greedy bash string operations applied to payload-sized input.

Two bugs in one day came from this shape, both introduced as optimisations:
  * _json_fast_str  — ${body#*"key"} / ${after%%\"*} over a whole payload,
                      280x slower than the jq fork it replaced at 74KB.
  * learn-from-prompts — ${PROMPT//$'\n'/ } over a whole prompt to build a
                      200-char snippet: 454s on 64KB, 4h46m observed live.

Bash rebuilds the string for these, superlinearly. On a variable holding a tool
payload (unbounded — a user can paste a file) that is a hang, not a slowdown.

A site is OK if a size limit is established BEFORE it: an explicit ${#var} test,
or slicing the variable down (${var:0:N}) first.
"""
import os
import re
import sys

HOOKS = sys.argv[1] if len(sys.argv) > 1 else "hooks"

# Variables that hold tool input (unbounded by definition).
PAYLOAD_VARS = r"(?:_INPUT|PROMPT|COMMAND|CMD|CMD_NORM|body|PAYLOAD|OUTPUT|TEXT|CONTENT)"

# ONLY global substitution. ${var//x/y} REBUILDS the string and is superlinear;
# ${var##*X} and ${var%%X*} are single scans and stay linear. Measured on macOS:
#
#      8 KB   //subst    646 ms   ##strip 23 ms   %%strip 21 ms
#     32 KB   //subst  57557 ms   ##strip 70 ms   %%strip 51 ms
#
# Flagging the strips too would have demanded a rewrite of context-advisor, which
# measures 51ms on a 32KB prompt — churn for nothing. Cost, not shape, decides.
GREEDY = re.compile(r"\$\{(%s)//" % PAYLOAD_VARS)

# The universal trailing-newline strip, in whatever variable a hook names:
#     VAR="${VAR%"${VAR##*[!$'\n']}"}"
# Measured FLAT (~20ms at 15-63KB) — the pattern anchors at the end and stops
# immediately — and it is in 122 hooks by design. Recognised by SHAPE rather than
# by one variable's spelling: the first draft hardcoded _INPUT and then flagged
# notify.sh, which does exactly the same thing to a variable called PAYLOAD.
NEWLINE_STRIP = re.compile(r'\$\{(\w+)%"\$\{\1##\*\[!')

# A size limit anywhere earlier in the file counts: these hooks are short and
# linear, so "before" is a fair approximation of "guards".
GUARD = re.compile(
    r"\$\{#%s\}|\$\{%s:0:|SUPERCHARGER_JSON_FAST_MAX|_json_fast_str" % (PAYLOAD_VARS, PAYLOAD_VARS)
)

findings = []
for fn in sorted(os.listdir(HOOKS)):
    if not fn.endswith(".sh"):
        continue
    path = os.path.join(HOOKS, fn)
    lines = open(path, errors="ignore").read().splitlines()
    guarded_from = None
    for i, ln in enumerate(lines, 1):
        stripped = ln.strip()
        if stripped.startswith("#"):
            continue
        if GUARD.search(ln):
            guarded_from = i
        m = GREEDY.search(ln)
        if not m:
            continue
        if NEWLINE_STRIP.search(ln):
            continue
        if guarded_from is not None and guarded_from <= i:
            continue
        findings.append((fn, i, m.group(1), stripped[:64]))

if findings:
    print("UNGUARDED greedy string ops on payload variables:")
    for fn, i, var, src in findings:
        print("  %-30s :%-4s %-8s %s" % (fn, i, var, src))
    print("\n%d site(s)" % len(findings))
else:
    print("none — every greedy op on a payload variable has a size limit before it")
