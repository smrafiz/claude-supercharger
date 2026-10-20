#!/usr/bin/env python3
"""Replay real tool calls from local transcripts through the PreToolUse hooks.

Reports, per hook, every run that exited outside 0 and 2, timed out, or printed
JSON that does not parse: the runs `onFailure: "block"` would turn into denials.
Run it before giving a guard the `block` flag in lib/hooks.sh.

  python3 -I tools/guard-replay.py [--hook NAME]... [--per-tool N] [--json OUT]

Hooks run from this checkout, as hooks/hooks.json registers them, against an
isolated SUPERCHARGER_STATE, so the live ledger and counters are untouched.
"""
import argparse, collections, glob, json, os, random, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ap = argparse.ArgumentParser()
ap.add_argument('--hook', action='append', default=[], help='only this hook file (repeatable)')
ap.add_argument('--per-tool', type=int, default=400, help='max distinct calls per tool name')
ap.add_argument('--transcripts', type=int, default=150, help='newest N transcript files')
ap.add_argument('--json', help='write the full result here')
a = ap.parse_args()

# Corpus: distinct tool_use inputs from the newest transcripts.
files = sorted(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')), key=os.path.getmtime)
by, seen = collections.defaultdict(list), set()
for f in files[-a.transcripts:]:
    try:
        for line in open(f, errors='replace'):
            if '"tool_use"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            for c in (d.get('message') or {}).get('content') or []:
                if not isinstance(c, dict) or c.get('type') != 'tool_use':
                    continue
                k = json.dumps([c.get('name'), c.get('input')], sort_keys=True)[:4000]
                if k in seen:
                    continue
                seen.add(k)
                by[c.get('name') or ''].append({
                    'tool_name': c.get('name'), 'tool_input': c.get('input') or {},
                    'cwd': d.get('cwd') or REPO, 'hook_event_name': 'PreToolUse',
                    'session_id': '00000000-0000-0000-0000-000000000000'})
    except OSError:
        pass
random.seed(7)
calls = []
for v in by.values():
    random.shuffle(v)
    calls += v[:a.per_tool]

pairs = []
for g in json.load(open(os.path.join(REPO, 'hooks/hooks.json')))['hooks'].get('PreToolUse', []):
    for h in g['hooks']:
        cmd = h['command'].replace('"${CLAUDE_PLUGIN_ROOT}"', REPO).replace('${CLAUDE_PLUGIN_ROOT}', REPO)
        name = re.search(r'([\w-]+\.(?:sh|py))', cmd).group(1)
        if not a.hook or name in a.hook:
            pairs.append((g.get('matcher') or '.*', cmd, name))

st = tempfile.mkdtemp()
os.makedirs(os.path.join(st, 'scope'))
env = dict(os.environ, SUPERCHARGER_STATE=st, SUPERCHARGER_TELEMETRY='0')
env.pop('CLAUDE_CODE_SESSION_ID', None)
jobs = [(c, cmd, n) for c in calls for (m, cmd, n) in pairs if re.fullmatch(m, c['tool_name'] or '')]


def run(job):
    c, cmd, name = job
    cwd = c['cwd'] if os.path.isdir(c['cwd']) else REPO
    try:
        p = subprocess.run(['bash', '-c', cmd], input=json.dumps(c), capture_output=True,
                           text=True, timeout=30, env=env, cwd=cwd)
        rc, err, out = p.returncode, p.stderr[-300:], p.stdout.strip()
        if rc == 0 and out.startswith('{'):
            try:
                dec = (json.loads(out).get('hookSpecificOutput') or {}).get('permissionDecision')
                if dec in ('deny', 'ask'):
                    rc = 'json-' + dec   # a decision, not a failure: tallied, not reported
            except (ValueError, AttributeError):
                rc, err = 'BADJSON', out[:300]
    except subprocess.TimeoutExpired:
        rc, err = 'TIMEOUT', ''
    return name, c['tool_name'], rc, err, json.dumps(c['tool_input'])[:300]


tally, bad = collections.Counter(), []
with ThreadPoolExecutor(8) as ex:
    for name, tool, rc, err, inp in ex.map(run, jobs):
        tally[(name, str(rc))] += 1
        if rc not in (0, 2, 'json-deny', 'json-ask'):
            bad.append({'hook': name, 'tool': tool, 'rc': rc, 'err': err, 'input': inp})

hooks = sorted({n for n, _ in tally})
for n in hooks:
    runs = sum(v for (h, _), v in tally.items() if h == n)
    fails = sum(v for (h, rc), v in tally.items() if h == n and rc not in ('0', '2', 'json-deny', 'json-ask'))
    print('%-34s %6d runs  %s' % (n, runs, 'clean' if not fails else '%d FAIL' % fails))
print('%d calls, %d runs, %d failures' % (len(calls), len(jobs), len(bad)))
if a.json:
    json.dump({'tally': {'%s %s' % k: v for k, v in sorted(tally.items())}, 'bad': bad},
              open(a.json, 'w'), indent=1)
sys.exit(1 if bad else 0)
