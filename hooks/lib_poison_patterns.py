"""Claude Supercharger — shared instruction-poisoning patterns.

NAMING: python libs here use underscores (lib_poison_patterns.py) while shell
libs use hyphens (lib-suppress.sh). That is not drift — a hyphen makes a module
un-importable, so `import lib_poison_patterns` requires it. Do not "fix" it.

Loaded by BOTH scanners that inspect agent-authored instruction files:

  skill-poisoning-scanner.sh   PreToolUse:Skill    — ~/.claude/skills|commands|plugins
  agent-poisoning-scanner.sh   PreToolUse:Agent    — ~/.claude/agents
  workflow-guard.sh            PreToolUse:Workflow — the script text + any agentType it names

Why a shared module rather than a copied list. Sibling guards drifting on their
pattern lists is this project's signature security-hook bug class (v2.8.1-.11:
the same guard on Bash and Write disagreeing about what it protected). Two
scanners looking for "the same" injection markers WILL diverge the first time
one of them is tightened alone. Centralising them is the same call already made
for secret regexes (lib-secret-patterns.sh) and code-security patterns
(lib_code_patterns.py) — add a pattern HERE, never in one scanner.

Consumers must degrade gracefully if this file is missing: import it inside a
try/except and fall back to a local copy. A hook that dies because an asset was
not deployed is worse than a hook that scans with the built-in set (v2.17.3
shipped exactly that failure — hooks/*.py was not copied by the installer).

Severity contract, relied on by both callers:
  CRITICAL -> deny (exit 2). No legitimate reason for this in an instruction file.
  HIGH/MEDIUM -> warn only. Real files trip these (a skill may legitimately
  mention ~/.aws/credentials or call subprocess), and a guard that blocks
  ordinary work gets the whole layer switched off.
"""

import hashlib
import os
import re

I = re.IGNORECASE

