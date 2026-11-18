#!/usr/bin/env bash
# Claude Supercharger — Office Read
# Event: PreToolUse | Matcher: Read
# Opt-in: redirects a Read of a PDF or Office file to a cached markitdown conversion.
# 2026-11-17, from tsrmehmet/memokit (MIT) convert-read.sh. A PDF Read costs page
# images plus text, and a .docx/.pptx/.xlsx Read gets nothing useful; markitdown's
# Markdown is a fraction of either. Opt in with SUPERCHARGER_MARKITDOWN=1 and
# markitdown on PATH (pip install 'markitdown[all]'). Stays out, never denies:
#   - a Read with `pages` (the model asked for page images), a file outside
#     CLAUDE_PROJECT_DIR (or resolving outside it through a symlink);
#   - ANY Read deny/ask rule in a settings file: Claude Code checks permission rules
#     against the input a hook returns, so a redirect would sidestep a rule naming
#     the original path.
# Cache: $SUPERCHARGER_STATE/office-read/<sha256 of the file>/<name>.md — a changed
# file gets a new key. A failed or empty conversion falls back to the normal Read.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-stdin.sh
. "$HOOKS_DIR/lib-stdin.sh"; sc_read_input _INPUT
[ "${SUPERCHARGER_MARKITDOWN:-0}" = 1 ] || exit 0
case "$_INPUT" in *.[pP][dD][fF]\"*|*.[dD][oO][cC][xX]\"*|*.[pP][pP][tT][xX]\"*|*.[xX][lL][sS][xX]\"*) ;; *) exit 0 ;; esac
command -v markitdown >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
check_hook_disabled "office-read" && exit 0

printf '%s' "$_INPUT" | CACHE="$SUPERCHARGER_STATE/office-read" python3 -c '
import glob, hashlib, json, os, re, subprocess, sys, tempfile
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
fp = ti.get("file_path") or ""
if d.get("tool_name") != "Read" or ti.get("pages") or not os.path.isabs(fp):
    sys.exit(0)
if not re.search(r"\.(pdf|docx|pptx|xlsx)$", fp, re.I) or not os.path.isfile(fp):
    sys.exit(0)
proj = os.path.realpath(os.environ["CLAUDE_PROJECT_DIR"])
real = os.path.realpath(fp)
if proj == "/" or not real.startswith(proj + os.sep):
    sys.exit(0)
# Any Read deny/ask rule, in any settings file we can see: stay out.
# shortcut: a --settings file on the command line is invisible to a hook, so a Read rule there is not seen, upgrade if Claude Code exposes it to hooks.
home = os.environ.get("HOME", "")
cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude")
files = [os.path.join(cfg, "settings.json"), os.path.join(cfg, "settings.local.json"),
         os.path.join(home, ".claude", "settings.json"), os.path.join(home, ".claude", "settings.local.json"),
         os.path.join(proj, ".claude", "settings.json"), os.path.join(proj, ".claude", "settings.local.json")]
for md in ("/Library/Application Support/ClaudeCode", "/etc/claude-code", "C:\\Program Files\\ClaudeCode"):
    files.append(os.path.join(md, "managed-settings.json"))
    files += sorted(glob.glob(os.path.join(glob.escape(md), "managed-settings.d", "*.json")))
for s in files:
    try:
        perms = json.load(open(s)).get("permissions") or {}
    except Exception:
        continue
    if any(str(r).startswith("Read") for k in ("deny", "ask") for r in (perms.get(k) or [])):
        sys.exit(0)
h = hashlib.sha256()
with open(real, "rb") as f:
    for blk in iter(lambda: f.read(1 << 20), b""):
        h.update(blk)
key = h.hexdigest()[:32]
kdir = os.path.join(os.environ["CACHE"], key)
out = os.path.join(kdir, os.path.basename(fp)[:120] + ".md")
if not (os.path.isfile(out) and not os.path.islink(out) and os.path.getsize(out) > 0):
    os.makedirs(kdir, mode=0o700, exist_ok=True)
    # shutil.which honours PATHEXT: Windows CreateProcess finds only a bare .exe itself.
    import shutil
    exe = shutil.which("markitdown")
    if not exe:
        sys.exit(0)
    # Inner timeout stays under the hook timeout (15s) so the hook is never killed mid-convert.
    tmo = float(os.environ.get("SUPERCHARGER_OFFICE_READ_TIMEOUT") or 10)
    cap = int(os.environ.get("SUPERCHARGER_OFFICE_READ_MAX") or 2000000)
    posix = os.name != "nt"
    try:
        p = subprocess.Popen([exe, real], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=posix)
    except Exception:
        sys.exit(0)
    try:
        so, _ = p.communicate(timeout=tmo)
    except BaseException:
        try:
            if posix:
                os.killpg(p.pid, 9)
            else:
                p.kill()
        except Exception:
            pass
        p.communicate()
        sys.exit(0)
    if p.returncode != 0 or not so.strip() or len(so) > cap:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=kdir)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(so)
        os.replace(tmp, out)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        sys.exit(0)
ti2 = dict(ti, file_path=out)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
    "permissionDecisionReason": "office-read: Markdown conversion of " + fp,
    "updatedInput": ti2,
    "additionalContext": "[office-read] Read the markitdown conversion of " + fp + " instead of the binary. Read it with pages= for the original page images."}}))
' 2>/dev/null
exit 0
