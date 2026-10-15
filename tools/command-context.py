#!/usr/bin/env python3
"""Live context for /sc-status, /sc-why and /sc-perf, injected with `!` when the
command loads, so the agent formats facts instead of spending a dozen tool calls
re-reading scope files.

  command-context.py status|why|perf

Rules for anything a slash command runs through `!` (measured 2026-10-12):
  - a non-zero exit aborts the WHOLE command with no reply -> this always exits 0;
  - in the default permission mode a command not covered by allowed-tools aborts it
    silently -> each command lists exactly this invocation in allowed-tools;
  - no $ARGUMENTS reach this line: command arguments would land in a shell line.
Every value is read-only and missing data prints as '—'.
"""
import glob, json, os, re, subprocess, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hooks'))
try:
    from lib_poison_patterns import msys_path   # Git Bash's /c/Users/x -> C:\\Users\\x
except Exception:
    def msys_path(x):
        return x
# HOME, not '~': native Windows python expands '~' from USERPROFILE.
HOME = msys_path(os.environ.get('HOME')) or os.path.expanduser('~')
# Same resolution as hooks/lib-paths.sh: a plugin install keeps its state in
# CLAUDE_PLUGIN_DATA, so reading only ~/.claude/supercharger showed an empty status.
SC = (msys_path(os.environ.get('SUPERCHARGER_STATE') or os.environ.get('CLAUDE_PLUGIN_DATA') or '')
      or os.path.join(HOME, '.claude', 'supercharger'))
SCOPE = os.path.join(SC, 'scope')
NA = '—'


def read(p, default=NA):
    try:
        with open(p, encoding='utf-8', errors='replace') as f:
            return f.read().strip() or default
    except Exception:
        return default


def tail(p, n):
    try:
        with open(p, encoding='utf-8', errors='replace') as f:
            return [l.rstrip('\n') for l in f.readlines()[-n:]]
    except Exception:
        return []


def newest(pattern):
    fs = glob.glob(pattern)
    return max(fs, key=os.path.getmtime) if fs else None