# (label, compiled regex, severity) — ordered by severity.
# All patterns are IGNORECASE: they were case-sensitive until v2.7.14, so
# "IGNORE PREVIOUS INSTRUCTIONS" / "CURL ... | SH" evaded every check.
PATTERNS = [
    # 2026-10-27: CRITICAL only when the decoded text is RUN on the same line; a decode
    # to a file or the terminal (`gh api ... | base64 -d > f`) is ordinary and warns HIGH.
    ('base64 decode execution',       re.compile(r'(?:base64\s+(?:-d|--decode)|atob\(|b64decode)[^\n]*(?:\|\s*(?:sudo\s+)?(?:ba|z|da|k)?sh\b|\|\s*(?:python3?|node|perl|ruby)\b|\beval\b|\bexec\b)|(?:\beval\b|\bexec\b|\b(?:ba)?sh\s+-c\b)[^\n]*(?:base64\s+(?:-d|--decode)|atob\(|b64decode)', I),                    'CRITICAL'),
    ('base64 decode', re.compile(r'(?:base64\s+(?:-d|--decode)|atob\(|b64decode)', I), 'HIGH'),
    ('hidden eval/exec',              re.compile(r'\beval\b.*\$|exec\s*\(', I),                                       'CRITICAL'),
    ('curl pipe to shell',            re.compile(r'curl.*\|\s*(?:ba)?sh|wget.*\|\s*(?:ba)?sh', I),                    'CRITICAL'),
    ('environment exfiltration',      re.compile(r'env\b.*curl|printenv.*\||(?:API_KEY|SECRET|TOKEN|PASSWORD).*curl', I), 'CRITICAL'),
    ('reverse shell pattern',         re.compile(r'mkfifo|/dev/tcp/|nc\s+-[el]', I),                                  'CRITICAL'),
    # v4.2.0: up to three qualifiers: 'ignore all previous instructions' slipped past
    # the single-qualifier form, in every scanner sharing this list.
    ('hidden instruction override',   re.compile(r'ignore\s+(?:(?:all|any|the|previous|prior|above|earlier|your)\s+){1,3}(?:instructions|rules|directives)|disregard.*instructions|you\s+are\s+now', I), 'HIGH'),
    ('obfuscated variable expansion', re.compile(r'\$\{[A-Z_]*:.*:.*\}.*\$\{', I),                                    'HIGH'),
    ('credential file access',        re.compile(r'/etc/shadow|\.ssh/id_|\.aws/credentials|\.netrc|keychain', I),     'HIGH'),
    # 4.4, from NVIDIA SkillSpector's static rules (audited 2026-10-26). Each was
    # run over 596 real skill/agent/command files on the author's machine: 0 hits.
    # A download piped into an interpreter is the same capability as curl|sh.
    ('fetch pipe to interpreter',     re.compile(r'(?:curl|wget)\s+[^|\n]*\|\s*(?:sudo\s+)?(?:python3?|node|ruby|perl)\b|\b(?:iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b[^|\n]*\|\s*(?:iex|Invoke-Expression)\b', I), 'CRITICAL'),
    ('instruction hidden in HTML comment', re.compile(r'<!--(?:(?!-->).){0,400}?(?:ignore|instructions?|transmit|\bsystem\b|\bsend\b)(?:(?!-->).){0,400}?-->', I | re.S), 'HIGH'),
    ('covert send',                   re.compile(r'(?:silently|quietly|secretly|covertly)\s+(?:send|transmit|upload|post)', I), 'HIGH'),
    ('system prompt extraction',      re.compile(r'(?:reveal|output|print|dump|repeat|leak)\s+(?:your\s+)?(?:full\s+|entire\s+)?system\s+prompt', I), 'HIGH'),
    ('safety bypass instruction',     re.compile(r'(?:bypass|override|disable)\s+(?:all\s+)?(?:safety|security)\s+(?:restrictions?|checks?|rules?|guardrails?|constraints?)', I), 'HIGH'),
    ('cross-session memory poisoning', re.compile(r'remember\s+(?:this|the\s+following)\s+(?:for|in)\s+(?:(?:all|every)\s+)?(?:(?:future|subsequent)\s+)?(?:sessions?|conversations?)|henceforth\s*,?\s*you\s+must', I), 'HIGH'),
    ('anti-refusal instruction',      re.compile(r'\byou\s+(?:must|should)\s+never\s+refuse\b|\bnever\s+refuse\s+(?:a|any)\s+request', I), 'HIGH'),
    ('scheduled persistence',         re.compile(r'\|\s*crontab\s+-\s*(?:$|[;)\n])|launchctl\s+(?:load|bootstrap)', I | re.M), 'HIGH'),
    # Names per SkillSpector AS2 (3ae98afc): Cursor/VS Code/.mcp.json, Windsurf, Roo and
    # Cline (mcp_settings), Claude Desktop, and Claude Code's own ~/.claude.json.
    ('MCP config key harvesting',     re.compile(r'(?:mcp(?:_config|_settings)?|claude_desktop_config|\.claude)\.json.{0,80}?(?:api_?key|token|secret)', I), 'HIGH'),
    ('hidden base64 data URI',        re.compile(r'data:text/plain;base64,[A-Za-z0-9+/=]{50,}'), 'HIGH'),
    ('subprocess spawn',              re.compile(r'os\.system\(|subprocess\.(?:run|call|Popen)|child_process', I),    'MEDIUM'),
    ('file write outside project',    re.compile(r"open\(.*'/tmp|open\(.*'/var|>/etc/", I),                            'MEDIUM'),
]

# Zero-width characters: invisible in every editor and in review, so they are a
# carrier for instructions the human never sees. Presence alone is the signal.
ZERO_WIDTH = ('​', '‌', '‍', '﻿')

