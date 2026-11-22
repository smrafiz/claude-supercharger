

# 2026-11-22: the same rule across separate Bash calls. Each file a download writes goes
# into a per-session ledger (DL_LEDGER, set by safety.sh); a later command that makes a
# recorded file executable or runs it ASKS (user decision 2026-11-22: ask, not deny, and a
# Read in between does not clear it). Relative paths resolve against the session cwd.
_DL_LEDGER_MAX = 200


def _dl_ledger_paths(c: str, base: str) -> tuple[list[str], list[tuple[str, str]]]:
    """Return (files this command downloads, [(segment, its cwd)])."""
    parts = _DL_SPLIT_RE.split(c)
    segs, seps = parts[0::2], parts[1::2]
    cwd, outs, segcwd = base, [], []
    for i, seg in enumerate(segs):
        segcwd.append((seg, cwd))
        toks = _dl_words(seg)
        if len(toks) == 2 and toks[0] == "cd":
            cwd = _dl_path(toks[1], cwd)
            continue
        o = _dl_outputs(seg)
        j = i
        while j + 1 < len(segs) and seps[j] == "|" and toks[:1] in (["curl"], ["wget"]) \
                and _dl_words(segs[j + 1])[:1] == ["tee"]:
            o += [t for t in _dl_words(segs[j + 1])[1:] if not t.startswith(("-", ">"))]
            j += 1
        outs += [_dl_path(p, cwd) for p in o]
    return outs, segcwd


def check_download_ledger(c: str) -> str | None:
    ledger = os.environ.get("DL_LEDGER", "")
    if not ledger:
        return None
    base = os.environ.get("CWD", "")
    outs, segcwd = _dl_ledger_paths(c, base)
    try:
        with open(ledger, encoding="utf-8") as f:
            known = [ln.rstrip("\n") for ln in f if ln.strip()]
    except OSError:
        known = []
    reason = None
    for p in dict.fromkeys(known):
        if any(_dl_runs(seg, p, cwd) for seg, cwd in segcwd):
            reason = (f"__SC_ASK__makes {p} executable or runs it; that file was downloaded earlier "
                      "in this session and nobody has reviewed it")
            break
    if outs:
        try:
            keep = [k for k in known if k not in outs] + list(dict.fromkeys(outs))
            with open(ledger, "w", encoding="utf-8") as f:
                f.write("\n".join(keep[-_DL_LEDGER_MAX:]) + "\n")
        except OSError:
            pass
    return reason
