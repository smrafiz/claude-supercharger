# Claude Supercharger — outbound secret scan (shared)
# Imported by mcp-egress-guard.sh (MCP tool arguments) and webfetch-egress-guard.sh
# (WebFetch url/prompt). Denies a call that would carry a credential OUT of the
# session — the "GhostSplice" shape, where a malicious MCP server's output tells
# the agent to pass a key back as a tool argument.
#
# The regexes are NOT defined here. They come from hooks/lib-secret-patterns.sh,
# which the calling hook sources and hands over newline-joined in OUTBOUND_SECRET_PATTERNS
# (one list for every channel, or the channels drift on what counts as a secret).
# That file is POSIX ERE for grep -E; Python's re reads `[[:space:]]` as a set of
# literal characters, so POSIX classes are translated mechanically below.
import json, os, re, urllib.parse

_POSIX = {'[:space:]': r'\s', '[:digit:]': '0-9', '[:alnum:]': 'A-Za-z0-9',
          '[:alpha:]': 'A-Za-z', '[:upper:]': 'A-Z', '[:lower:]': 'a-z',
          '[:xdigit:]': '0-9A-Fa-f'}

# Labels for the deny reason: keyed on a fragment of the PATTERN text, never on
# the matched value, so the reason cannot echo the secret. First hit wins, so the
# more specific fragment comes first. An unlabelled pattern still blocks.
_LABELS = (
    ('AKIA', 'AWS access key ID'), ('ASIA', 'AWS access key ID'),
    ('[Aa][Ww][Ss]_', 'AWS secret access key'), ('github_pat', 'GitHub token'),
    ('gh[oprsu]', 'GitHub token'), ('ya29', 'Google OAuth token'),
    ('_token"', 'OAuth token'), ('Bearer', 'bearer token'),
    ('PRIVATE KEY', 'private key'), ('"private_key"', 'private key'),
    ('://', 'URL with embedded credentials'), ('_live_', 'Stripe key'),
    ('npm_', 'npm token'), ('eyJ', 'JWT'), ('sk-ant', 'Anthropic API key'),
    ('sk-', 'OpenAI-style API key'), ('x(ox', 'Slack token'),
    ('hf_', 'HuggingFace token'), ('ops_', 'secrets-manager token'),
    ('AIza', 'Google API key'), ('AccountKey', 'Azure storage key'),
    ('SK[0-9a-f]', 'Twilio key'), ('SG\\.', 'SendGrid key'),
    ('0x[', 'wallet private key'), ('prv', 'wallet private key'),
    ('[5KL]', 'wallet private key'), ('[Aa][Pp][Ii]', 'API key / secret assignment'),
)


def _compile(raw):
    out = []
    for p in (raw or '').splitlines():
        p = p.strip()
        if not p:
            continue
        label = next((l for frag, l in _LABELS if frag in p), 'credential')
        for k, v in _POSIX.items():
            p = p.replace(k, v)
        try:
            out.append((re.compile(p), label))
        except re.error:
            continue
    return out


def strings(x, out=None):
    """Every string value in x, recursively. A dict string value is ALSO yielded
    as `key=value`, so a bare secret passed under an `api_key` argument meets the
    generic key=value pattern the same way it would in a config file."""
    if out is None:
        out = []
    if isinstance(x, str):
        out.append(x)
    elif isinstance(x, dict):
        for k, v in x.items():
            if isinstance(v, str):
                out.append('%s=%s' % (k, v))
            strings(v, out)
    elif isinstance(x, list):
        for v in x:
            strings(v, out)
    return out


def find(values):
    """Label of the first secret pattern found in values (each also checked after
    up to two rounds of percent-decoding — the tool decodes a URL before sending
    it), else ''."""
    pats = _compile(os.environ.get('OUTBOUND_SECRET_PATTERNS', ''))
    if not pats:
        return ''
    for s in values:
        cands = [s]
        d = s
        for _ in range(2):
            d2 = urllib.parse.unquote(d)
            if d2 == d:
                break
            cands.append(d2)
            d = d2
        for c in cands:
            for rx, label in pats:
                if rx.search(c):
                    return label
    return ''


_ALLOWED = set('abcdefghijklmnopqrstuvwxyz0123456789_.-')


def _key(s):
    # Same normalisation as tools/trust-mcp.sh + elicitation-guard, then with the
    # separators dropped: a tool name spells server `claude.ai Foo` as
    # `claude_ai_Foo`, so `.`/`_`/`-` must not decide the comparison.
    k = ''.join(c for c in str(s).strip().lower() if c in _ALLOWED)
    return re.sub(r'[._-]', '', k)


def server_trusted(server, cwd):
    """Reuses the Elicitation trust list: a server trusted to ASK for a credential
    (trustedElicitationServers in .supercharger.json, or /sc-trust-mcp) is trusted
    to RECEIVE one. Read only after a hit, so a clean call pays nothing."""
    want = _key(server)
    if not want:
        return False
    names = []
    d = cwd or os.getcwd()
    while d:
        try:
            with open(os.path.join(d, '.supercharger.json'), encoding='utf-8') as f:
                names += json.load(f).get('trustedElicitationServers') or []
            break
        except Exception:
            pass
        if os.path.exists(os.path.join(d, '.git')):
            break
        parent = os.path.dirname(d)
        d = '' if parent == d else parent
    home = os.environ.get('HOME') or os.path.expanduser('~')
    for root in (os.environ.get('SUPERCHARGER_STATE'), os.environ.get('CLAUDE_PLUGIN_DATA'),
                 os.path.join(home, '.claude', 'supercharger')):
        if not root:
            continue
        try:
            with open(os.path.join(root, 'scope', '.trusted-elicitation-servers'), encoding='utf-8') as f:
                names += f.read().splitlines()
        except Exception:
            pass
    return any(_key(n) == want for n in names if isinstance(n, str))