# v4.1.5: Unicode Tag Block (U+E0000-E007F) maps 1:1 to ASCII but renders
# zero-width — a second invisible carrier used to smuggle instructions an LLM
# reads and a human cannot see (EchoLeak CVE-2025-32711). Sibling of ZERO_WIDTH;
# non-raw string so \U resolves to the codepoint range. Near-zero FP.
_TAG_BLOCK = re.compile('[\U000e0000-\U000e007f]')

# 4.4: bidi embedding/isolate controls (Trojan Source, CVE-2021-42574) reorder what a
# human reads without changing what the model reads. prompt-injection-scanner.sh
# already flagged them on Read; the skill/agent load point did not.
_BIDI = re.compile('[\u202a-\u202e\u2066-\u2069]')

# 4.4: a skill that names a one-request exfil endpoint (webhook.site, a Discord or
# Slack webhook, a Telegram bot). The list is read from lib-egress-patterns.sh, the
# one the WebFetch, MCP and Bash guards use, so the channels cannot drift.
_COLLECTOR = []


def _collector_re():
    if not _COLLECTOR:
        try:
            import os as _os
            src = open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                                     'lib-egress-patterns.sh'), encoding='utf-8').read()
            m = re.search(r"^EGRESS_WEBHOOK_RE='([^']*)'", src, re.M)
            _COLLECTOR.append(re.compile(m.group(1), I) if m else None)
        except (OSError, re.error):
            _COLLECTOR.append(None)
    return _COLLECTOR[0]


# 4.4: a CRITICAL match QUOTED in backticks right after a reviewing verb ("flag any
# `curl ... | bash`", "never run `base64 -d | sh`") is a security skill describing the
# attack, not one performing it: that one match is reported HIGH instead of denying
# the whole skill (found running SkillSpector's benign samples). The same command
# anywhere else, or unquoted, still denies.
_REVIEW_CTX = re.compile(r'\b(?:flag|detect|block|reject|refuse|catch|warn\s+(?:about|on)|look\s+for|'
                         r'avoid|never\s+(?:run|use|execute)|do\s+not\s+(?:run|use|execute)|'
                         r"don't\s+(?:run|use|execute)|disallow|deny|denied|blocked|blocks|stops?|stopped)\b", I)


def _quoted_in_review(text, m):
    """True when this match sits inside an inline `code` span on a line that has a
    reviewing verb, or is a markdown table row. Code span always required."""
    line_start = text.rfind('\n', 0, m.start()) + 1
    line_end = text.find('\n', m.end())
    line_end = len(text) if line_end == -1 else line_end
    before, after = text[line_start:m.start()], text[m.end():line_end]
    inside_code = before.count('`') % 2 == 1 and '`' in after
    # 2026-10-27: the verb may follow ("`curl|bash` ... stay blocked"), and a markdown
    # table row quoting sinks in code is a reference table (sc-security's sink table).
    # Both were our own commands, denied on the Skill tool.
    table_row = before.lstrip().startswith('|')
    return inside_code and (table_row or bool(_REVIEW_CTX.search(before + ' ' + after)))


def scan_text(text, fname):
    """Return (findings, critical_count) for one instruction file's text.

    Both scanners format findings identically, so a user who has seen one
    scanner's output can read the other's without relearning it.
    """
    findings = []
    critical = 0
    for label, regex, sev in PATTERNS:
        if sev == 'CRITICAL':
            hits = list(regex.finditer(text))
            reviewed = sum(1 for m in hits if _quoted_in_review(text, m))
            live = len(hits) - reviewed
            if live:
                findings.append('%s: %s (%dx in %s)' % (sev, label, live, fname))
                critical += 1
            if reviewed:
                findings.append('HIGH: %s quoted in a review/detection context (%dx in %s)' % (label, reviewed, fname))
            continue
        n = len(regex.findall(text))
        if n:
            findings.append('%s: %s (%dx in %s)' % (sev, label, n, fname))
    stego = sum(text.count(c) for c in ZERO_WIDTH)
    if stego:
        findings.append('HIGH: steganographic whitespace (%dx in %s)' % (stego, fname))
    tags = len(_TAG_BLOCK.findall(text))
    if tags:
        findings.append('HIGH: unicode tag-block ASCII smuggling (%dx in %s)' % (tags, fname))
    bidi = len(_BIDI.findall(text))
    if bidi:
        findings.append('HIGH: bidirectional text controls (%dx in %s)' % (bidi, fname))
    col = _collector_re()
    if col:
        n = len(col.findall(text))
        if n:
            findings.append('HIGH: exfiltration endpoint named (webhook/bot collector) (%dx in %s)' % (n, fname))
    # A command file byte-identical to one Supercharger shipped is our own text: /sc-security
    # names attacks so it can look for them. Keep only live CRITICAL findings for it.
    # CRLF folded to LF: a Windows checkout of the same file must still match.
    if findings and hashlib.sha256(text.replace('\r\n', '\n').encode('utf-8', 'replace')).hexdigest() in _shipped_hashes():
        findings = [f for f in findings if f.startswith('CRITICAL')]
    return findings, critical


