#!/usr/bin/env bash
# Claude Supercharger — Package Source Guard
# Event: PreToolUse | Matcher: Write, Edit, MultiEdit
#
# Supply-chain: flags a dependency added/changed to point at a NON-REGISTRY
# source — a tarball/wheel URL, a git+/git:// or github:owner/repo shorthand, a
# file:/local path outside the project, or a registry-override (npm
# overrides/resolutions, pip --index-url, poetry/cargo custom source) that can
# pin a package to an attacker-controlled index (dependency confusion). The three
# existing supply-chain hooks each guard a DIFFERENT facet — install-script-guard
# = lifecycle scripts, lockfile-integrity-guard = lockfile hash, dep-vuln-scanner
# = known CVEs (post-install). The ORIGIN of a newly-added dependency is
# unguarded, and a malicious source runs before dep-vuln-scanner ever sees it.
# ASKS (dep-from-source is occasionally legit); asks once per source per session.
# Advisory + fail-open; disable with SUPERCHARGER_PACKAGE_SOURCE_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_PACKAGE_SOURCE_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
check_hook_disabled "package-source-guard" 2>/dev/null && exit 0

# v2.24.2: fork-free gate. This hook only cares about seven dependency manifests, but
# it was starting a ~28ms python3 for EVERY Write/Edit — including source files it can
# never match — which made it the slowest hook in the 20-wide Write wave. The patterns
# below are a deliberate SUPERSET of the python's basename test (they match anywhere in
# the payload, and cover the case variants python gets via .lower()), so a gate miss
# can never skip a file the guard would have flagged; a spurious match just falls
# through to the unchanged python.
case "$_INPUT" in
  *package.json*|*[Pp]yproject.toml*|*[Pp]ipfile*|*[Pp]ipFile*|*requirements*|*[Rr]equirements*|\
  *[Gg]emfile*|*go.mod*|*[Cc]argo.toml*|*[Cc]argo.TOML*) : ;;
  *) exit 0 ;;
esac

_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$_SID" ] && _SID="${CLAUDE_CODE_SESSION_ID:-default}"
_SEEN_FILE="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.pkgsrc-seen-${_SID}"

# NB: the python heredoc is redirected to a temp file rather than captured via
# $(python3 <<'PYEOF' … ) — bash 3.2's old-style command-substitution parser
# mis-scans a heredoc body this regex-heavy (many parens/quotes) and aborts with
# a bogus "unexpected EOF". A plain (non-nested) heredoc parses correctly.
_PSG_OUT=$(mktemp 2>/dev/null) || _PSG_OUT="${TMPDIR:-/tmp}/pkgsrc-guard.$$"
HOOK_INPUT="$_INPUT" SEEN_FILE="$_SEEN_FILE" python3 > "$_PSG_OUT" 2>/dev/null <<'PYEOF'
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
if base == "package.json":
    KIND = "npm"
elif base == "pyproject.toml":
    KIND = "pyproject"
elif base == "pipfile":
    KIND = "pipfile"
elif base.startswith("requirements") and base.endswith(".txt"):
    KIND = "pyreq"
elif base == "gemfile":
    KIND = "gem"
elif base == "go.mod":
    KIND = "go"
elif base == "cargo.toml":
    KIND = "cargo"
if KIND is None:
    sys.exit(0)

# --- old/new text (same shape as install-script-guard) ---
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

hits = []          # human-readable
sources = []       # dedup keys

# A version-spec value that is NOT a plain registry range (^1.0, ~2, 1.x, *,
# "workspace:*", "catalog:", a bare tag/branch for git-less). These are the
# non-registry origins we ask about.
NONREG = re.compile(
    r'^\s*(git\+|git://|git@|github:|gitlab:|bitbucket:|https?://|http:|file:|link:|portal:)',
    re.I)

def add(desc, key):
    hits.append(desc); sources.append(key)

if KIND == "npm":
    DEP_KEYS = ("dependencies", "devDependencies", "optionalDependencies",
                "peerDependencies", "overrides", "resolutions")
    def dep_map(text):
        try:
            j = json.loads(text)
        except Exception:
            return None
        out = {}
        for dk in DEP_KEYS:
            v = j.get(dk)
            if isinstance(v, dict):
                for name, spec in v.items():
                    if isinstance(spec, str):
                        out[dk + "/" + name] = spec
        return out
    nm, om = dep_map(new), dep_map(old)
    if nm is not None:
        om = om or {}
        for name, spec in nm.items():
            if (name not in om or om[name] != spec) and NONREG.match(spec):
                short = name.split("/", 1)[1]
                add("%s -> %s" % (short, spec[:80]), spec.strip())
    else:
        # Edit fragment isn't valid JSON — scan added lines for a name:source pair.
        oldset = set(old.splitlines())
        for line in new.splitlines():
            if line in oldset:
                continue
            m = re.search(r'"[\w@./-]+"\s*:\s*"([^"]+)"', line)
            if m and NONREG.match(m.group(1)):
                add(m.group(1)[:80], m.group(1).strip())
