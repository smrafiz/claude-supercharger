#!/usr/bin/env python3
"""List Trust Receipts: outward actions recorded by hooks/trust-receipts.sh.

Usage: receipts.py [today|session|7d|<N>d|all] [--here]
  today    since local midnight (default)
  session  this session only (CLAUDE_CODE_SESSION_ID)
  <N>d     the last N days
  --here   only this project (the current directory)
"""
import glob, json, os, re, sys, time

args = [a for a in sys.argv[1:] if a != '--here']
here = '--here' in sys.argv[1:]
span = (args[0] if args else 'today').lower()
state = (os.environ.get('SUPERCHARGER_STATE') or os.environ.get('CLAUDE_PLUGIN_DATA')
         or os.path.join(os.environ.get('HOME') or os.path.expanduser('~'), '.claude', 'supercharger'))
now = time.time()
sid = os.environ.get('CLAUDE_CODE_SESSION_ID', '')
if span == 'today':
    since = time.mktime(time.localtime(now)[:3] + (0, 0, 0, 0, 0, -1))
elif span == 'all':
    since = 0
elif re.fullmatch(r'\d+d', span):
    since = now - int(span[:-1]) * 86400
elif span == 'session':
    since = 0
    if not sid:
        sys.exit('No session id in CLAUDE_CODE_SESSION_ID; use today or 7d.')
else:
    sys.exit(__doc__.strip())

rows = []
for p in sorted(glob.glob(os.path.join(state, 'receipts', '*.jsonl'))):
    try:
        lines = open(p, encoding='utf-8').read().splitlines()
    except OSError:
        continue
    for line in lines:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get('ts', 0) < since or (span == 'session' and r.get('session') != sid):
            continue
        if here and r.get('cwd') != os.getcwd():
            continue
        rows.append(r)

if not rows:
    print('No outward actions recorded (%s%s).' % (span, ', this project' if here else ''))
    sys.exit(0)
cell = lambda s: str(s).replace('|', '/').replace('\n', ' ')[:80]
kinds = {}
for r in rows:
    kinds[r.get('kind')] = kinds.get(r.get('kind'), 0) + 1
print('%d outward action(s), %s: %s\n' % (len(rows), span,
      ', '.join('%d %s' % (n, k) for k, n in sorted(kinds.items()))))
print('| When | Kind | Project | Destination | What |')
print('|---|---|---|---|---|')
for r in rows:
    print('| %s | %s | %s | %s | %s |' % (time.strftime('%m-%d %H:%M', time.localtime(r.get('ts', 0))), r.get('kind', '?'),
          cell(os.path.basename((r.get('cwd') or '?').rstrip('/\\'))), cell(r.get('dest', '?')), cell(r.get('what', '?'))))