_SHIPPED = None


def _shipped_hashes():
    """sha256 of every command file Supercharger has shipped (configs/commands-shipped.txt,
    regenerated by tools/gen-commands-shipped.sh). Installed next to this file; the repo
    and plugin layouts keep it in configs/. Missing -> empty set, so everything warns."""
    global _SHIPPED
    if _SHIPPED is None:
        _SHIPPED = set()
        here = os.path.dirname(os.path.abspath(__file__))
        for path in (os.path.join(here, 'commands-shipped.txt'),
                     os.path.join(here, '..', 'configs', 'commands-shipped.txt')):
            try:
                with open(path) as f:
                    _SHIPPED = {ln.split()[1] for ln in f if len(ln.split()) == 2}
                break
            except OSError:
                continue
    return _SHIPPED


_FRONTMATTER = re.compile(r'\A\ufeff?---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\Z)', re.S)


def frontmatter_hooks(text):
    """The `hooks:` block of a SKILL.md / agent .md YAML frontmatter, or ''. Claude Code
    registers it like settings hooks: host commands, not instructions."""
    m = _FRONTMATTER.match(text or '')
    if not m:
        return ''
    h = re.search(r'(?m)^["\']?hooks["\']?[ \t]*:.*(?:\n(?:[ \t-].*|[ \t]*))*', m.group(1))
    return h.group(0).rstrip() if h else ''


def frontmatter_hook_findings(items, home_dir):
    """Findings for (path, text) items whose frontmatter hooks are new or changed since
    last seen. A file that declares hooks on purpose warns once, not on every load;
    a cloned or edited one still warns the first time it is read."""
    import hashlib, json, os as _os
    state = _os.environ.get('SUPERCHARGER_STATE') or _os.path.join(home_dir or '', '.claude', 'supercharger')
    sf = _os.path.join(state, 'scope', 'frontmatter-hooks-seen.json')
    try:
        seen = json.load(open(sf))
    except Exception:
        seen = {}
    out, dirty = [], False
    for path, text in items:
        block = frontmatter_hooks(text)
        if not block:
            continue
        key, h = str(path), hashlib.sha256(block.encode('utf-8', 'replace')).hexdigest()
        if seen.get(key) == h:
            continue
        seen[key], dirty = h, True
        out.append('HIGH: frontmatter declares hooks, which run shell commands on this machine '
                   '(in %s): %s' % (_os.path.basename(key), ' '.join(block.split())[:200]))
    if dirty:
        try:
            _os.makedirs(_os.path.dirname(sf), exist_ok=True)
            json.dump(seen, open(sf, 'w'))
        except Exception:
            pass
    return out


