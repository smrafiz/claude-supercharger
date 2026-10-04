#!/usr/bin/env python3
"""Redirect-clobber detector — called by redirect-clobber-guard.sh.

Reads CMD (the Bash command) and PROJECT_DIR (cwd) from the environment. Extracts
files that a truncating clobber (`>` not `>>`, `sed -i`, `tee` no -a, `dd of=`,
`truncate`) would overwrite, and prints the FIRST one that is git-TRACKED. Empty
output = nothing to ask about.
"""
import os
import re
import shlex
import subprocess
import sys

cmd = os.environ.get("CMD", "")
proj = os.environ.get("PROJECT_DIR", "") or "."
if not cmd:
    sys.exit(0)

EXCLUDE_DIRS = (
    "dist/", "build/", ".next/", ".nuxt/", ".output/", "node_modules/",
    "coverage/", ".venv/", "__pycache__/", "vendor/", "target/",
)


def excluded(p):
    n = p.replace("\\", "/")
    if n == "/dev/null" or n.startswith("/dev/"):
        return True
    if any(seg in n for seg in EXCLUDE_DIRS):
        return True
    # lockfiles are handled by lockfile-integrity-guard; skip generated/minified.
    if n.endswith((".lock", ".min.js", ".min.css", ".map")):
        return True
    return False


def segments(c):
    return re.split(r";|&&|\|\||\||&", c)


cands = []

# 1) stdout truncating redirect: `>` not `>>`, not `2>`/`1>`, not `&>`/`>&`.
# v2.22.10: also catch an fd-qualified truncate (`1> f`) and clobber-force (`>| f`).
# `(?![>&])` still excludes append `>>` and fd-dup `>&`/`2>&1`; `\|?` consumes the
# clobber-force pipe. (Only tracked files are ever surfaced, so `2> untracked.log`
# stays silent.)
for m in re.finditer(r"""(?<![>&])>(?![>&])\|?\s*("[^"]+"|'[^']+'|[^\s;&|<>()]+)""", cmd):
    cands.append(m.group(1))

