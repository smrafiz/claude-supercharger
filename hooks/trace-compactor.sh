#!/usr/bin/env bash
# Claude Supercharger — Trace Compactor Hook
# Event: PostToolUse | Matcher: Bash,PowerShell
# Collapses stack frames in large Python/Node output, keeping every other line.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.27.31: cwd via the fork-free reader (jq fallback intact). The OUTPUT read
# below stays on jq — it pulls the whole of stdout, the large escape-carrying
# value the fast reader is built to refuse — but cwd is a short top-level field
# that was costing a jq fork of its own on every call.
_json_get PROJECT_DIR cwd "$_INPUT" '.cwd // .workspace.current_dir // empty'
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

OUTPUT=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.stdout // .tool_response.output // empty' 2>/dev/null || true)
if [ -z "$OUTPUT" ]; then
  OUTPUT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; r=json.load(sys.stdin).get('tool_response',{}); print(r.get('stdout') or r.get('output') or '')" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0

# Skip python startup cost for short outputs
[ "${#OUTPUT}" -lt 2000 ] && exit 0

SC_HOOKS_DIR="$HOOKS_DIR" TC_OUTPUT="$OUTPUT" TC_SUPPRESS="$HOOK_SUPPRESS" TC_GENERIC="${SUPERCHARGER_TRACE_COMPACT_GENERIC:-}" python3 <<'PYEOF'
import os, json, re, sys
sys.path.insert(0, os.environ.get('SC_HOOKS_DIR', ''))
from lib_fulloutput import save as _save_full

output = os.environ.get('TC_OUTPUT', '')
original_len = len(output)

summary = None

# 4.4.2 (idea from headroomlabs-ai/headroom, log_compressor.rs frame collapse):
# collapse stack FRAMES in place and keep every other line. This replaced a summary
# that swapped the WHOLE output for one line whenever it held a traceback, so a long
# pytest run with one traceback reached Claude as a single line, every other result
# gone. Kept: the exception line, chained-exception lines ("During handling of the
# above exception", "Caused by:"), all non-frame output, the first 2 and last 3
# frames of each stack, and up to 5 more app frames nearest the innermost one.
_LIB_PY = re.compile(r'site-packages|dist-packages|/lib/python\d|<frozen |importlib\._bootstrap|\\Lib\\')
_LIB_JS = re.compile(r'node_modules|node:internal|\(internal/|\(node:')
_PY_FRAME = re.compile(r'^(\s+)File "(.+?)", line \d+')
_JS_FRAME = re.compile(r'^(\s+)at ')


def _collapse(frames, lib_re):
    """frames: list of line-lists, outermost first. Returns the lines to keep."""
    n = len(frames)
    if n <= 8:
        return [l for f in frames for l in f]
    is_lib = [bool(lib_re.search(f[0])) for f in frames]
    keep = set(range(2)) | set(range(n - 3, n))
    keep |= set([i for i in range(2, n - 3) if not is_lib[i]][-5:])
    out, run, run_lib = [], 0, True
    indent = re.match(r'\s*', frames[0][0]).group(0)
    for i, f in enumerate(frames):
        if i in keep:
            if run:
                out.append(f'{indent}[... {run} {"library " if run_lib else ""}frames collapsed]')
                run, run_lib = 0, True
            out.extend(f)
        else:
            run += 1
            run_lib = run_lib and is_lib[i]
    return out


def _compact(text):
    lines = text.split('\n')
    out, i, n = [], 0, len(lines)
    while i < n:
        m = _PY_FRAME.match(lines[i])
        if m:
            frames = []
            while i < n and _PY_FRAME.match(lines[i]):
                ind = len(_PY_FRAME.match(lines[i]).group(1))
                f = [lines[i]]; i += 1
                # the code line and any ^^^ markers sit deeper than "File"
                while i < n and lines[i].strip() and not _PY_FRAME.match(lines[i]) \
                        and len(lines[i]) - len(lines[i].lstrip()) > ind:
                    f.append(lines[i]); i += 1
                frames.append(f)
            out.extend(_collapse(frames, _LIB_PY))
            continue
        if _JS_FRAME.match(lines[i]):
            frames = []
            while i < n and _JS_FRAME.match(lines[i]):
                frames.append([lines[i]]); i += 1
            out.extend(_collapse(frames, _LIB_JS))
            continue
        out.append(lines[i]); i += 1
    return '\n'.join(out)


if 'Traceback (most recent call last):' in output or re.search(r'\n\s+at (?:Object\.|async |new |Module\.|\S+ \()', output):
    compacted = _compact(output)
    # Only worth a rewrite when it saves something real; otherwise leave it alone.
    if original_len - len(compacted) >= 500:
        summary = compacted

# --- Generic large output (opt-in only) ---
if summary is None:
    # 2.21.11: do NOT silently rewrite arbitrary large output by default. This
    # hook's scope is Python/Node tracebacks (see header); the old unconditional
    # else-branch truncated ANY >=2000-char output to first-2000 + last-500 and
    # substituted it via updatedToolOutput, so Claude saw a `cat bigfile` / long
    # log with its MIDDLE silently removed and acted on it as if complete.
    # bash-output-compactor handles the specific verbose commands worth
    # compacting; general truncation is now opt-in via
    # SUPERCHARGER_TRACE_COMPACT_GENERIC=1.
    if os.environ.get('TC_GENERIC'):
        first = output[:2000]
        last = output[-500:]
        omitted = original_len - 2500
        summary = first + f'\n[... {omitted} chars omitted ...]\n' + last

if summary is not None:
    summary += _save_full(output)
    new_len = len(summary)
    # v2.6.2: replace Claude's view of the tool output with the compacted summary
    # via hookSpecificOutput.updatedToolOutput. Previously this hook emitted a
    # systemMessage which added the summary AS WELL as Claude seeing the full
    # traceback — defeating the purpose. updatedToolOutput cleanly substitutes.
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PostToolUse',
            'updatedToolOutput': summary,
        }
    }))
    import sys
    sys.stderr.write(f'[Supercharger] trace-compactor: compacted {original_len} → {new_len} chars\n')
PYEOF

exit 0