def msys_path(x):
    """Git Bash's /c/Users/... -> C:\\Users\\..., on Windows only.

    Claude Code launches hooks through Git Bash on Windows, so a payload `cwd`
    arrives POSIX-shaped: /d/a/repo. Native Windows python resolves a
    leading-slash path against the CURRENT DRIVE, so that becomes D:\\d\\a\\repo
    — a path that does not exist. Every `is_dir()` below then returns False, the
    base is skipped, and the scanner reports CLEAN having looked at nothing.
    Silent, and on a security scanner.

    Same normalisation, and the same reasoning, as path-guard's _msys_path;
    that one carries the measurements taken on a windows-latest runner.

    Gated on os.name so POSIX is provably untouched: there, a directory named
    /c is legitimate and must never be rewritten.
    """
    import os as _os
    import re as _re
    if _os.name != 'nt' or not x or not isinstance(x, str):
        return x
    m = _re.match(r'^/([A-Za-z])(/|$)', x)
    if not m:
        return x
    return m.group(1).upper() + ':\\' + x[3:].replace('/', '\\')


def resolve_agent_defs(agent, home_dir, cwd):
    """Map an agent name to the definition file(s) Claude Code would run. Deduped, existing.

    Shared for the same reason the patterns are: agent-poisoning-scanner (Agent)
    and workflow-guard (Workflow, via `agentType`) resolve the SAME files from two
    channels. Two copies of this lookup would drift on their glob list or their
    namespace handling the first time one is touched — the v2.8.1-.11 class again.

    Two hazards are encoded here rather than left to each caller:
      - a namespaced invocation ("plugin:agent") names a file by its BARE name on
        disk. Missing that was the v2.7.54 skill-poisoning bypass.
      - on a case-insensitive filesystem two globs differing only in case resolve
        to ONE file; dedup by inode, not by path string, or every finding in it is
        counted twice.
    """
    import re as _re

    if not agent or not isinstance(agent, str):
        return []

    names = {agent}
    bare = _re.split(r'[:/]', agent)[-1]
    if bare:
        names.add(bare)

    globs = []
    for nm in names:
        globs += [
            '%s.md' % nm, '*/%s.md' % nm, '*/*/%s.md' % nm,
            '%s/AGENT.md' % nm, '*/%s/AGENT.md' % nm,
        ]

    # Normalise BEFORE building the bases — a Git Bash cwd is POSIX-shaped and
    # would otherwise resolve to a non-existent path, skipping the project-level
    # scan without saying so.
    home_dir = msys_path(home_dir)
    cwd = msys_path(cwd)

    # Claude Code runs ONE definition per name (sub-agents.md): project .claude/agents/
    # over ~/.claude/agents/, and among the project dirs found walking up to the repo
    # root, "the definition closest to the working directory". So: cwd, then ancestors
    # nearest-first, then home; the first base holding a match is the answer. Scanning
    # a shadowed definition denied an agent whose file never runs.
    for base in agent_def_dirs(cwd, home_dir):
        if not base.is_dir():
            continue
        # Every match within the winning dir is kept: two files there declaring one
        # name load in "filesystem read order", so either may be the one that runs.
        out, seen = [], set()
        for pat in globs:
            try:
                for p in base.glob(pat):
                    if not p.is_file():
                        continue
                    try:
                        st = p.stat()
                        key = (st.st_dev, st.st_ino)
                    except OSError:
                        key = str(p.resolve())
                    if key not in seen and _fm_name_ok(p, names):
                        seen.add(key)
                        out.append(p)
            except Exception:
                continue
        if out:
            return out
    return []


def agent_def_dirs(cwd, home_dir):
    """Agent definition dirs in Claude Code's precedence: cwd, ancestors nearest first
    (up to the git root), then home. The first dir holding the agent wins. Shared by
    resolve_agent_defs and agent-allowlist-detect.py so the two orders cannot drift."""
    from pathlib import Path
    cwd, home_dir = msys_path(cwd), msys_path(home_dir)
    bases = [Path(cwd) / '.claude' / 'agents']
    bases += [Path(d) / 'agents' for d in ancestor_claude_dirs(cwd, home_dir)]
    bases.append(Path(home_dir) / '.claude' / 'agents')
    return bases


