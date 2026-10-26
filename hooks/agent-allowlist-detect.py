#!/usr/bin/env python3
"""Claude Supercharger — per-agent allowlist resolver (agent-allowlist-guard.sh).

Reads the PreToolUse payload on stdin. Decides whether the call comes from a
subagent whose definition declares a `supercharger-allow:` list for this tool,
and if so whether the call is inside it. Prints ONE verdict on stdout, fields
separated by \\x1f:

  ALLOW                         no list applies, or the call is inside it
  DENY  <reason> <remedy>       the call is outside the declared list
  SEG   <agent> <file> <pats> <cmd>
                                Bash: the shell side splits <cmd> with
                                cmd-normalize.sh and matches every segment
                                against <pats> (newline separated)

Fail-open notes (malformed lists) are written to stderr directly.

Frontmatter shape (all three keys optional):

  supercharger-allow:
    bash: ["git status", "git diff*"]   # prefix, or glob when it has * ? [
    webfetch: [docs.python.org, "*.github.com"]
    write:                               # block lists work too
      - src/**
      - tests/**

Identity: the payload's `agent_id` marks a subagent call (code.claude.com/docs/
en/hooks, "common input fields"); `agent_type` is the frontmatter `name` of the
agent, not its filename. A session started with --agent carries agent_type but
no agent_id, and is the main session: never restricted here.

Fail open on anything this file cannot read: a malformed list must never block
work, it says so on stderr instead. Fail closed only on the CALL: once a list
is declared, a command, URL or path that cannot be matched is outside it.
"""

import fnmatch
import json
import os
import re
import sys
from urllib.parse import urlsplit

US = "\x1f"
KEY = "supercharger-allow"
TOOL_KEYS = {
    "Bash": "bash", "Monitor": "bash", "PowerShell": "bash",
    "WebFetch": "webfetch",
    "Write": "write", "Edit": "write", "MultiEdit": "write", "NotebookEdit": "write",
}
KNOWN = {"bash", "webfetch", "write"}


class Malformed(Exception):
    pass


def note(msg):
    sys.stderr.write("[Supercharger] agent-allowlist-guard: %s (failing open)\n" % msg)


def out(*fields):
    print(US.join(fields))
    sys.exit(0)


# ── frontmatter ─────────────────────────────────────────────────────────────
def _strip_comment(s):
    q = None
    for i, c in enumerate(s):
        if q:
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "#" and (i == 0 or s[i - 1] in " \t"):
            return s[:i].rstrip()
    return s.rstrip()


def _scalar(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] == '"':
        try:
            return json.loads(s)
        except Exception:
            raise Malformed("bad double-quoted string %s" % s[:40])
    if len(s) >= 2 and s[0] == s[-1] == "'":
        return s[1:-1].replace("''", "'")
    if s[:1] in "\"'":
        raise Malformed("unterminated quote in %s" % s[:40])
    return s


def _flow_list(s):
    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        raise Malformed("expected [ ... ] list, got %s" % s[:40])
    body, items, buf, q = s[1:-1], [], "", None
    for c in body:
        if q:
            buf += c
            if c == q:
                q = None
        elif c in "\"'":
            q = c
            buf += c
        elif c == ",":
            items.append(buf)
            buf = ""
        elif c in "[]{}":
            raise Malformed("nested collections are not supported")
        else:
            buf += c
    if q:
        raise Malformed("unterminated quote in list")
    items.append(buf)
    vals = [_scalar(x) for x in items if x.strip()]
    return vals


