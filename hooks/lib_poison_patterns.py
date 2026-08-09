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

import re

I = re.IGNORECASE

# (label, compiled regex, severity) — ordered by severity.
# All patterns are IGNORECASE: they were case-sensitive until v2.7.14, so
# "IGNORE PREVIOUS INSTRUCTIONS" / "CURL ... | SH" evaded every check.
PATTERNS = [
    ('base64 decode execution',       re.compile(r'base64\s+(?:-d|--decode)|atob\(|b64decode', I),                    'CRITICAL'),
    ('hidden eval/exec',              re.compile(r'\beval\b.*\$|exec\s*\(', I),                                       'CRITICAL'),
    ('curl pipe to shell',            re.compile(r'curl.*\|\s*(?:ba)?sh|wget.*\|\s*(?:ba)?sh', I),                    'CRITICAL'),
    ('environment exfiltration',      re.compile(r'env\b.*curl|printenv.*\||(?:API_KEY|SECRET|TOKEN|PASSWORD).*curl', I), 'CRITICAL'),
    ('reverse shell pattern',         re.compile(r'mkfifo|/dev/tcp/|nc\s+-[el]', I),                                  'CRITICAL'),
    ('hidden instruction override',   re.compile(r'ignore\s+(?:previous|above|all)\s+(?:instructions|rules)|disregard.*instructions|you\s+are\s+now', I), 'HIGH'),
    ('obfuscated variable expansion', re.compile(r'\$\{[A-Z_]*:.*:.*\}.*\$\{', I),                                    'HIGH'),
    ('credential file access',        re.compile(r'/etc/shadow|\.ssh/id_|\.aws/credentials|\.netrc|keychain', I),     'HIGH'),
    ('subprocess spawn',              re.compile(r'os\.system\(|subprocess\.(?:run|call|Popen)|child_process', I),    'MEDIUM'),
    ('file write outside project',    re.compile(r"open\(.*'/tmp|open\(.*'/var|>/etc/", I),                            'MEDIUM'),
]

# Zero-width characters: invisible in every editor and in review, so they are a
# carrier for instructions the human never sees. Presence alone is the signal.
ZERO_WIDTH = ('​', '‌', '‍', '﻿')


def scan_text(text, fname):
    """Return (findings, critical_count) for one instruction file's text.

    Both scanners format findings identically, so a user who has seen one
    scanner's output can read the other's without relearning it.
    """
    findings = []
    critical = 0
    for label, regex, sev in PATTERNS:
        n = len(regex.findall(text))
        if n:
            findings.append('%s: %s (%dx in %s)' % (sev, label, n, fname))
            if sev == 'CRITICAL':
                critical += 1
    stego = sum(text.count(c) for c in ZERO_WIDTH)
    if stego:
        findings.append('HIGH: steganographic whitespace (%dx in %s)' % (stego, fname))
    return findings, critical


def resolve_agent_defs(agent, home_dir, cwd):
    """Map an agent name to the definition file(s) on disk. Deduped, existing.

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
    from pathlib import Path

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

    out, seen = [], set()
    for base in (Path(home_dir) / '.claude' / 'agents', Path(cwd) / '.claude' / 'agents'):
        if not base.is_dir():
            continue
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
                    if key not in seen:
                        seen.add(key)
                        out.append(p)
            except Exception:
                continue
    return out