def ago(p):
    try:
        s = int(time.time() - os.path.getmtime(p))
    except Exception:
        return NA
    return '%ds ago' % s if s < 60 else '%dm ago' % (s // 60) if s < 3600 else '%dh ago' % (s // 3600) if s < 86400 else '%dd ago' % (s // 86400)


def session():
    """This session's transcript: the newest one in THIS cwd's project dir (never
    the machine-newest, which is another project under concurrent sessions)."""
    enc = re.sub(r'[^A-Za-z0-9-]', '-', os.getcwd())   # CC's project-dir name (C:\\x -> C--x)
    sid = re.sub(r'[^A-Za-z0-9_-]', '', os.environ.get('CLAUDE_CODE_SESSION_ID', ''))
    t = os.path.join(HOME, '.claude', 'projects', enc, sid + '.jsonl') if sid else ''
    if not (t and os.path.exists(t)):
        t = newest(os.path.join(HOME, '.claude', 'projects', enc, '*.jsonl'))
        sid = os.path.basename(t)[:-6] if t else sid
    return enc, sid, t


PRICES = {'opus': (5.0, 6.25, 0.5, 25.0), 'sonnet': (3.0, 3.75, 0.3, 15.0),
          'haiku': (0.8, 1.0, 0.08, 4.0), 'fable': (10.0, 12.5, 1.0, 50.0)}


def transcript_cost(path):
    t = 0.0
    try:
        for ln in open(path, encoding='utf-8', errors='replace'):
            if '"usage"' not in ln:
                continue
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            if d.get('type') != 'assistant':
                continue
            m = d.get('message') or {}
            u = m.get('usage') or {}
            mod = (m.get('model') or '').lower()
            k = 'opus' if 'opus' in mod else 'fable' if ('fable' in mod or 'mythos' in mod) else 'haiku' if 'haiku' in mod else 'sonnet'
            ip, cw, cr, op = PRICES[k]
            t += (u.get('input_tokens', 0) * ip + u.get('cache_creation_input_tokens', 0) * cw
                  + u.get('cache_read_input_tokens', 0) * cr + u.get('output_tokens', 0) * op) / 1e6
    except Exception:
        return NA
    return '$%.2f' % t


def unscanned_line():
    """Payloads a non-blocking scanner gave up on (stdin timeout). lib-stdin.sh appends
    '<epoch> <hook>' per miss; silence from a scanner otherwise reads as a clean scan."""
    rows = tail(os.path.join(SCOPE, '.unscanned'), 200)
    if not rows:
        return 'unscanned_payloads: 0'
    last = rows[-1].split()
    return 'unscanned_payloads: %d (last: %s)' % (len(rows), last[1] if len(last) > 1 else NA)


def status():
    enc, sid, tr = session()
    cfg = {}
    try:
        cfg = json.load(open('.supercharger.json'))
    except Exception:
        pass
    hist = tail(os.path.join(SCOPE, '.tool-history-' + sid), 10) if sid else []
    def failed(l):
        try:
            return json.loads(l).get('success') is False
        except ValueError:
            return 'fail' in l.lower()
    fails = sum(1 for l in hist if failed(l))
    conf = 1.0 - 0.2 * sum(1 for l in hist[-5:] if failed(l))
    if sid and os.path.exists(os.path.join(SCOPE, '.repetition-flag-' + sid)):
        conf -= 0.2
    mem_dir = os.path.join(HOME, '.claude', 'projects', enc, 'memory')
    mem = [f for f in glob.glob(os.path.join(mem_dir, '*.md')) if not f.endswith('MEMORY.md')]
    lessons = tail('.claude/supercharger/lessons.jsonl', 3)
    try:
        n_less = sum(1 for _ in open('.claude/supercharger/lessons.jsonl'))
    except Exception:
        n_less = 0
    sub = {}
    for f in glob.glob(os.path.join(SCOPE, '.subagent-costs-*.jsonl')):
        for l in tail(f, 100000):
            try:
                d = json.loads(l)
            except ValueError:
                continue
            k = d.get('agent_id') or id(d)
            if float(d.get('cost_usd') or 0) >= sub.get(k, (0, ''))[0]:
                sub[k] = (float(d.get('cost_usd') or 0), d.get('agent_name') or '?')
    by = {}
    for c, n in sub.values():
        by[n] = by.get(n, 0) + c
    top = sorted(by.items(), key=lambda x: -x[1])[:3]
    try:
        budget = subprocess.run(['bash', os.path.join(SC, 'tools', 'input-budget.sh'), '--line'],
                                capture_output=True, text=True, timeout=10).stdout.strip() or NA
    except Exception:
        budget = NA
    restored = os.path.join(SCOPE, '.memory-restored-' + sid) if sid else ''
    audit = os.path.join(SC, 'audit', time.strftime('%Y-%m-%d', time.gmtime()) + '.jsonl')
    try:
        n_audit = sum(1 for _ in open(audit))
    except Exception:
        n_audit = 0
    out = [
        'session_id: ' + (sid or NA),
        'project: ' + os.path.basename(os.getcwd()),
        'role: ' + str(cfg.get('role') or NA),
        'tier: ' + read(os.path.join(SCOPE, '.economy-tier'), 'standard'),
        'mcp_profile: ' + read(os.path.join(SCOPE, '.mcp-profile')),
        'hook_profile: ' + read(os.path.join(SCOPE, '.profile'), 'standard'),
        'input_budget: ' + budget,
        'session_cost: ' + (transcript_cost(tr) if tr else NA) + ' (from the transcript)',
        'budget_usd: ' + str(cfg.get('budget') or NA),
        'subagents_all_sessions: %d runs; top: %s' % (len(sub), ', '.join('%s $%.2f' % t for t in top) or NA),
        'tools_last10: %d ok / %d fail' % (len(hist) - fails, fails) if hist else 'tools_last10: ' + NA,
        'confidence: %.2f' % max(0.0, min(1.0, conf)),
        'memory: %d entries, updated %s' % (len(mem), ago(max(mem, key=os.path.getmtime))) if mem else 'memory: ' + NA,
        'lessons: %d' % n_less,
    ] + ['  lesson: ' + (json.loads(l).get('lesson', '')[:80] if l.startswith('{') else l[:80]) for l in reversed(lessons)] + [
        'disabled_hooks: ' + (read(os.path.join(SCOPE, '.disabled-hooks'), 'none').replace('\n', ', ')),
        'last_compact: ' + (ago(restored) if restored and os.path.exists(restored) else 'this session'),
        'audit_events_today: %d' % n_audit,
        unscanned_line(),
    ] + ['  block: ' + l[:160] for l in tail(os.path.join(SCOPE, '.blocked-commands'), 3)]
    print('\n'.join(out))


def why():
    srcs = [('scan-alert', newest(os.path.join(SCOPE, '.scan-alert-*')), 5),
            ('blocked-commands', os.path.join(SCOPE, '.blocked-commands'), 3),
            ('user-corrections', newest(os.path.join(SCOPE, '.user-corrections*')), 1),
            ('failed-commands', newest(os.path.join(SCOPE, '.failed-commands-*')), 1),
            ('subagent-report', newest(os.path.join(SCOPE, '.subagent-report-*')), 3),
            ('prompt-notes', newest(os.path.join(SCOPE, '.prompt-notes-*')), 3),
            ('detect-overruns', os.path.join(SCOPE, '.detect-overruns'), 1)]
    shown = 0
    for name, p, n in srcs:
        if p and os.path.exists(p):
            lines = tail(p, n)
            if lines:
                shown += 1
                print('[%s] %s (%s)' % (name, ago(p), p))
                for l in lines:
                    print('  ' + l[:300])
    if not shown:
        print('No recent hook activity recorded.')


def perf():
    try:
        r = subprocess.run(['bash', os.path.join(SC, 'tools', 'hook-perf.sh'), '--days', '7'],
                           capture_output=True, text=True, timeout=20)
        print((r.stdout or r.stderr).strip()[:4000] or NA)
    except Exception as e:
        print('hook-perf.sh unavailable: %s' % e)


if __name__ == '__main__':
    try:
        {'status': status, 'why': why, 'perf': perf}.get(sys.argv[1] if len(sys.argv) > 1 else '', lambda: print(NA))()
    except Exception as e:  # never abort the slash command
        print('context unavailable: %s' % e)
    sys.exit(0)
