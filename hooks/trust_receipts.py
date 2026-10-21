#!/usr/bin/env python3
"""trust-receipts.sh helper: reads the hook payload on stdin. See trust-receipts.sh."""
import glob, hashlib, json, os, re, shlex, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from lib_outbound_secret import _compile
except Exception:
    _compile = lambda raw: []

# Words in the last part of an MCP tool name that mean the call changes something
# outside this machine. A tool whose name starts with a read word is skipped, so
# `get_file_permissions` and `list_shared_drives` never count.
SEND = {'send', 'post', 'create', 'share', 'upload', 'publish', 'update', 'delete', 'trash',
        'reply', 'comment', 'write', 'push', 'merge', 'invite', 'move', 'copy', 'put', 'add',
        'remove', 'edit', 'submit', 'set', 'rename', 'archive', 'forward', 'schedule'}
READ = {'get', 'list', 'search', 'read', 'fetch', 'query', 'find', 'describe', 'view', 'export',
        'download', 'whoami', 'check', 'preview', 'resolve', 'count', 'lookup'}
# Argument keys that name where an MCP call went, most specific first.
DEST_KEYS = ('to', 'recipient', 'recipients', 'emailAddress', 'email', 'channel', 'channel_id',
             'repo', 'repository', 'fileId', 'url', 'parentId', 'title', 'name', 'fileName', 'path')
WRAPPERS = {'sudo', 'command', 'env', 'nohup', 'time', 'exec', 'xargs'}
_HEX = re.compile(r'[A-Fa-f0-9]{32,}')


def redact(s, pats):
    s = str(s)
    for p, _ in pats:
        s = p.sub('[REDACTED]', s)
    return _HEX.sub('[REDACTED]', s)[:160]


def segments(cmd):
    # Split on ; && || | and newlines OUTSIDE quotes: `git commit -m "x; git push"` is
    # one commit, not a push.
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=';&|\n')
    lex.whitespace, lex.whitespace_split, lex.commenters = ' \t\r', True, ''
    try:
        toks = list(lex)
    except ValueError:
        toks = None
    if toks is None:
        return [argv_of(s.split()) for s in re.split(r'&&|\|\||;|\||\n', cmd)]
    out, cur = [], []
    for t in toks:
        if t and set(t) <= set(';&|\n'):
            out.append(argv_of(cur)); cur = []
        else:
            cur.append(t)
    return out + [argv_of(cur)]


