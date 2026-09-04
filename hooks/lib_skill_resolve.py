"""Resolve an invoked skill name to the file(s) backing it on disk.

Shared by skill-poisoning-scanner (content classification) and
skill-integrity-guard (change detection). Both must agree on WHICH file a skill
name means; two copies of this logic drift the moment one is edited, which is
the v2.9.8 cross-channel parity failure.

Extracted verbatim from skill-poisoning-scanner, including the two bug fixes it
carries: the ~/.claude/skills root (v2.27.x -- the primary install path, once
omitted, so an identical poisoned SKILL.md was denied under plugins/ and passed
under skills/) and the bare-name search (v2.7.54 -- skills are invoked
namespaced "plugin:skill" while the file on disk is named by the bare skill, so
a raw-name glob matched nothing and the file was never opened).
"""
import re
from pathlib import Path


def resolve_skill_paths(skill, home_dir, cwd):
    """Return existing files backing `skill`, de-duplicated by resolved path.

    Empty list when nothing matches -- callers treat that as "nothing to
    inspect", never as "inspected and clean".
    """
    candidates = [
        Path(home_dir) / '.claude' / 'commands',
        Path(home_dir) / '.claude' / 'plugins',
        Path(home_dir) / '.claude' / 'skills',
        Path(cwd) / '.claude' / 'commands',
        Path(cwd) / '.claude' / 'plugins',
        Path(cwd) / '.claude' / 'skills',
    ]

    skill_names = {skill}
    bare = re.split(r'[:/]', skill)[-1]
    if bare:
        skill_names.add(bare)

    # Targeted globs only -- rglob over ~/.claude/ walks 1000s of files.
    # Three shapes: <base>/.../<name>.md, <base>/.../<name>/SKILL.md,
    # <base>/.../<name>/skill.md. Depth limit 6.
    patterns = []
    for nm in skill_names:
        patterns += [
            f'{nm}.md', f'*/{nm}.md', f'*/*/{nm}.md', f'*/*/*/{nm}.md',
            f'{nm}/SKILL.md', f'*/{nm}/SKILL.md', f'*/*/{nm}/SKILL.md',
            f'{nm}/skill.md', f'*/{nm}/skill.md', f'*/*/{nm}/skill.md',
        ]

    seen = set()
    out = []
    for base in candidates:
        if not base.is_dir():
            continue
        for pat in patterns:
            try:
                for p in base.glob(pat):
                    if p.is_file():
                        if _identity(p) not in seen:
                            seen.add(_identity(p))
                            out.append(p)
            except Exception:
                continue
    return out


def _identity(p):
    """Identify a file by what the filesystem says it is, not by its spelling.

    The SKILL.md / skill.md globs both match one file on a case-INSENSITIVE
    filesystem (macOS, NTFS), and Path.resolve() keeps the casing the glob was
    written with -- so two spellings of one file produced two different strings
    and string dedup let it through twice. Harmless for a scanner (it reports the
    same finding twice); wrong for a lock, which would key one file under two
    names and hash it twice.

    (st_dev, st_ino) is the filesystem's own answer to "same file", and it
    settles hard links and case-folding together. Falls back to the resolved
    string where stat is unavailable, which is the old behaviour.
    """
    try:
        st = p.stat()
        return (st.st_dev, st.st_ino)
    except Exception:
        return str(p.resolve())
