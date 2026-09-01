#!/usr/bin/env python3
"""Decide whether an edit lands inside a locked line range.

Reads the hook payload on stdin and a manifest path in AI_LOCK_MANIFEST. Prints
one human-readable reason on stdout when the edit intersects a lock, nothing
otherwise. Exit status is always 0 — the caller treats "no output" as allow, so
a crash here must never turn into a phantom deny.

MANIFEST FORMAT — JSON Lines, one object per line, `#` lines ignored. This is
PIsberg/vibetags' `.vibetags-locks` schema, taken verbatim so a project that
already generates one gets this for free:

    {"type":"locked","file":"src/a.py","startLine":10,"endLine":40,
     "reason":"Step order is load-bearing; reordering skips regeneration"}

`reason` is the point of the whole feature. A guard that says "this is locked"
teaches nothing and gets waved through; one that says WHY carries the knowledge
of whoever locked it to whoever is about to change it.

Unknown `type` values are skipped, so a manifest carrying other record kinds
(vibetags writes a `format` header) works untouched.
"""
from __future__ import annotations

import json
import os
import re
import sys

_MAX_MANIFEST_BYTES = 1 << 20  # 1MB — a lock manifest is metadata, not data


def _msys_path(x):
    """Git Bash's /c/Users/... -> C:\\Users\\..., on Windows only.

    Same normalisation and the same reasoning as path-guard's `_msys_path` and
    lib_poison_patterns' `msys_path`; test-msys-path-normalisation asserts every
    scanner that path-joins a payload path carries one. This detector did not,
    and v4.0.13's Windows job is what said so: 5 pass / 6 fail, and the split was
    exact — every case expecting an ASK failed, every case expecting silence
    passed. The guard was inert on Windows, failing open and saying nothing.

    Claude Code launches hooks through Git Bash, so the manifest path arrives
    POSIX-shaped from the wrapper's `$PWD` walk while native Windows python
    resolves a leading slash against the CURRENT DRIVE. The two sides of the
    comparison then spell the same file differently and no lock ever matches —
    the identical defect fixed for macOS's /private/var vs /var one release
    earlier, which should have been the hint that a THIRD spelling existed.

    Gated on os.name so POSIX is provably untouched: there, a directory named
    /c is legitimate and must never be rewritten.
    """
    if os.name != "nt" or not x or not isinstance(x, str):
        return x
    m = re.match(r"^/([A-Za-z])(/|$)", x)
    if not m:
        return x
    return m.group(1).upper() + ":\\" + x[3:].replace("/", "\\")


def _same_file(a, b):
    """Whether two spellings name the same file.

    realpath on both sides after MSYS normalisation, and a case-insensitive
    compare on Windows, where the filesystem is.
    """
    a = os.path.realpath(_msys_path(a))
    b = os.path.realpath(_msys_path(b))
    if os.name == "nt":
        return a.lower() == b.lower()
    return a == b


def _locks(path, repo_root):
    """Locked ranges from the manifest, each file made absolute.

    A recorded path is relative to the manifest's own directory, not to the
    process cwd — the mistake vibetags records fixing, where two modules with
    the same relative layout drew each other's violations.
    """
    out = []
    try:
        if os.path.getsize(path) > _MAX_MANIFEST_BYTES:
            return out
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue  # one bad line must not void the rest
                if not isinstance(rec, dict) or rec.get("type") != "locked":
                    continue
                f = rec.get("file")
                if not isinstance(f, str) or not f:
                    continue
                try:
                    start = int(rec.get("startLine", 0))
                    end = int(rec.get("endLine", 0))
                except Exception:
                    continue
                if start <= 0 or end < start:
                    continue
                out.append({
                    # Joined but NOT resolved: `_same_file` resolves both sides
                    # together, because resolving here would fix one spelling of
                    # the path and leave the other. Two spellings have already bitten
                    # this detector — /private/var vs /var on macOS, then /c/... vs
                    # C:\... on Git Bash — so the comparison owns the normalisation
                    # and nothing else does it piecemeal.
                    "file": (f if os.path.isabs(f)
                             else os.path.join(repo_root, f)),
                    "start": start,
                    "end": end,
                    "reason": (rec.get("reason") or "").strip(),
                    "element": (rec.get("element") or "").strip(),
                })
    except Exception:
        return []
    return out


def _edit_ranges(tool, tool_input, target):
    """1-indexed [start, end] line ranges this call would change.

    None means "the whole file" — a Write replaces it wholesale, so it touches
    every lock in that file regardless of where they sit.
    """
    if tool in ("Write", "NotebookEdit"):
        return None
    strings = []
    if tool == "Edit":
        s = tool_input.get("old_string")
        if isinstance(s, str) and s:
            strings.append(s)
    elif tool == "MultiEdit":
        for e in tool_input.get("edits") or []:
            if isinstance(e, dict):
                s = e.get("old_string")
                if isinstance(s, str) and s:
                    strings.append(s)
    if not strings:
        return None  # cannot tell what moves -> treat as whole-file, ask rather than miss
    try:
        with open(target, encoding="utf-8", errors="replace") as fh:
            body = fh.read()
    except Exception:
        return None
    ranges = []
    for s in strings:
        idx = body.find(s)
        if idx < 0:
            # The edit will fail anyway, or the string is normalised differently.
            # Do not invent a range: fall back to whole-file rather than guess.
            return None
        start = body.count("\n", 0, idx) + 1
        ranges.append((start, start + s.count("\n")))
    return ranges


def main():
    manifest = os.environ.get("AI_LOCK_MANIFEST", "")
    manifest = _msys_path(manifest)
    if not manifest or not os.path.isfile(manifest):
        return
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return
    target = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not isinstance(target, str) or not target:
        return
    target_raw = target
    target = os.path.realpath(_msys_path(target))

    repo_root = os.path.dirname(os.path.abspath(_msys_path(manifest)))
    hits = [lk for lk in _locks(manifest, repo_root)
            if _same_file(lk["file"], target_raw)]
    if not hits:
        return

    ranges = _edit_ranges(tool, tool_input, target)
    if ranges is not None:
        hits = [lk for lk in hits
                if any(s <= lk["end"] and lk["start"] <= e for s, e in ranges)]
        if not hits:
            return

    lk = hits[0]
    where = "%s:%d-%d" % (os.path.basename(lk["file"]), lk["start"], lk["end"])
    what = lk["element"] or where
    reason = lk["reason"] or "no reason recorded in the manifest"
    extra = "" if len(hits) == 1 else " (+%d more locked range(s) in this file)" % (
        len(hits) - 1
    )
    print("%s is locked in %s — %s%s" % (
        what, os.path.basename(manifest), reason, extra))


main()
