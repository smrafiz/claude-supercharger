#!/usr/bin/env bash
# Claude Supercharger — Bash Output Compactor
# Event: PostToolUse | Matcher: Bash,PowerShell
# Compresses verbose Bash output (git log, pytest/vitest/jest, npm install)
# before it enters Claude's context. Uses updatedToolOutput (v2.1.121 schema)
# to replace what Claude sees with a structured summary.
#
# Trigger: tool output > 50 lines AND command matches a known verbose pattern.
# Disable: SUPERCHARGER_BASH_COMPACTOR=0

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_BASH_COMPACTOR:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.25: bash fast-path before any fork. Most Bash commands aren't verbose
# patterns (git log / pytest / vitest / jest / mocha / ava / npm test / npm
# install / cargo test). Scan the raw stdin once — if no trigger token is
# present, exit immediately. Median 110ms → ~0ms on the common case.
case "$_INPUT" in
  # Dedup note: shell glob substring rules collapse several "obvious" entries:
  #   *'npm i'*    catches "npm i", "npm install", AND "pnpm install"  (pnpm install contains "npm i")
  #   *'npm test'* catches "npm test" AND "pnpm test"                  (pnpm test contains "npm test")
  #   *'go test'*  catches "go test" AND "cargo test"                  (cargo test contains "go test")
  # Removing the redundant longer forms eliminates shellcheck SC2221/SC2222
  # and changes nothing functionally — all four callsites verified by smoke
  # test (npm install, pnpm install, yarn install, pytest, cargo test).
  *'git log'*|*'npm test'*|*'yarn test'*|*vitest*|*jest*|*mocha*|*ava*|\
  *pytest*|*'go test'*|*'yarn install'*|*'pnpm add'*|*'npm i'*) ;;
  # 4.4.2: any other command gets the generic pass, but only for big output (the
  # payload length is a cheap upper bound; python re-checks the output itself) and unless SUPERCHARGER_COMPACT_GENERIC=0.
  *) { [ "${#_INPUT}" -ge 8000 ] && [ "${SUPERCHARGER_COMPACT_GENERIC:-1}" != 0 ]; } || exit 0 ;;
esac

# Single jq fork extracts all four fields at once — replaces the previous
# four sequential jq calls (~50ms × 4 = ~200ms saved per invocation when bash
# output is short). Fields are joined with US separator (\x1f) so they can
# never appear in command/output.
# v2.7.59: .cwd // .workspace.current_dir — CC 2.1.176+ sometimes sends the CWD in
# workspace.current_dir instead of .cwd (the v2.6.57 drift). This consolidated
# @tsv extraction (added in the perf sweep) had dropped the fallback → empty
# PROJECT_DIR → wrong project-scoped debug/profile detection.
# v2.27.29: the 4th field was the ENTIRE stdout and was never read. @tsv escapes
# newlines, so it could not be used as output anyway — which is why the raw
# stdout is re-extracted with its own jq below. Meanwhile every byte of a long
# test run was escaped by jq, copied into a shell variable, and then piped
# through THREE separate awk forks that only ever wanted fields 1 to 3. Dropping
# it leaves FIELDS a few hundred bytes instead of the whole run.
FIELDS=$(printf '%s\n' "$_INPUT" | jq -r '[.cwd // .workspace.current_dir // "", .tool_name // "", .tool_input.command // ""] | @tsv' 2>/dev/null || true)
# Split with parameter expansion instead of three awk forks. `%%` and `#` are
# single scans and stay linear; `//` is deliberately not used here. @tsv has
# already escaped any literal tab or newline inside the values, so splitting on
# the raw tabs is lossless.
_rest="$FIELDS"
PROJECT_DIR="${_rest%%$'\t'*}"; _rest="${_rest#*$'\t'}"
TOOL_NAME="${_rest%%$'\t'*}";   _rest="${_rest#*$'\t'}"
CMD="${_rest%%$'\t'*}"
# jq emits 2 tabs for 3 columns; none at all means jq failed and FIELDS is empty
# or garbage — blank the fields rather than mirroring it into every one.
case "$FIELDS" in *$'\t'*) ;; *) PROJECT_DIR=""; TOOL_NAME=""; CMD="" ;; esac
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "bash-output-compactor" && exit 0
hook_profile_skip "bash-output-compactor" && exit 0

case "$TOOL_NAME" in Bash|PowerShell) ;; *) exit 0 ;; esac

[ -z "$CMD" ] && exit 0