else:
    # Line-scan added lines with per-ecosystem source markers.
    PATTERNS = {
        "pyproject": [
            (re.compile(r'\bgit\s*=\s*["\']', re.I),            "git source"),
            (re.compile(r'\burl\s*=\s*["\']https?://', re.I),   "url source"),
            (re.compile(r'\bpath\s*=\s*["\']', re.I),           "local path source"),
            (re.compile(r'\[\[tool\.poetry\.source\]\]', re.I), "custom package index"),
            (re.compile(r'@\s*git\+', re.I),                    "git+ dependency"),
            (re.compile(r'@\s*https?://', re.I),                "url dependency"),
        ],
        "pipfile": [
            (re.compile(r'\bgit\s*=\s*["\']', re.I),          "git source"),
            (re.compile(r'\bpath\s*=\s*["\']', re.I),         "local path source"),
            (re.compile(r'\[\[source\]\]', re.I),             "custom package index"),
            (re.compile(r'\bref\s*=\s*["\']', re.I),          "git ref pin"),
        ],
        "pyreq": [
            (re.compile(r'(^|\s)-e\s', re.I),                          "editable install"),
            (re.compile(r'\bgit\+', re.I),                             "git+ url"),
            (re.compile(r'@\s*https?://', re.I),                       "direct url dependency"),
            (re.compile(r'https?://\S+\.(whl|tar\.gz|zip|tgz)', re.I), "tarball/wheel url"),
            (re.compile(r'--(extra-)?index-url|(^|\s)-i\s+https?://', re.I), "custom package index"),
        ],
        "gem": [
            (re.compile(r'\bgit:\s*["\']', re.I),      "git source"),
            (re.compile(r'\bgithub:\s*["\']', re.I),   "github shorthand"),
            (re.compile(r'\bpath:\s*["\']', re.I),     "local path source"),
            (re.compile(r'\bsource\s+["\']https?://(?!rubygems\.org)', re.I), "non-rubygems source"),
        ],
        "go": [
            (re.compile(r'^\s*replace\s', re.I),                    "replace directive"),
            (re.compile(r'=>\s*\.{0,2}/', ),                        "local module replace"),
        ],
        "cargo": [
            (re.compile(r'\bgit\s*=\s*["\']', re.I),   "git source"),
            (re.compile(r'\bpath\s*=\s*["\']', re.I),  "local path source"),
            (re.compile(r'\[source\.', re.I),          "source replacement"),
            (re.compile(r'\bregistry\s*=\s*["\']', re.I), "custom registry"),
        ],
    }.get(KIND, [])
    oldset = set(old.splitlines())
    for line in new.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or line in oldset:
            continue
        for rx, label in PATTERNS:
            if rx.search(line):
                add("%s: %s" % (label, s[:80]), s)
                break

if not hits:
    sys.exit(0)

# Ask once per source per session.
seen_path = os.environ.get("SEEN_FILE", "")
seen = set()
if seen_path and os.path.exists(seen_path):
    try:
        with open(seen_path, "r", errors="replace") as f:
            seen = set(l.rstrip("\n") for l in f)
    except Exception:
        seen = set()

fresh_idx = [i for i, k in enumerate(sources) if k not in seen]
if not fresh_idx:
    sys.exit(0)
if seen_path:
    try:
        os.makedirs(os.path.dirname(seen_path), exist_ok=True)
        with open(seen_path, "a") as f:
            for i in fresh_idx:
                f.write(sources[i] + "\n")
    except Exception:
        pass

shown = [hits[i] for i in fresh_idx][:3]
print("package-source: this %s edit adds/changes a dependency from a NON-REGISTRY "
      "source — %s. A tarball/git/file/custom-index origin bypasses the registry "
      "(dependency-confusion / supply-chain risk) and runs before any CVE scan. "
      "Confirm the source is trusted." % (os.path.basename(fp), "; ".join(shown)))
PYEOF
REASON=$(cat "$_PSG_OUT" 2>/dev/null)
rm -f "$_PSG_OUT" 2>/dev/null

[ -z "$REASON" ] && exit 0

RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] package-source-guard: ASK on non-registry dependency source" >&2
exit 0