def argv_of(a):
    a = list(a)
    while a and (re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', a[0]) or a[0] in WRAPPERS):
        a = a[1:]
    return a


def positional(args):
    return [a for a in args if not a.startswith('-')]


def flag_value(args, *names):
    for i, a in enumerate(args):
        for n in names:
            if a == n and i + 1 < len(args):
                return args[i + 1]
            if a.startswith(n + '='):
                return a.split('=', 1)[1]
    return ''


def remote_target(a):
    # [user@]host:path or rsync://, but not a local path that happens to hold a colon
    return bool(re.match(r'^rsync://', a) or re.match(r'^(?:[^@/\s]+@)?[A-Za-z0-9.-]+:(?!//)', a))


def bash_receipts(cmd, cwd):
    out, repo = [], os.path.basename(cwd.rstrip('/\\')) or '?'
    for a in segments(cmd):
        seg = ' '.join(a)
        if not a:
            continue
        prog, args = os.path.basename(a[0]), a[1:]
        if '--dry-run' in args or (prog == 'git' and '-n' in args):
            continue
        if prog == 'git':
            i = 0
            while i < len(args) and args[i].startswith('-'):
                i += 2 if args[i] in ('-C', '-c', '--git-dir', '--work-tree') else 1
            if i < len(args) and args[i] == 'push':
                p = positional(args[i + 1:])
                out.append(('push', 'git push', ' '.join(p[:2]) or repo + ' (default remote)', seg))
        elif prog in ('docker', 'podman') and args[:1] == ['push']:
            p = positional(args[1:])
            out.append(('push', prog + ' push', p[0] if p else '?', seg))
        elif (prog in ('npm', 'pnpm', 'yarn', 'cargo', 'poetry', 'flit') and args[:1] == ['publish']) \
                or (prog == 'gem' and args[:1] == ['push']) or (prog == 'twine' and args[:1] == ['upload']):
            out.append(('publish', prog + ' ' + args[0], repo, seg))
        elif prog == 'gh' and len(args) >= 2:
            sub, act = args[0], args[1]
            writes = {'pr': ('create', 'merge', 'comment', 'close', 'review', 'edit', 'reopen'),
                      'issue': ('create', 'comment', 'close', 'edit', 'reopen', 'delete'),
                      'release': ('create', 'upload', 'delete', 'edit'),
                      'repo': ('create', 'delete', 'edit', 'rename'), 'gist': ('create', 'edit', 'delete')}
            api_write = sub == 'api' and (flag_value(args, '-X', '--method').upper() in ('POST', 'PUT', 'PATCH', 'DELETE')
                                         or any(x in args for x in ('-f', '-F', '--field', '--raw-field', '--input')))
            if act in writes.get(sub, ()) or api_write:
                dest = flag_value(args, '-R', '--repo') or (positional(args[1:])[0] if api_write and positional(args[1:]) else repo)
                kind = 'publish' if sub == 'release' else 'repo'
                if api_write:
                    what = 'gh api %s %s' % ((flag_value(args, '-X', '--method') or 'POST').upper(), dest)
                else:
                    p = positional(args[2:])
                    what = ('gh %s %s %s' % (sub, act, p[0] if p else '')).strip()
                out.append((kind, 'gh api' if api_write else 'gh %s %s' % (sub, act), dest, what))
        elif prog == 'curl':
            sends = any(x in args for x in ('-d', '-F', '-T', '--form', '--upload-file', '--json')) \
                or any(x.startswith(('--data', '-d', '-XP', '-XD')) for x in args) \
                or flag_value(args, '-X', '--request').upper() in ('POST', 'PUT', 'PATCH', 'DELETE')
            if sends:
                url = next((x for x in args if re.match(r'^https?://', x)), '')
                host = re.sub(r'^https?://(?:[^@/]*@)?([^/:?#]+).*', r'\1', url) if url else '?'
                out.append(('upload', 'curl', host, (flag_value(args, '-X', '--request') or 'POST').upper() + ' ' + host))
        elif prog == 'wget':
            if any(x.startswith(('--post-data', '--post-file', '--body-data', '--body-file')) for x in args) \
                    or flag_value(args, '--method').upper() in ('POST', 'PUT', 'PATCH', 'DELETE'):
                url = next((x for x in args if re.match(r'^https?://', x)), '')
                host = re.sub(r'^https?://(?:[^@/]*@)?([^/:?#]+).*', r'\1', url) if url else '?'
                out.append(('upload', 'wget', host, 'POST ' + host))
        elif prog in ('scp', 'rsync'):
            p = positional(args)
            if len(p) >= 2 and remote_target(p[-1]) and not remote_target(p[0]):
                host = re.sub(r'^(?:rsync://)?(?:[^@/]+@)?([^:/]+).*', r'\1', p[-1])
                out.append(('upload', prog, host, '%s %s -> %s' % (prog, os.path.basename(p[0].rstrip('/')), host)))
    return out


def mcp_receipt(tool, ti):
    parts = tool.split('__')
    if len(parts) < 3:
        return None
    server, name = '__'.join(parts[1:-1]), parts[-1]
    words = [w.lower() for w in re.findall(r'[A-Za-z][a-z0-9]*|[A-Z]+(?![a-z])', name)]
    if not words or words[0] in READ or not SEND & set(words):
        return None
    server = re.sub(r'^(claude_ai_|plugin_)', '', server).replace('_', ' ')
    dest = ''
    for k in DEST_KEYS:
        v = ti.get(k) if isinstance(ti, dict) else None
        if v:
            v = v[:3] if isinstance(v, list) else [v]
            # an address keeps only its domain: where it went, not who
            dest = ', '.join(re.sub(r'^[^@\s]+@', '@', str(x)) for x in v)
            break
    return ('send', tool, server, (name + (' ' + dest if dest else '')))


def artifact_receipt(tool, ti, resp):
    act = (ti.get('action') or 'publish') if isinstance(ti, dict) else 'publish'
    url = ti.get('url') or ''
    if not url:
        m = re.search(r'https://claude\.ai/(?:code/)?artifact/[A-Za-z0-9_-]+', json.dumps(resp)[:20000])
        url = m.group(0) if m else 'new artifact'
    if tool == 'Artifact' and act in ('publish', 'delete'):
        what = 'delete' if act == 'delete' else 'publish ' + (os.path.basename(ti.get('file_path') or '')
            or ('asset' if ti.get('asset') else ti.get('title') or ''))
        return ('publish', tool, url, what.strip())
    if tool == 'ArtifactData' and act in ('set', 'update', 'delete', 'batch', 'str_replace'):
        return ('send', tool, url, '%s %s' % (act, ti.get('collection') or ''))
    if tool == 'ArtifactComments' and act in ('reply', 'resolve'):
        return ('send', tool, url, act + ' comment')
    return None


def main():
    try:
        d = json.load(sys.stdin)
    except ValueError:
        return
    base = os.environ['RECEIPTS']
    pats = _compile(os.environ.get('OUTBOUND_SECRET_PATTERNS', ''))
    sid = re.sub(r'[^0-9A-Za-z-]', '', d.get('session_id') or '')[:64]
    cwd = d.get('cwd') or ''
    event = d.get('hook_event_name') or ''

    if event == 'PostToolUse':
        tool, ti, resp = d.get('tool_name') or '', d.get('tool_input') or {}, d.get('tool_response')
        if tool == 'Bash':
            recs = bash_receipts(ti.get('command') or '', cwd)
        elif tool.startswith('mcp__'):
            recs = [r for r in [mcp_receipt(tool, ti)] if r]
        elif tool.startswith('Artifact'):
            recs = [r for r in [artifact_receipt(tool, ti, resp)] if r]
        else:
            recs = []
        if not recs:
            return
        os.makedirs(base, exist_ok=True)
        now = int(time.time())
        with open(os.path.join(base, time.strftime('%Y-%m', time.localtime(now)) + '.jsonl'), 'a') as f:
            for kind, t, dest, what in recs:
                f.write(json.dumps({'ts': now, 'session': sid, 'cwd': cwd, 'kind': kind, 'tool': redact(t, pats),
                                    'dest': redact(dest, pats), 'what': redact(what, pats)}) + '\n')
        return

    if event != 'SessionStart' or not cwd:
        return
    seen = os.path.join(base, '.seen-' + hashlib.sha1(cwd.encode()).hexdigest()[:12])
    try:
        since = int(open(seen).read().strip() or 0)
    except (OSError, ValueError):
        since = 0
    now = int(time.time())
    since = max(since, now - 7 * 86400)
    recs = []
    for p in sorted(glob.glob(os.path.join(base, '*.jsonl')))[-2:]:
        try:
            lines = open(p).read().splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get('cwd') == cwd and r.get('session') != sid and r.get('ts', 0) > since:
                recs.append(r)
    os.makedirs(base, exist_ok=True)
    with open(seen + '.tmp', 'w') as f:
        f.write(str(now))
    os.replace(seen + '.tmp', seen)
    if not recs:
        return
    kinds = {}
    for r in recs:
        kinds[r.get('kind', '?')] = kinds.get(r.get('kind', '?'), 0) + 1
    last = recs[-1]
    msg = ('[RECEIPTS] Since the last session here, %d outward action(s): %s (latest: %s to %s). '
           'List them: /sc-receipts' % (len(recs), ', '.join('%d %s' % (n, k) for k, n in sorted(kinds.items())),
                                         last.get('what', '?'), last.get('dest', '?')))
    print(json.dumps({'systemMessage': msg,
                      'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': msg}}))


main()
