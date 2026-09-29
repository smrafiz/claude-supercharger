"""Engine for tools/fp-triage.sh — see that file for what and why."""
import collections, glob, json, os, re, shutil, subprocess, sys, tempfile

REPO = os.environ.get('FPT_REPO', '')
LEDGER = os.environ.get('FPT_LEDGER', '')
PROJECTS = os.environ.get('FPT_PROJECTS', '')
EXAMPLES = int(os.environ.get('FPT_EXAMPLES', '3'))
GUARDS = ['safety.sh', 'git-safety.sh', 'harness-tamper-guard.sh']
# Ledger writers that are not Bash command guards: nothing to replay.
NOT_BASH = ('completion claimed', 'secret in staged commit', 'ambiguous secret pattern',
            'credentials — secret in', 'skills —', 'sendmessage —', 'ALLOWED by allowPatterns')

SECRETS = []
for p in (open(os.environ['FPT_PATTERNS']).read().splitlines() if os.environ.get('FPT_PATTERNS') else []):
    try: SECRETS.append(re.compile(p))
    except re.error: pass


def mask(s):
    for r in SECRETS:
        s = r.sub('[REDACTED]', s)
    return s


def parse_ledger():
    out = []
    for line in open(LEDGER, errors='replace'):
        m = re.match(r'\[[^\]]*\] (.*)', line.rstrip('\n'))
        if not m or ' — ' not in m.group(1): continue
        body = m.group(1)
        if body.startswith(NOT_BASH) or any(k in body for k in NOT_BASH): continue
        reason, cmd = body.split(' — ', 1)[0], body.rsplit(' — ', 1)[1]
        out.append((reason, cmd))
    return out


def transcript_commands():
    """Full Bash commands from local transcripts, keyed by their flattened 60-char prefix."""
    idx = {}
    for f in glob.glob(os.path.join(PROJECTS, '*', '*.jsonl')):
        for line in open(f, errors='ignore'):
            if '"Bash"' not in line: continue
            try: d = json.loads(line)
            except ValueError: continue
            for b in (d.get('message') or {}).get('content') or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use' and b.get('name') == 'Bash':
                    c = (b.get('input') or {}).get('command') or ''
                    idx.setdefault(_key(c), c)
    return idx


def _key(c):
    return re.sub(r'\s+', ' ', c).strip()[:60]


INTERP = r'(?:bash|sh|zsh|dash|python3?|node|ruby|perl|php|deno|bun)'
# A quoted argument right after these runs as code (`sh -cm '...'` clusters -c).
EXEC_BEFORE = re.compile(r'(?:\s-[A-Za-z]*[ce][A-Za-z]*|\beval|\bexec|\bssh\s+\S+|' + INTERP + r')\s*$')


def blank_text(cmd):
    """Blank what is data (quoted strings, non-interpreter heredoc bodies); keep what executes."""
    lines = cmd.split('\n'); out = []; kept = []; i = 0
    while i < len(lines):
        ln = lines[i]; out.append(ln)
        m = re.search(r'<<-?\s*([\'"]?)(\w+)\1', ln)
        if m:
            execs = re.search(r'(^|[\s;&|(])' + INTERP + r'(\s[^<]*)?<<', ln) is not None
            j = i + 1; body = []
            while j < len(lines) and lines[j].strip() != m.group(2):
                body.append(lines[j]); j += 1
            if execs:
                # Interpreter code executes: set it aside so the quote pass below
                # cannot blank a path or command inside it.
                kept.append('\n'.join(body)); out.append(f'\x00{len(kept) - 1}\x00')
            else:
                out.extend('x' for _ in body)
            i = j; continue
        i += 1
    s = '\n'.join(out)
    res = []; pos = 0
    for q in re.finditer(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"", s):
        res.append(s[pos:q.start()])
        before = s[max(0, q.start() - 40):q.start()]
        res.append(q.group(0) if EXEC_BEFORE.search(before) else q.group(0)[0] + 'x' + q.group(0)[0])
        pos = q.end()
    res.append(s[pos:])
    return re.sub(r'\x00(\d+)\x00', lambda m: kept[int(m.group(1))], ''.join(res))


def blocked(cmd, state):
    for g in GUARDS:
        try:
            r = subprocess.run(['bash', os.path.join(REPO, 'hooks', g)],
                               input=json.dumps({'tool_name': 'Bash', 'tool_input': {'command': cmd},
                                                 'session_id': 'fp-triage', 'cwd': state}),
                               capture_output=True, text=True, timeout=20,
                               env={**os.environ, 'HOME': state, 'SUPERCHARGER_STATE': state + '/sc',
                                    'SUPERCHARGER_NO_TELEMETRY': '1'})
        except subprocess.TimeoutExpired:
            return 'HANG'
        if r.returncode == 2 or '"deny"' in r.stdout:
            return g
    return ''


def main():
    entries = parse_ledger()
    if not entries:
        print('fp-triage: no Bash guard entries in the ledger'); return
    idx = transcript_commands()
    state = tempfile.mkdtemp(); os.makedirs(state + '/sc/scope')
    rows = collections.defaultdict(lambda: collections.defaultdict(list))
    seen = {}
    try:
        for n, (reason, text) in enumerate(entries, 1):
            full = idx.get(_key(text.split('[REDACTED]')[0])) if len(text) >= 60 else None
            cmd = full or text
            if cmd not in seen:
                now = blocked(cmd, state)
                if now == 'HANG': verdict = 'HANG'
                elif not now: verdict = 'fixed'
                else: verdict = 'text-only' if not blocked(blank_text(cmd), state) else 'real'
                seen[cmd] = verdict
                print(f'\r  {n}/{len(entries)}', end='', file=sys.stderr, flush=True)
            rows[reason][seen[cmd]].append(cmd)
    finally:
        shutil.rmtree(state, ignore_errors=True)
    print(file=sys.stderr)

    tot = collections.Counter(v for r in rows.values() for v, c in r.items() for _ in c)
    print(f'Block ledger: {sum(tot.values())} Bash-guard entries, {len(seen)} distinct commands')
    print(f'  fixed since: {tot["fixed"]}   text-only (likely FP): {tot["text-only"]}   '
          f'still blocks on a command: {tot["real"]}   HANG: {tot["HANG"]}\n')
    order = sorted(rows, key=lambda r: (-len(rows[r]['HANG']), -len(rows[r]['text-only']), r))
    for reason in order:
        v = rows[reason]
        if not v['text-only'] and not v['HANG']: continue
        print(f'{len(v["text-only"]):4} text-only / {sum(len(x) for x in v.values()):4} total  {reason[:110]}')
        for c in (v['HANG'] + v['text-only'])[:EXAMPLES]:
            print('       ', mask(re.sub(r'\s+', ' ', c))[:160])
    quiet = [r for r in rows if not rows[r]['text-only'] and not rows[r]['HANG']]
    if quiet:
        print(f'\n{len(quiet)} rule(s) with no text-only blocks (fixed or real).')


if __name__ == '__main__':
    main()