# 2) sed -i / --in-place: file args are the trailing non-flag tokens (the FIRST
#    non-flag is the s/…/…/ script; the rest are files).
for seg in segments(cmd):
    if re.search(r"(^|\s)sed(\s|$)", seg) and re.search(r"(^|\s)(-i\b|--in-place)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        if "sed" in toks:
            nonflag = [t for t in toks[toks.index("sed") + 1:] if not t.startswith("-")]
            cands.extend(nonflag[1:])

# 3) tee (no -a/--append): non-flag args are target files.
for seg in segments(cmd):
    if re.search(r"(^|\s)tee(\s|$)", seg) and not re.search(r"(^|\s)(-a\b|--append)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        if "tee" in toks:
            cands.extend(t for t in toks[toks.index("tee") + 1:] if not t.startswith("-"))

# 4) dd of=FILE
for m in re.finditer(r"""\bdd\b[^;&|]*?\bof=("[^"]+"|'[^']+'|[^\s;&|]+)""", cmd):
    cands.append(m.group(1))

# 5) truncate … FILE (last non-flag token of the truncate segment).
for seg in segments(cmd):
    if re.search(r"(^|\s)truncate(\s|$)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        files = [t for t in toks if not t.startswith("-") and t != "truncate"]
        if files:
            cands.append(files[-1])

# 6) cp / mv clobbering a tracked destination. safety.sh guards cp/mv only for
#    security targets (sudoers/authorized_keys/…); a plain `mv build/app.js
#    src/app.js` or `cp tpl.ts config.ts` over a tracked source silently bypasses
#    every write guard — the redirect-clobber sibling verbs drifted. Dest = the
#    trailing operand (or the `-t DIR` target). Recursive/archive dir copies are
#    skipped (dir semantics, high parse ambiguity). A pure rename to a NEW path
#    stays silent — only a git-TRACKED dest is ever surfaced downstream.
for seg in segments(cmd):
    mm = re.search(r"(?:^|\s)(cp|mv)(?:\s|$)", seg)
    if not mm:
        continue
    try:
        toks = shlex.split(seg)
    except Exception:
        toks = seg.split()
    verb = mm.group(1)
    if verb not in toks:
        continue
    rest = toks[toks.index(verb) + 1:]
    # skip recursive/archive copies (dir semantics, parse-ambiguous, low signal)
    if any(t in ("-r", "-R", "--recursive", "-a", "--archive") or
           (re.match(r"^-[A-Za-z]+$", t) and re.search(r"[rRa]", t[1:]))
           for t in rest):
        continue
    tdir = None
    ops = []
    i = 0
    while i < len(rest):
        t = rest[i]
        if t in ("-t", "--target-directory") and i + 1 < len(rest):
            tdir = rest[i + 1]; i += 2; continue
        if t.startswith("--target-directory="):
            tdir = t.split("=", 1)[1]; i += 1; continue
        if t in ("-S", "--suffix") and i + 1 < len(rest):
            i += 2; continue                      # value-flag: skip its value
        if t.startswith("-") and t != "-":
            i += 1; continue                      # any other flag
        ops.append(t); i += 1
    if tdir is not None:
        for s in ops:
            cands.append(os.path.join(tdir, os.path.basename(s)))
        continue
    if len(ops) < 2:
        continue
    dest = ops[-1]
    sources = ops[:-1]
    dpath = dest if os.path.isabs(dest) else os.path.join(proj, dest)
    if os.path.isdir(dpath):
        for s in sources:
            cands.append(os.path.join(dest, os.path.basename(s)))
    elif dest not in sources:
        cands.append(dest)

# 7) PowerShell (tool_name PowerShell only): the clobber vocabulary is cmdlets.
#    Set-Content / Out-File (no -Append) / Clear-Content overwrite their -Path or
#    first positional; Copy-Item / Move-Item overwrite -Destination or the second
#    positional. -Recurse copies are skipped, like cp -r. `>` is caught by (1).
PS_WRITE = {"set-content", "sc", "out-file", "clear-content", "clc"}
PS_COPY = {"copy-item", "copy", "cpi", "move-item", "move", "mi"}
PS_PATH_FLAGS = ("-path", "-filepath", "-literalpath", "-lp", "-pspath")
PS_VALUE_FLAGS = ("-value", "-encoding", "-inputobject", "-width", "-filter",
                  "-include", "-exclude", "-credential", "-stream")
if os.environ.get("SC_SHELL") == "PowerShell":
    for seg in segments(cmd):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        low = [t.lower() for t in toks]
        verb = next((t for t in low if t in PS_WRITE or t in PS_COPY), None)
        if verb is None:
            continue
        rest = toks[low.index(verb) + 1:]
        lrest = [t.lower() for t in rest]
        if verb in ("out-file",) and "-append" in lrest:
            continue
        if verb in PS_COPY and any(t.startswith("-recurse") for t in lrest):
            continue
        named, pos, i = {}, [], 0
        while i < len(rest):
            t, lt = rest[i], lrest[i]
            if lt.startswith("-") and ":" in lt:          # -Path:foo
                named[lt.split(":", 1)[0]] = t.split(":", 1)[1]; i += 1; continue
            if lt in PS_PATH_FLAGS or lt == "-destination" or lt in PS_VALUE_FLAGS:
                if i + 1 < len(rest):
                    named[lt] = rest[i + 1]
                i += 2; continue
            if lt.startswith("-"):
                i += 1; continue                          # switch (-Force, -NoNewline)
            pos.append(t); i += 1
        if verb in PS_WRITE:
            target = next((named[f] for f in PS_PATH_FLAGS if f in named), None)
            target = target or (pos[0] if pos else None)
        else:
            target = named.get("-destination") or (pos[1] if len(pos) > 1 else None)
        if target:
            cands.append(target)

# One git fork answers "is ANY candidate tracked?". Every `>` inside a heredoc'd
# program (`a > b`, `=>`) is a candidate, and the loop below forks git once per
# candidate. Only when something is tracked (or the batch errors, e.g. a bad
# pathspec) do we fall through to the per-candidate loop, which keeps its order.
_batch = [c.strip().strip('"').strip("'") for c in cands]
_batch = [p for p in dict.fromkeys(_batch) if p and not excluded(p)]
if len(_batch) > 1:
    try:
        _r = subprocess.run(["git", "-C", proj, "ls-files", "--", *_batch],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
        if _r.returncode == 0 and not _r.stdout.strip():
            cands = []
    except Exception:
        pass

seen = set()
for raw in cands:
    p = raw.strip().strip('"').strip("'")
    if not p or p in seen:
        continue
    seen.add(p)
    if excluded(p):
        continue
    try:
        r = subprocess.run(
            ["git", "-C", proj, "ls-files", "--error-unmatch", "--", p],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
        )
    except Exception:
        continue
    if r.returncode == 0:
        print(p)
        break