def parse_frontmatter(text):
    """-> (name or None, allow dict or None, notes). Raises Malformed."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        if KEY in text:
            raise Malformed("%s found but the file has no --- frontmatter" % KEY)
        return None, None, []
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise Malformed("frontmatter is not closed with ---")
    fm = lines[1:end]
    name, allow, notes = None, None, []
    i = 0
    while i < len(fm):
        raw = fm[i]
        line = _strip_comment(raw)
        i += 1
        if not line.strip() or raw[:1] in " \t":
            continue
        m = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", line)
        if not m:
            continue
        k, v = m.group(1), m.group(2)
        if k == "name":
            name = _scalar(v) if v.strip() else None
            continue
        if k != KEY:
            continue
        if v.strip():
            raise Malformed("%s must be a block of bash/webfetch/write keys" % KEY)
        allow = {}
        block = []
        while i < len(fm) and (not fm[i].strip() or fm[i][:1] in " \t"):
            block.append(fm[i])
            i += 1
        j = 0
        while j < len(block):
            bl = _strip_comment(block[j])
            j += 1
            if not bl.strip():
                continue
            mm = re.match(r"^(\s+)([A-Za-z0-9_-]+)\s*:\s*(.*)$", bl)
            if not mm:
                raise Malformed("cannot read line %r" % bl.strip()[:40])
            ind, tk, tv = len(mm.group(1)), mm.group(2).lower(), mm.group(3)
            if tv.strip():
                vals = _flow_list(tv) if tv.strip().startswith("[") else [_scalar(tv)]
            else:
                vals = []
                while j < len(block):
                    il = _strip_comment(block[j])
                    if not il.strip():
                        j += 1
                        continue
                    im = re.match(r"^(\s+)-\s*(.*)$", il)
                    if not im or len(im.group(1)) <= ind:
                        break
                    vals.append(_scalar(im.group(2)))
                    j += 1
            for x in vals:
                if not isinstance(x, str) or not x.strip() or "\n" in x:
                    raise Malformed("%s.%s has an empty or non-text entry" % (KEY, tk))
            if tk not in KNOWN:
                notes.append("unknown key %s.%s ignored" % (KEY, tk))
                continue
            allow[tk] = [x.strip() for x in vals]
    return name, allow, notes


# ── definition lookup ───────────────────────────────────────────────────────
def project_root(cwd):
    d = os.path.realpath(cwd) if cwd else ""
    cur = d
    while cur:
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        nxt = os.path.dirname(cur)
        if nxt == cur:
            break
        cur = nxt
    return d


def find_definition(agent, home, bases, resolve_agent_defs):
    """Project definitions shadow user ones (Claude Code's precedence)."""
    from pathlib import Path
    home_agents = os.path.realpath(os.path.join(home, ".claude", "agents"))
    ordered = [b for b in bases if b] + [home]
    seen = set()
    for base in ordered:
        agents_dir = os.path.realpath(os.path.join(base, ".claude", "agents"))
        if agents_dir in seen or not os.path.isdir(agents_dir):
            continue
        seen.add(agents_dir)
        is_home = agents_dir == home_agents
        # Shared resolver first: filename == agent name is the common case.
        cands = []
        try:
            for p in resolve_agent_defs(agent, home if is_home else "/nonexistent", base):
                rp = os.path.realpath(str(p))
                if rp.startswith(agents_dir + os.sep):
                    cands.append(rp)
        except Exception:
            cands = []
        # agent_type is the frontmatter name, which need not be the filename
        # ("Tony Stark (Engineer)" lives in code-helper.md). Fall back to reading
        # every definition's name in this directory.
        for p in sorted(Path(agents_dir).glob("**/*.md")):
            rp = os.path.realpath(str(p))
            if rp not in cands:
                cands.append(rp)
        for rp in cands:
            try:
                text = open(rp, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            try:
                name, allow, notes = parse_frontmatter(text)
            except Malformed as e:
                stem = os.path.splitext(os.path.basename(rp))[0]
                if stem == agent or KEY in text and re.search(
                        r"(?m)^name\s*:\s*[\"']?%s[\"']?\s*$" % re.escape(agent), text):
                    return rp, None, ["malformed %s in %s (%s); list ignored" % (KEY, rp, e)]
                continue
            nm = name or os.path.splitext(os.path.basename(rp))[0]
            if nm == agent:
                return rp, allow, notes
    return None, None, []


# ── matchers ────────────────────────────────────────────────────────────────
def glob_rx(pat):
    i, n, rx = 0, len(pat), ""
    while i < n:
        c = pat[i]
        if pat.startswith("**/", i):
            rx += "(?:.*/)?"
            i += 3
        elif pat.startswith("**", i):
            rx += ".*"
            i += 2
        elif c == "*":
            rx += "[^/]*"
            i += 1
        elif c == "?":
            rx += "[^/]"
            i += 1
        else:
            rx += re.escape(c)
            i += 1
    return re.compile(rx + r"\Z")


def has_glob(s):
    return any(c in s for c in "*?[")


def norm_tool_path(p, home):
    # Same two spellings hooks/lib-toolpath.sh sc_norm_path rewrites: surrounding
    # whitespace, and a leading ~ / ~/. Keep the two in step.
    p = p.strip()
    if p == "~":
        p = home
    elif p.startswith("~/"):
        p = home + "/" + p[2:]
    return p


def path_allowed(real, root, pats, home):
    rel = os.path.relpath(real, root) if root else None
    inside = rel is not None and rel != ".." and not rel.startswith(".." + os.sep)
    for pat in pats:
        pp = norm_tool_path(pat, home)
        if os.path.isabs(pp):
            # Absolute entry: compare real paths, so a symlink cannot alias in.
            stem = re.split(r"[*?\[]", pp, 1)[0]
            base = os.path.dirname(stem) if has_glob(pp) else pp
            rb = os.path.realpath(base)
            pp = rb + pp[len(base):]
            target = real
        else:
            if not inside:
                continue
            pp = pp[2:] if pp.startswith("./") else pp
            pp = pp.rstrip("/") or pp
            target = rel.replace(os.sep, "/")
        if has_glob(pp):
            if glob_rx(pp).match(target):
                return True
        elif target == pp or target.startswith(pp.rstrip("/") + "/"):
            return True
    return False


def host_of(url):
    try:
        sp = urlsplit(url.strip())
    except Exception:
        return None
    if sp.scheme.lower() not in ("http", "https"):
        return None
    h = sp.hostname
    return h.rstrip(".").lower() if h else None


def host_allowed(host, pats):
    for pat in pats:
        p = pat.strip().lower()
        if "://" in p:
            p = host_of(p) or p
        p = p.rstrip(".")
        if has_glob(p):
            if fnmatch.fnmatchcase(host, p):
                return True
        elif host == p or host.endswith("." + p):
            return True
    return False


def unsafe_shell(cmd):
    """Constructs whose effect a prefix list cannot see. -> label or None."""
    q = None
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if q == "'":
            if c == "'":
                q = None
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c == "`":
            return "command substitution (backticks)"
        if c == "$" and cmd.startswith("$(", i):
            return "command substitution $( )"
        if q == '"':
            if c == '"':
                q = None
            i += 1
            continue
        if c in "\"'":
            q = c
            i += 1
            continue
        if c in "<>" and cmd.startswith("(", i + 1):
            return "process substitution"
        if c == ">":
            rest = cmd[i + 1:]
            if rest.startswith("&") or re.match(r">?\s*/dev/null\b", rest):
                i += 1
                continue
            return "an output redirect (it writes a file)"
        i += 1
    return None


def show(items, k=8):
    s = ", ".join(items[:k])
    return s + (", ..." if len(items) > k else "") if items else "(empty: nothing allowed)"


def main():
    try:
        d = json.loads(sys.stdin.read() or "{}")
    except Exception:
        out("ALLOW")
    if not isinstance(d, dict):
        out("ALLOW")
    agent_id, agent = d.get("agent_id"), d.get("agent_type")
    if not agent_id or not isinstance(agent, str) or not agent:
        out("ALLOW")  # main session (or --agent): never restricted here
    tool = d.get("tool_name") or ""
    if tool not in TOOL_KEYS and tool not in ("Agent", "Workflow"):
        out("ALLOW")
    ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}

    hooks_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, hooks_dir)
    try:
        from lib_poison_patterns import resolve_agent_defs, msys_path
    except Exception as e:
        note("shared resolver not importable (%s); call not checked" % e)
        out("ALLOW")

    home = msys_path(os.environ.get("HOME", ""))
    cwd = msys_path(d.get("cwd") or os.environ.get("PWD_DIR") or os.getcwd())
    root = project_root(cwd)
    bases = []
    for b in (root, msys_path(os.environ.get("CLAUDE_PROJECT_DIR", "")), cwd):
        if b and b not in bases:
            bases.append(b)

    deff, allow, notes = find_definition(agent, home, bases, resolve_agent_defs)
    for nt in notes:
        note(nt)
    if deff is None or not allow:
        out("ALLOW")

    def deny(what, subject, key):
        pats = allow[key]
        reason = ("subagent '%s' may only %s on the %s.%s list in %s: %s. %s is not on it."
                  % (agent, what, KEY, key, deff, show(pats), subject))
        remedy = ("stay inside the list, or hand this step back to the parent session in your "
                  "report. Only the user widens the list.")
        out("DENY", reason, remedy)

    if tool in ("Agent", "Workflow"):
        reason = ("subagent '%s' declares a %s list in %s, and a nested %s would run "
                  "outside it." % (agent, KEY, deff, "subagent" if tool == "Agent" else "workflow"))
        out("DENY", reason, "do the work yourself inside the list, or hand it back to the parent session.")

    key = TOOL_KEYS[tool]

    if key == "write":
        p = ti.get("file_path") if tool != "NotebookEdit" else (ti.get("notebook_path") or ti.get("file_path"))
        if not isinstance(p, str) or not p.strip():
            out("ALLOW")  # nothing to write; the tool fails on its own
        p = norm_tool_path(p, home)
        real = os.path.realpath(p if os.path.isabs(p) else os.path.join(cwd, p))
        # Its own definition is never writable while it carries a list: an agent
        # that can rewrite its list has no list.
        if real == os.path.realpath(deff):
            out("DENY", "subagent '%s' may not edit its own definition %s, which holds its %s list."
                % (agent, deff, KEY), "hand this step back to the parent session.")
        if key not in allow:
            out("ALLOW")
        if path_allowed(real, root, allow[key], home):
            out("ALLOW")
        deny("write files", "`%s` (resolves to %s, project root %s)" % (p, real, root), key)

    if key not in allow:
        out("ALLOW")

    if key == "webfetch":
        url = ti.get("url")
        if not isinstance(url, str) or not url.strip():
            out("ALLOW")
        host = host_of(url)
        if host and host_allowed(host, allow[key]):
            out("ALLOW")
        deny("fetch from hosts", "`%s` (host %s)" % (url[:200], host or "unreadable, or not http/https"), key)

    # bash
    cmd = ti.get("command")
    if not isinstance(cmd, str) or not cmd.strip():
        out("ALLOW")  # Monitor's ws form carries no command
    bad = unsafe_shell(cmd)
    if bad:
        reason = ("subagent '%s' runs under the %s.bash list in %s, which cannot vouch for %s. "
                  "Allowed: %s." % (agent, KEY, deff, bad, show(allow[key])))
        out("DENY", reason, "run the allowed command on its own, without substitution or redirects; "
            "or hand this step back to the parent session.")
    pats = [p for p in allow[key] if US not in p]
    # fd duplications and /dev/null redirects write nothing, but their `&` would
    # read as a separator to split_segments (`2>&1` -> `... 2>` and `1`).
    cmd = re.sub(r"(?:\d*|&)>>?\s*/dev/null\b|\d*>&(?:\d+|-)", " ", cmd)
    out("SEG", agent, deff, "\n".join(pats), cmd)


if __name__ == "__main__":
    main()
