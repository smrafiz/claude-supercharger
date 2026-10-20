#!/usr/bin/env python3
"""unfinished-work.sh helper: reads the hook payload on stdin. See unfinished-work.sh."""
import glob, json, os, re, sys, time

try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
scope = os.environ['SCOPE']
sid = re.sub(r'[^0-9A-Za-z-]', '', d.get('session_id') or '')[:64]
cwd = d.get('cwd') or (d.get('workspace') or {}).get('current_dir') or ''
event = d.get('hook_event_name') or ''
if not sid:
    sys.exit(0)
snap = os.path.join(scope, '.inflight-%s.json' % sid)

if event == 'Stop':
    tasks = [t for t in (d.get('background_tasks') or []) if isinstance(t, dict)]
    crons = [c for c in (d.get('session_crons') or []) if isinstance(c, dict)]
    if not tasks and not crons:
        try:
            os.remove(snap)
        except OSError:
            pass
        sys.exit(0)
    keep = lambda o, ks: {k: str(o.get(k))[:160] for k in ks if o.get(k) not in (None, '')}
    rec = {'session_id': sid, 'cwd': cwd, 'time': int(time.time()),
           'tasks': [keep(t, ('type', 'status', 'description', 'command', 'name')) for t in tasks[:20]],
           'crons': [keep(c, ('schedule', 'recurring', 'prompt')) for c in crons[:20]]}
    os.makedirs(scope, exist_ok=True)
    tmp = snap + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(rec, f)
    os.replace(tmp, snap)   # whole file or none: a reader never sees half a snapshot
    sys.exit(0)

if event != 'SessionStart':
    sys.exit(0)
lines, now = [], time.time()
for p in sorted(glob.glob(os.path.join(scope, '.inflight-*.json'))):
    try:
        rec = json.load(open(p))
    except (OSError, ValueError):
        continue
    if rec.get('session_id') == sid and d.get('source') not in ('resume', 'compact'):
        continue
    if rec.get('cwd') != cwd or now - rec.get('time', 0) > 7 * 86400:
        continue
    when = time.strftime('%Y-%m-%d %H:%M', time.localtime(rec.get('time', 0)))
    for t in rec.get('tasks', []):
        lines.append('- %s (%s, %s): %s' % (t.get('type', 'task'), t.get('status', '?'), when,
                     t.get('description') or t.get('command') or t.get('name') or '?'))
    for c in rec.get('crons', []):
        lines.append('- scheduled %s (%s): %s' % (c.get('schedule', '?'), when, c.get('prompt', '?')))
    try:
        os.replace(p, p + '.seen')   # once: the next start does not repeat it
    except OSError:
        pass
if lines:
    msg = ('[UNFINISHED] An earlier session here ended with work still running; no later turn '
           'saw it finish, so check whether it completed:\n' + '\n'.join(lines[:12]))
    print(json.dumps({'systemMessage': msg,
                      'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': msg}}))
