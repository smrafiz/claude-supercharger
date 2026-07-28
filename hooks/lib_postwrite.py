#!/usr/bin/env python3
"""Post-write advisory engine — shared by post-write-advisor.sh.

Folds three PostToolUse:Write advisory checks (formerly conflict-marker-guard,
config-validity-guard, shebang-exec-guard) into ONE process that reads the final
on-disk file a single time. Reads HOOK_INPUT + the environment; prints the combined
PostToolUse additionalContext JSON (or nothing). Each check honours its original
per-check kill-switch env var, plus the master SUPERCHARGER_POST_WRITE_ADVISOR=0.
"""
import os
import re
import sys
import json

# --- conflict markers -------------------------------------------------------
_CONFLICT_SKIP = {".md", ".markdown", ".mdx", ".rst", ".txt", ".adoc", ".org",
                  ".eml", ".mbox", ".patch", ".diff", ".rej"}
_START = re.compile(r'^' + '<' * 7 + r' ', re.M)
_END = re.compile(r'^' + '>' * 7 + r' ', re.M)
_MID = re.compile(r'^' + '=' * 7 + r'$', re.M)


def _ext(path):
    base = path.rsplit("/", 1)[-1].lower()
    return "." + base.rsplit(".", 1)[-1] if "." in base else ""


def check_conflict(path, text):
    if _ext(path) in _CONFLICT_SKIP or not text:
        return None
    hits = []
    if _START.search(text):
        hits.append('<' * 7)
    if _END.search(text):
        hits.append('>' * 7)
    if hits and _MID.search(text):
        hits.append('=' * 7)
    if not hits:
        return None
    return ("[merge conflict] The written file contains unresolved git conflict "
            "marker(s): %s. This is a half-resolved or accidentally-written merge "
            "conflict — the file won't compile/parse. Remove the markers and keep "
            "the intended content before it fails at build/run." % " ".join(hits))


# --- structured-config validity --------------------------------------------
def check_validity(path, text):
    low = path.lower()
    if low.endswith(".json"):
        fmt = "json"
    elif low.endswith((".yaml", ".yml")):
        fmt = "yaml"
    elif low.endswith(".toml"):
        fmt = "toml"
    else:
        return None
    if not text:
        return None
    err = None
    if fmt == "json":
        try:
            json.loads(text)
        except Exception as e:
            stripped = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
            stripped = re.sub(r'(^|[^:])//[^\n]*', lambda m: m.group(1), stripped)
            stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
            try:
                json.loads(stripped)
            except Exception:
                err = str(e)
    elif fmt == "yaml":
        try:
            import yaml
        except Exception:
            return None
        try:
            yaml.safe_load(text)
        except Exception as e:
            err = str(e).replace("\n", " ")
    elif fmt == "toml":
        try:
            import tomllib
        except Exception:
            return None
        try:
            tomllib.loads(text)
        except Exception as e:
            err = str(e)
    if not err:
        return None
    return ("[invalid %s] The file just written does not parse as %s: %s. This will "
            "fail at the next tool that reads it (npm/tsc/CI/loader). Fix the syntax "
            "— likely a trailing comma, unbalanced brace/bracket, or bad indentation "
            "— before continuing." % (fmt.upper(), fmt.upper(), err[:300]))


# --- shebang without executable bit ----------------------------------------
def check_shebang(path, first_line, mode):
    if not first_line.startswith("#!") or mode is None or (mode & 0o111):
        return None
    interp = first_line[2:].strip()[:60] or "a shebang"
    base = path.rsplit("/", 1)[-1]
    return ("[not executable] The file just written starts with a shebang (%s) but "
            "is mode 0644 — running it directly (e.g. ./%s) will fail with "
            "'permission denied'. Run: chmod +x %s  (ignore this if you source the "
            "file instead of executing it)." % (interp, base, path))


def run(hook_input, env):
    try:
        d = json.loads(hook_input)
    except Exception:
        return []
    if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
        return []
    ti = d.get("tool_input") or {}
    path = ti.get("file_path") or ""
    if not path:
        return []

    # Read the FINAL on-disk file once (post-write); fall back to tool_input content
    # only if the file isn't on disk (rare — then shebang mode is unknowable).
    text = ""
    mode = None
    if os.path.isfile(path):
        try:
            with open(path, "r", errors="replace") as f:
                text = f.read(1024 * 1024)
        except Exception:
            text = ""
        try:
            mode = os.stat(path).st_mode
        except Exception:
            mode = None
    if not text:
        text = ti.get("content") or ti.get("new_string") or ""
        if not text and isinstance(ti.get("edits"), list):
            text = "\n".join(str(e.get("new_string", "")) for e in ti["edits"] if isinstance(e, dict))
    first = text.split("\n", 1)[0] if text else ""

    warns = []
    if env.get("SUPERCHARGER_CONFLICT_MARKER_GUARD") != "0":
        w = check_conflict(path, text)
        if w:
            warns.append(w)
    if env.get("SUPERCHARGER_CONFIG_VALIDITY_GUARD") != "0":
        w = check_validity(path, text)
        if w:
            warns.append(w)
    if env.get("SUPERCHARGER_SHEBANG_EXEC_GUARD") != "0":
        w = check_shebang(path, first, mode)
        if w:
            warns.append(w)
    return warns


if __name__ == "__main__":
    ws = run(os.environ.get("HOOK_INPUT", ""), os.environ)
    if ws:
        msg = "\n\n".join(ws) + "\n\n(Disable: SUPERCHARGER_POST_WRITE_ADVISOR=0, or a single check via its own SUPERCHARGER_*_GUARD=0)"
        sys.stdout.write(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse", "additionalContext": msg}}))