def _fm_name_ok(p, names):
    """False when the file's frontmatter `name:` names a different agent. Claude Code
    keys agents by that name, not the filename, so such a file shadows nothing; letting
    it win would skip the definition that actually runs. No name field -> True."""
    import re as _re
    try:
        with open(str(p), encoding='utf-8', errors='replace') as f:
            head = f.read(4096)
    except OSError:
        return True
    m = _re.match(r'\A\ufeff?---\s*\n(.*?)\n---', head, _re.S)
    n = m and _re.search(r'^name:\s*[\'"]?([^\'"\n]+?)[\'"]?\s*$', m.group(1), _re.M)
    return not n or n.group(1).strip() in names


# Directory names never searched for nested .claude dirs: dependencies, build output,
# VCS internals. Dot-dirs are skipped too (and .claude is never descended into: its
# worktrees/ holds whole checkouts).
_NESTED_SKIP = frozenset(('node_modules', 'vendor', 'dist', 'build'))


def git_root(start):
    """Nearest directory at or above `start` holding .git (a dir, or a worktree's file)."""
    import os as _os
    d = _os.path.realpath(start) if start else ''
    while d:
        if _os.path.exists(_os.path.join(d, '.git')):
            return d
        nd = _os.path.dirname(d)
        if nd == d:
            return None
        d = nd
    return None


def _same(a, b):
    import os as _os
    return _os.path.normcase(_os.path.realpath(a)) == _os.path.normcase(_os.path.realpath(b))


def ancestor_claude_dirs(cwd, home_dir=''):
    """`.claude` dirs strictly above the cwd, up to the git root. Claude Code loads
    skills and agents from each at startup (skills.md, sub-agents.md). [] outside a
    repo; ~/.claude is user scope and left out."""
    import os as _os
    cwd = msys_path(cwd)
    root = git_root(cwd) if cwd else None
    if not root:
        return []
    home_claude = _os.path.join(msys_path(home_dir), '.claude') if home_dir else ''
    out, d = [], _os.path.realpath(cwd)
    while not _same(d, root):
        nd = _os.path.dirname(d)
        if nd == d:
            break
        d = nd
        p = _os.path.join(d, '.claude')
        if _os.path.isdir(p) and not (home_claude and _same(p, home_claude)):
            out.append(p)
    return out


def nested_claude_dirs(cwd, home_dir='', max_depth=4, max_dirs=800):
    """`.claude` dirs anywhere under the git root (the cwd outside a repo), at most
    `max_depth` levels down. Skills in one load the first time Claude touches a file
    in that subfolder (skills.md, "Nested"). The cwd's own and ~/.claude are left out.
    Breadth-first, so shallow packages are always covered first.
    shortcut: stops after `max_depth` levels or `max_dirs` directories (~40us each on
    macOS; this runs at SessionStart) and skips dependency/build dirs, so a skill
    deeper than that in a huge tree is missed. Raise the caps if that bites."""
    import os as _os
    cwd = msys_path(cwd)
    if not cwd or not _os.path.isdir(cwd):
        return []
    top = git_root(cwd) or _os.path.realpath(cwd)
    skip = [_os.path.join(cwd, '.claude')] + ([_os.path.join(msys_path(home_dir), '.claude')] if home_dir else [])
    out, level = [], [top]
    seen = 0
    for depth in range(max_depth + 1):
        nxt = []
        for d in level:
            seen += 1
            if seen > max_dirs:
                return out
            try:
                it = list(_os.scandir(d))
            except OSError:
                continue
            for e in it:
                try:
                    if not e.is_dir(follow_symlinks=False):
                        continue
                except OSError:
                    continue
                if e.name == '.claude':
                    if not any(_same(e.path, s) for s in skip):
                        out.append(e.path)
                elif depth < max_depth and not e.name.startswith('.') and e.name not in _NESTED_SKIP:
                    nxt.append(e.path)
        level = nxt
    return out