# Detect verbose pattern type — fast bash regex, no fork.
# Same substring-coverage rules as the fast-path case above:
#   *npm\ test* covers pnpm\ test, *pytest* covers python\ -m\ pytest,
#   *go\ test* covers cargo\ test, *npm\ i* covers npm/pnpm install.
PATTERN=""
case "$CMD" in
  *git\ log*) PATTERN="git-log" ;;
  *npm\ test*|*yarn\ test*|*vitest*|*jest*|*mocha*|*ava*|*pytest*|*go\ test*) PATTERN="test" ;;
  *yarn\ install*|*pnpm\ add*|*npm\ i*) PATTERN="install" ;;
  *) [ "${SUPERCHARGER_COMPACT_GENERIC:-1}" != 0 ] || exit 0; PATTERN="generic" ;;
esac

# Get tool output (stdout). Bash hook payloads include it under tool_response.stdout.
OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
[ -z "$OUTPUT" ] && exit 0

LINE_COUNT=$(printf '%s\n' "$OUTPUT" | wc -l | tr -d ' ')
# The generic pass judges by size in python: a few minified lines can be 100 KB.
[ "$LINE_COUNT" -lt 50 ] && [ "$PATTERN" != generic ] && exit 0

COMPACTED=$(PATTERN="$PATTERN" OUTPUT="$OUTPUT" LINE_COUNT="$LINE_COUNT" python3 <<'PYEOF'
import os, re

pattern = os.environ.get('PATTERN', '')
output = os.environ.get('OUTPUT', '')
line_count = int(os.environ.get('LINE_COUNT', 0))
lines = output.splitlines()

if pattern == 'git-log':
    head = lines[:5]
    tail = lines[-5:] if line_count > 10 else []
    summary = '\n'.join(head)
    if tail:
        summary += f'\n... [{line_count - 10} commits omitted] ...\n' + '\n'.join(tail)
    print(summary)

elif pattern == 'test':
    # Extract pass/fail counts. The LAST match: runners print the totals last, and
    # the first match was often a test name ("test_0 PASSED" read as "0 passed").
    def _last(rx):
        ms = list(re.finditer(rx, output, re.IGNORECASE))
        return ms[-1] if ms else None
    pass_match = _last(r'\b(\d+)\s+passed')
    fail_match = _last(r'\b(\d+)\s+failed')
    skip_match = _last(r'\b(\d+)\s+skipped')
    err_match  = _last(r'\b(\d+)\s+errors?\b')
    duration   = re.search(r'(?:in|took|finished in)\s+([\d.]+\s*[ms]+)', output, re.IGNORECASE)

    parts = []
    if pass_match: parts.append(f'{pass_match.group(1)} passed')
    if fail_match: parts.append(f'{fail_match.group(1)} failed')
    if skip_match: parts.append(f'{skip_match.group(1)} skipped')
    if err_match:  parts.append(f'{err_match.group(1)} errors')
    summary_line = ', '.join(parts) if parts else f'{line_count} lines of test output'
    if duration: summary_line += f' (in {duration.group(1)})'

    # Find failure block — keep last 25 lines around 'FAIL' / 'failed' / 'Error'
    fail_indices = [i for i, l in enumerate(lines) if re.search(r'(FAIL|✗|❌|Error:|AssertionError|expect)', l)]
    if fail_indices:
        start = max(0, fail_indices[0] - 5)
        end = min(len(lines), fail_indices[-1] + 20)
        # Cap excerpt at 30 lines
        if end - start > 30:
            end = start + 30
        excerpt = '\n'.join(lines[start:end])
        # 4.4.2 (ideas from headroomlabs-ai/headroom log_compressor.rs): the excerpt
        # is one window from the FIRST failure, so later failures and pytest's
        # "short test summary info" fell outside it. Every per-test failure line is
        # now kept (pytest FAILED/ERROR, go --- FAIL, jest ✕/●, vitest FAIL), and the
        # omitted marker names the exception types the excerpt does not show, so
        # Claude can tell whether the saved full output is worth opening.
        ids, seen_ids = [], set(excerpt.split('\n'))
        for l in lines:
            s = l.strip()
            if re.match(r'(FAILED|ERROR) \S|--- FAIL: |FAIL \S|[✕×] |● ', s) and s not in seen_ids:
                seen_ids.add(s); ids.append(s)
        shown = ids[:50]
        more = f'\n  +{len(ids) - 50} more failing tests' if len(ids) > 50 else ''
        all_failures = (f'\n[All failing tests — {len(ids)}]\n' + '\n'.join(shown) + more) if ids else ''
        kept = set(excerpt.split('\n')) | set(shown)
        types = []
        for l in lines:
            if l in kept:
                continue
            for t in re.findall(r'\b([A-Z]\w*(?:Error|Exception))\b', l):
                if t not in types and t not in excerpt:
                    types.append(t)
        omitted = line_count - (end - start)
        detail = f'; other exception types: {", ".join(types[:5])}' if types else ''
        print(f'[Test summary] {summary_line}\n[Failure excerpt — {end-start} lines]\n{excerpt}'
              f'{all_failures}\n[{omitted} lines omitted{detail}]')
    else:
        print(f'[Test summary] {summary_line}\n[All passed — {line_count} lines suppressed]')

elif pattern == 'install':
    # Find "added N packages" / "X packages installed"
    added = re.search(r'(\d+)\s+packages?(?:\s+(?:added|installed|updated))?', output, re.IGNORECASE)
    duration = re.search(r'(?:in|took)\s+([\d.]+\s*[ms]+)', output, re.IGNORECASE)
    summary_line = []
    if added: summary_line.append(f'{added.group(1)} packages')
    if duration: summary_line.append(f'in {duration.group(1)}')

    # Show only warnings/errors from output
    relevant = [l for l in lines if re.search(r'\b(warn|error|failed|deprecated|peer dep)', l, re.IGNORECASE)]
    total = len(relevant)
    # 4.4.2 (headroom log_compressor.rs): fold lines that differ only in numbers,
    # hex or paths AFTER their first ':' or '=', so distinct packages stay distinct
    # and the same message repeated for many versions shows once with a count. A
    # line with neither is kept as is: normalising all of it would merge packages.
    groups, order = {}, []
    for l in relevant:
        m = re.match(r'([^:=]*[:=])(.*)', l)
        key = m.group(1) + re.sub(r'0x[0-9a-fA-F]+|\d+(?:\.\d+)*|/\S+', '#', m.group(2)) if m else l
        if key not in groups:
            groups[key] = [l, 0]; order.append(key)
        groups[key][1] += 1
    relevant = [groups[k][0] + (f'  [x{groups[k][1]} similar]' if groups[k][1] > 1 else '') for k in order]
    shown_total = len(relevant)
    relevant = relevant[:15]

    base = '[Install summary] ' + (', '.join(summary_line) if summary_line else f'{line_count} lines')
    if relevant:
        # Say what the cap dropped, so 15 shown out of 200 does not read as "all of them".
        errs = sum(1 for l in relevant if re.search(r'\berr', l, re.IGNORECASE))
        more = f'\n[+{shown_total - 15} more warning/error lines omitted]' if shown_total > 15 else ''
        base += f'\n[Warnings/errors ({total}, {errs} of the shown are errors)]\n' + '\n'.join(relevant) + more
    else:
        base += '\n[No warnings or errors]'
    print(base)

elif pattern == 'generic':
    # 4.4.2 (ideas from headroom lossless_compaction.py and dense_line_elider.py):
    # for any other command, only steps that keep the meaning: colour codes go,
    # a run of 3+ identical lines becomes one line and a count, and lines that are
    # long and nearly space-free (minified JS, base64) keep their head and tail
    # when such lines add up to 2000+ chars, so a lone token or URL is spared.
    # Rewritten only when that saves at least 1000 chars and a fifth of the output.
    # 8000+ chars only: replaying 1421 real outputs, 4000 cost ~120 ms on 5x more
    # calls for 13% more saving.
    if len(output) < 8000:
        raise SystemExit(0)
    text = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', output)
    ls, out, i = text.split('\n'), [], 0
    while i < len(ls):
        j = i
        while j + 1 < len(ls) and ls[j + 1] == ls[i]:
            j += 1
        if j - i >= 2 and ls[i].strip():
            out += [ls[i], f'[... previous line repeated {j - i} more times]']
        else:
            out += ls[i:j + 1]
        i = j + 1
    dense = [k for k, l in enumerate(out) if len(l) >= 300 and l.count(' ') <= 0.06 * len(l)]
    if sum(len(out[k]) for k in dense) >= 2000:
        for k in dense:
            l = out[k]
            out[k] = l[:160] + f'[... {len(l) - 240} chars elided]' + l[-80:]
    new = '\n'.join(out)
    if len(output) - len(new) >= max(1000, len(output) // 5):
        print(new)
PYEOF
)

[ -z "$COMPACTED" ] && exit 0
# Keep the full output recoverable: the summary is all the model sees.
COMPACTED="$COMPACTED$(printf '%s' "$OUTPUT" | SC_HOOKS_DIR="$HOOKS_DIR" python3 -c 'import os,sys; sys.path.insert(0, os.environ["SC_HOOKS_DIR"]); from lib_fulloutput import save; sys.stdout.write(save(sys.stdin.read()))' 2>/dev/null)"

OUT_JSON=$(printf '%s' "$COMPACTED" | jq -Rs '.' 2>/dev/null || true)
[ -z "$OUT_JSON" ] && exit 0

# Use v2.1.121 updatedToolOutput to replace Claude's view with the compacted summary.
# Original output is preserved in transcript log; only context-injected version is compacted.
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":%s}}\n' "$OUT_JSON"
echo "[Supercharger] bash-output-compactor: compressed $LINE_COUNT-line $PATTERN output" >&2

exit 0
