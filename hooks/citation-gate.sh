#!/usr/bin/env bash
# Claude Supercharger — Citation Gate
# Event: Stop | Matcher: *
#
# CLAUDE.md says never fabricate sources; that is a prompt rule. This is the
# evidence check, a sibling of claim-evidence-gate: every URL in the reply that
# just ended must have appeared somewhere in this session outside Claude's own
# prose: a prompt the user wrote, a tool call, or a tool result (WebFetch,
# WebSearch, gh, curl...). A URL seen nowhere else may be invented, so the user
# gets a one-line warning naming it. Never blocks: a well-known docs URL written
# from memory is often right, and the reader decides.
#
# Placeholder hosts (example.com, localhost, 127.0.0.1) are ignored.
#
# 2026-11-07: commit hashes too, in backticks or after "commit". Replay over 42
# transcripts: 1197 hashes cited, 1 seen nowhere else, and it was invented (the real
# commit's hash was never printed; the reply made one up). A hash is evidenced when its
# first 7 characters appear: tools print short hashes, replies often cite longer ones.
# Stop fires every turn: the fast path greps the transcript tail for a URL first,
# and the full scan only json-parses lines that contain one of the candidates.
# Fail-open. Disable: SUPERCHARGER_CITATION_GATE=0
set -uo pipefail
# lib-timing carries the /sc off kill-switch every hook must honour.
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true
[ "${SUPERCHARGER_CITATION_GATE:-1}" = "0" ] && exit 0

. "${BASH_SOURCE[0]%/*}/lib-stdin.sh" 2>/dev/null || true
_INPUT=""
if command -v sc_read_input_warn >/dev/null 2>&1; then
  sc_read_input_warn _INPUT "citation-gate"
fi
case "$_INPUT" in *'"stop_hook_active":true'*) exit 0 ;; esac

TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

tail -c 40000 "$TRANSCRIPT" 2>/dev/null | LC_ALL=C grep -qE 'https?://|`[0-9a-f]{7,40}`|commit [0-9a-f]{7}' || exit 0

# Output goes to a file, not $(...): a quote char in a heredoc inside $() can cut
# the script short (see heredoc-in-substitution-quoting).
_CG_OUT=$(mktemp 2>/dev/null) || _CG_OUT="${TMPDIR:-/tmp}/citegate.$$"
TRANSCRIPT_PATH="$TRANSCRIPT" python3 > "$_CG_OUT" 2>/dev/null <<'PYEOF'

import json, os, re, sys

path = os.environ.get("TRANSCRIPT_PATH", "")
URL = re.compile(r"https?://[^\s<>\"'`)\]}|\\]+")
PLACEHOLDER = re.compile(r"^https?://([^/]*\.)?(example\.(com|org|net)|localhost|127\.0\.0\.1|0\.0\.0\.0)([:/]|$)", re.I)


def norm(u):
    u = u.rstrip(".,;:!?*_")
    u = u.split("#", 1)[0]
    return u.rstrip("/")


def entries(lines):
    for ln in lines:
        try:
            yield json.loads(ln)
        except Exception:
            continue


def is_prompt(e):
    if e.get("type") != "user":
        return False
    c = (e.get("message") or {}).get("content")
    if isinstance(c, str):
        return True
    return isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "text" for b in c)


try:
    # The last ~4 MB holds the latest turn; never read a whole transcript here.
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 4_000_000))
        tail = f.read().decode("utf-8", "replace").splitlines()[1:][-400:]
except Exception:
    sys.exit(0)

# The reply that just ended: assistant text after the last prompt the user wrote.
reply = []
for e in entries(tail):
    if is_prompt(e):
        reply = []
    elif e.get("type") == "assistant":
        for b in (e.get("message") or {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "text":
                reply.append(b.get("text") or "")

cands = {}
for u in URL.findall("\n".join(reply)):
    n = norm(u)
    if n.count("/") >= 2 and "." in n.split("/")[2] and not PLACEHOLDER.match(n):
        cands.setdefault(n, u.rstrip(".,;:!?*_"))
# Commit hashes: backticked or after "commit"; a digit and a letter, so a word or a
# number is not one. Keyed by the 7-char prefix that evidence must contain.
SHA = re.compile(r"(?:`|\bcommits? )([0-9a-f]{7,40})(?![0-9a-zA-Z_])")
for h in SHA.findall("\n".join(reply)):
    if re.search(r"\d", h) and re.search(r"[a-f]", h):
        cands.setdefault(h[:7], h)
if not cands:
    sys.exit(0)

# Evidence: the whole transcript, minus Claude's own prose and thinking.
# Transcripts reach hundreds of MB, so grep -F (C speed) picks the lines that
# hold a candidate and only those are json-parsed.
import subprocess, tempfile
unseen = set(cands)
try:
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".pat") as pf:
        pf.write("\n".join(unseen) + "\n")
        patfile = pf.name
    hits_out = subprocess.run(["grep", "-F", "-f", patfile, path], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=8,
                              env=dict(os.environ, LC_ALL="C")).stdout.decode("utf-8", "replace")
    os.unlink(patfile)
except Exception:
    sys.exit(0)
for ln in hits_out.splitlines():
    if not unseen:
        break
    hits = [n for n in unseen if n in ln]
    if not hits:
        continue
    try:
        e = json.loads(ln)
    except Exception:
        continue
    if e.get("type") == "assistant":
        blocks = (e.get("message") or {}).get("content") or []
        text = json.dumps([b for b in blocks if isinstance(b, dict) and b.get("type") not in ("text", "thinking")])
    else:
        text = json.dumps(e)
    for n in hits:
        if n in text:
            unseen.discard(n)

if unseen:
    shown = [cands[n] for n in sorted(unseen)][:5]
    print("[Supercharger] citation-gate: this reply cites link(s) or commit(s) that never appeared in "
          "this session (not fetched, searched, opened or returned by a tool), so they may be invented: "
          + ", ".join(shown) + ". Check them before relying on them.")
PYEOF
MSG=$(cat "$_CG_OUT" 2>/dev/null); rm -f "$_CG_OUT" 2>/dev/null
[ -n "$MSG" ] || exit 0
printf '%s' "$MSG" | jq -Rs '{systemMessage: .}' 2>/dev/null || true
exit 0
