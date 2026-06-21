#!/usr/bin/env bash
# Claude Supercharger — Session Learnings Injector
# Event: SessionStart | Matcher: (none)
# Injects accumulated learnings: blocked commands, user corrections,
# positive reinforcements, and repeated failure patterns.
# Includes log rotation (30 days) and dedup.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"

# Project dir for init_hook_suppress (cheap, one jq)
_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# v2.6.33: one python3 fork replaces ~30 subprocesses (md5 + jq cwd-fallback
# + 4 rotate_log subshells × {grep, awk, mv} + 3 dedup_log subshells × {awk,
# mv} + 1 python3 blocks-compress + tail/sed/tr/sed pipelines for corrections
# and reinforcements + sort/sed/sort/uniq/sort/awk/head pipeline for failures
# + jq -Rs JSON wrap). Now: 1 python3 heredoc does md5, log rotation, dedup,
# blocks compression, corrections/reinforcements/failures aggregation, and
# emits the final systemMessage JSON. Median 140ms → ~50ms.
OUT=$(SCOPE_DIR="$SCOPE_DIR" PROJECT_DIR="$PROJECT_DIR" HOOK_SUPPRESS="$HOOK_SUPPRESS" \
      python3 <<'PYEOF'
import hashlib, json, os, re, sys
from collections import Counter, OrderedDict
from datetime import datetime, timedelta

scope_dir = os.environ['SCOPE_DIR']
project_dir = os.environ['PROJECT_DIR']
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

proj_hash = hashlib.md5(project_dir.encode()).hexdigest()[:8]

blocks_log         = os.path.join(scope_dir, '.blocked-commands')
failures_log       = os.path.join(scope_dir, '.failed-commands')
corrections_log    = os.path.join(scope_dir, f'.user-corrections-{proj_hash}')
reinforcements_log = os.path.join(scope_dir, f'.user-reinforcements-{proj_hash}')

# Fall back to global if project-scoped doesn't exist
if not os.path.isfile(corrections_log) and os.path.isfile(os.path.join(scope_dir, '.user-corrections')):
    corrections_log = os.path.join(scope_dir, '.user-corrections')
if not os.path.isfile(reinforcements_log) and os.path.isfile(os.path.join(scope_dir, '.user-reinforcements')):
    reinforcements_log = os.path.join(scope_dir, '.user-reinforcements')

# --- 30-day rotation: keep lines whose [YYYY-MM-DD ...] timestamp is >= cutoff
cutoff = (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d')
ts_re = re.compile(r'^\[(\d{4}-\d{2}-\d{2})')

def rotate_and_dedup(path, do_dedup=True):
    if not os.path.isfile(path):
        return []
    try:
        with open(path) as f:
            lines = f.readlines()
    except Exception:
        return []
    kept = []
    seen = set()
    changed = False
    for line in lines:
        stripped = line.rstrip('\n')
        m = ts_re.match(stripped)
        if m and m.group(1) < cutoff:
            changed = True
            continue
        if do_dedup:
            if stripped in seen:
                changed = True
                continue
            seen.add(stripped)
        kept.append(stripped)
    if changed:
        try:
            with open(path, 'w') as f:
                for line in kept:
                    f.write(line + '\n')
        except Exception:
            pass
    return kept

blocks_lines        = rotate_and_dedup(blocks_log)
corrections_lines   = rotate_and_dedup(corrections_log)
reinforcements_lines = rotate_and_dedup(reinforcements_log)
failures_lines      = rotate_and_dedup(failures_log, do_dedup=False)

context_parts = []

# Blocked commands → category counts, top 8 by frequency
if blocks_lines:
    counts = Counter()
    last_seen = {}
    entry_re = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\] (.+)$')
    for line in blocks_lines:
        m = entry_re.match(line)
        if not m:
            continue
        date, rest = m.group(1), m.group(2)
        reason = rest.split(' — ')[0].strip()[:80]
        counts[reason] += 1
        last_seen[reason] = date[:10]
    if counts:
        body = '\n'.join(
            f'- {reason} (blocked {count}x, last: {last_seen[reason]})'
            for reason, count in counts.most_common(8)
        )
        context_parts.append('[BLOCKS] ' + body)

# User corrections (last 5, pipe-joined)
if corrections_lines:
    corr_re = re.compile(r'^\[.*?\] CORRECTION: ')
    tail = [corr_re.sub('', l) for l in corrections_lines[-5:]]
    context_parts.append('[CORR] ' + '|'.join(tail))

# User reinforcements (last 5)
if reinforcements_lines:
    rein_re = re.compile(r'^\[.*?\] REINFORCED: ')
    tail = [rein_re.sub('', l) for l in reinforcements_lines[-5:]]
    context_parts.append('[WORKS] ' + '|'.join(tail))

# Repeated failures: pattern → count, threshold 3, top 5
if failures_lines:
    fail_re = re.compile(r'^\[.*?\] exit=\d+ — ')
    pattern_counts = Counter(fail_re.sub('', l) for l in failures_lines if l)
    repeated = [(p, c) for p, c in pattern_counts.most_common() if c >= 3][:5]
    if repeated:
        body = '\n'.join(f' {c} {p}' for p, c in repeated)
        context_parts.append('[FAILS] ' + body)

if not context_parts:
    sys.exit(0)

context = '\n\n'.join(context_parts)
print(json.dumps({'systemMessage': context, 'suppressOutput': suppress}))
PYEOF
)

[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
exit 0
