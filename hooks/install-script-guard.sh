#!/usr/bin/env bash
# Claude Supercharger — Install Script Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# npm/pnpm/yarn/bun run lifecycle scripts automatically on `install`
# (preinstall/install/postinstall/prepare/prepublish/prepack/…); a Python
# setup.py runs arbitrary code at install time too. Adding or changing one of
# those is a prime supply-chain persistence vector — it executes on the next
# install, in CI, on a teammate's machine — and is trivial to miss in review.
# lockfile-integrity-guard guards the lockfile and dep-vuln-scanner audits
# installed deps; neither inspects manifest lifecycle fields. This ASKS when a
# manifest edit ADDS/CHANGES a lifecycle script, or introduces one whose command
# reaches the network or evals code (curl/wget/node -e/python -c/base64/…).
# Advisory + fail-open; disable with SUPERCHARGER_INSTALL_SCRIPT_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_INSTALL_SCRIPT_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
check_hook_disabled "install-script-guard" 2>/dev/null && exit 0

# v2.24.2: fork-free gate — see package-source-guard for the rationale. This hook
# only inspects package.json / setup.py / binding.gyp / *.gyp / *.gypi, but was
# forking python3 (~28ms) on every Write/Edit. Superset match on the raw payload:
# a miss can't skip a real target, a spurious hit just runs the unchanged python.
case "$_INPUT" in
  *package.json*|*setup.py*|*.gyp*|*[Ss]etup.PY*) : ;;
  *) exit 0 ;;
esac

REASON=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import os, sys, json, re

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

tool = d.get("tool_name") or ""
if tool not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

inp = d.get("tool_input") or {}
fp = inp.get("file_path") or ""
base = os.path.basename(fp).lower()
KIND = None
if base in ("package.json",):
    KIND = "npm"
elif base in ("setup.py",):
    KIND = "pysetup"
elif base == "binding.gyp" or base.endswith((".gyp", ".gypi")):
    KIND = "gyp"   # v2.23.26: node-gyp runs binding.gyp actions during `npm install`
if KIND is None:
    sys.exit(0)

# Build old/new text.
if tool == "Write":
    new = inp.get("content")
    if new is None:
        sys.exit(0)
    try:
        with open(fp, "r", errors="replace") as f:
            old = f.read()
    except Exception:
        old = ""
elif tool == "Edit":
    old = inp.get("old_string") or ""
    new = inp.get("new_string") or ""
else:  # MultiEdit
    old = "\n".join((e.get("old_string") or "") for e in (inp.get("edits") or []))
    new = "\n".join((e.get("new_string") or "") for e in (inp.get("edits") or []))

SUSPICIOUS = re.compile(
    r"curl|wget|fetch\b|node\s+-e|node\s+--eval|--eval|python3?\s+-c|base64|eval\b|"
    r"/dev/tcp|https?://|(^|[^a-z])nc\s|ncat|chmod|\bexec\b|\||>",
    re.I)

hits = []

if KIND == "npm":
    LIFECYCLE = (r'preinstall|install|postinstall|prepare|prepublish|prepublishOnly'
                 r'|prepack|postpack|preuninstall|postuninstall|dependencies')
    # note: "install"/"dependencies" as bare words are too broad, so we match the
    # JSON key form "<name>": "<command>" only.
    pat = re.compile(r'"(' + LIFECYCLE + r')"\s*:\s*"((?:[^"\\]|\\.)*)"')
    def scripts(text):
        out = {}
        for m in pat.finditer(text):
            k = m.group(1)
            if k == "dependencies":     # skip the deps object key false-positive
                continue
            out.setdefault(k, m.group(2))
        return out
    old_s, new_s = scripts(old), scripts(new)
    editing_existing = bool(old.strip())
    for k, cmd in new_s.items():
        changed = (k not in old_s) or (old_s.get(k) != cmd)
        if not changed:
            continue
        if SUSPICIOUS.search(cmd or ""):
            hits.append("%s = %s (network/eval)" % (k, (cmd or "")[:80]))
        elif editing_existing:
            hits.append("%s = %s" % (k, (cmd or "")[:80]))
        # brand-new manifest with a benign lifecycle script (e.g. husky) is not flagged

elif KIND == "pysetup":
    # setup.py runs at install; adding a shell-out / eval that was not there before
    # is the risk. (Generic eval/exec is also caught by code-security-scanner; here
    # it is specifically install-time execution in a manifest.)
    PY_EXEC = re.compile(r"os\.system\(|subprocess\.|__import__\(|\bexec\(|check_output\(|Popen\(")
    if PY_EXEC.search(new) and not PY_EXEC.search(old):
        m = PY_EXEC.search(new)
        hits.append("setup.py adds install-time code execution (%s…)" % new[m.start():m.start()+40].replace("\n", " "))

elif KIND == "gyp":
    # v2.23.26: node-gyp executes a binding.gyp during `npm install` (config/gyp
    # phase — before pre/postinstall). A weaponized "action" or a `<!(cmd)`
    # command-expansion runs arbitrary shell then. Flag added exec, not the whole
    # (benign compile) file: an added `"action"` block, a `<!(…)`/`<!@(…)` command
    # expansion, or a shell-out token inside the diff.
    GYP_EXEC = re.compile(r'"action"\s*:|<!@?\(|"/bin/sh"|"cmd"|"powershell"|'
                          r'curl|wget|node\s+-e|python3?\s+-c|base64|\beval\b|/dev/tcp')
    if GYP_EXEC.search(new) and not GYP_EXEC.search(old):
        m = GYP_EXEC.search(new)
        hits.append("binding.gyp adds an install-time action/command-expansion (%s…)"
                    % new[m.start():m.start()+40].replace("\n", " "))

if not hits:
    sys.exit(0)

print("install-script: this %s edit adds/changes an install-time script — %s. "
      "It runs automatically on the next install (locally, in CI, on teammates' "
      "machines) — a common supply-chain persistence vector. Confirm it is intended."
      % (os.path.basename(fp), "; ".join(hits[:3])))
PYEOF
)

[ -z "$REASON" ] && exit 0

RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] install-script-guard: ASK on manifest lifecycle-script change" >&2
exit 0
