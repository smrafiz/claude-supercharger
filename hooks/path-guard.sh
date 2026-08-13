#!/usr/bin/env bash
# Claude Supercharger — Path Guard
# Event: PreToolUse | Matcher: Write,Edit
# Hardens Write/Edit against path-based attacks:
#   - Path traversal (../../../etc/passwd, %2e%2e, double-encode, null bytes)
#   - Symlink attacks (resolved path outside project root)
#   - Git internals (.git/hooks/, .git/refs/, ~/.claude/hooks/)
#   - Absolute-path writes outside project root (~/.ssh, ~/.aws, /etc/, ...)
#   - Build artifact injection (node_modules/.bin, .next, .venv, vendor/, dist/)
#
# Each category is opt-out via .supercharger.json:
#   {"disableSecurityCategories": ["path-traversal", "symlink", "git-internals",
#                                   "selfmod", "abs-path", "build-artifacts"]}
# Disable: SUPERCHARGER_PATH_GUARD=0
# Debug:   SC_PATHGUARD_DEBUG=1 — trace each gate to stderr (never stdout, which
#          carries the verdict). Off by default; added after six probes failed to
#          explain a Windows verdict and tracing the real gates settled it in one.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_PATH_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
# v2.6.36: PROJECT_DIR stays as the actual CWD (used as boundary for symlink/
# abs-path checks — writes within the linked worktree must be allowed).
# CONFIG_ROOT is the worktree-aware location for .supercharger.json.
CONFIG_ROOT=$(_resolve_project_root "$PROJECT_DIR" 2>/dev/null) || CONFIG_ROOT="$PROJECT_DIR"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "path-guard" && exit 0
hook_profile_skip "path-guard" && exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit) ;;   # v2.9.3: cover NotebookEdit (notebook_path) + MultiEdit
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)  # v2.9.3: NotebookEdit uses notebook_path
[ -z "$FILE_PATH" ] && exit 0

# Disabled categories from .supercharger.json (project-level opt-out)
DISABLED_CATS=""
EXTRA_ROOTS=""
if [ -f "$CONFIG_ROOT/.supercharger.json" ]; then
  # One fork reads both keys. CONFIG_ROOT goes through the ENVIRONMENT, not
  # string interpolation into the python source: a project path containing a
  # quote used to break (or inject into) this program.
  _PG_CFG=$(SC_CFG_ROOT="$CONFIG_ROOT" python3 -c "
import json, os
try:
    with open(os.path.join(os.environ['SC_CFG_ROOT'], '.supercharger.json')) as f:
        d = json.load(f)
    print(','.join(c for c in (d.get('disableSecurityCategories') or []) if isinstance(c, str)))
    # v2.26.41: additionalRoots — sibling directories that count as in-project.
    # Tab-joined: a tab cannot appear in a sane path and keeps this to one line.
    print('\t'.join(r for r in (d.get('additionalRoots') or []) if isinstance(r, str)))
except Exception:
    print(''); print('')
" 2>/dev/null || printf '\n\n')
  DISABLED_CATS=$(printf '%s\n' "$_PG_CFG" | sed -n '1p')
  EXTRA_ROOTS=$(printf '%s\n' "$_PG_CFG" | sed -n '2p')
fi
_cat_enabled() { case ",$DISABLED_CATS," in *",$1,"*) return 1 ;; esac; return 0; }

# Session launch dir (recorded by project-config.sh at SessionStart). Read
# fork-free; absent for a session that started before this version, which simply
# means the boundary behaves as it did then.
SESSION_ROOT=""
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  _SR_F="$SUPERCHARGER_STATE/scope/.session-root-$CLAUDE_CODE_SESSION_ID"
  if [ -f "$_SR_F" ]; then
    IFS= read -r SESSION_ROOT < "$_SR_F" || SESSION_ROOT=""
  fi
fi

# v2.26.43: Claude Code's OWN directory authorisation. CC has three ways to put a
# directory in the workspace — the `--add-dir` launch flag, the `/add-dir`
# in-session command, and `permissions.additionalDirectories` in settings.json —
# and path-guard honoured none of them. A user who ran `/add-dir ../sibling` had
# authorised that directory through the product's front door, CC allowed it, and
# this guard still denied the write. That is a false block on explicit consent,
# and it is the answer we should have given before inventing `additionalRoots`.
#
# Two sources were intended; only the first works:
#   - settings.json permissions.additionalDirectories  (static; user + project)
#   - .session-dirs-<sid>, appended by dir-added-record.sh — NEVER WRITTEN.
#     That hook was registered on "DirectoryAdded", which Claude Code does not
#     dispatch, so the in-session `/add-dir` half has never been honoured. The
#     read below stays because the file is still the right contract if such an
#     event ships; today it simply never exists. A user running `/add-dir` mid
#     session is still denied here, which is a known gap, not a silent one.
# Both go through the SAME refusals as a configured root — CC granting read
# access to $HOME must not silently make the home directory writable here.
CC_DIRS=""
_CC_SETTINGS="$HOME/.claude/settings.json"
_CC_PROJ="$CONFIG_ROOT/.claude/settings.json"
_CC_PROJ_LOCAL="$CONFIG_ROOT/.claude/settings.local.json"
if [ -f "$_CC_SETTINGS" ] || [ -f "$_CC_PROJ" ] || [ -f "$_CC_PROJ_LOCAL" ]; then
  CC_DIRS=$(SC_S1="$_CC_SETTINGS" SC_S2="$_CC_PROJ" SC_S3="$_CC_PROJ_LOCAL" python3 -c "
import json, os
out = []
for k in ('SC_S1', 'SC_S2', 'SC_S3'):
    try:
        with open(os.environ[k]) as f:
            d = json.load(f)
        for v in ((d.get('permissions') or {}).get('additionalDirectories') or []):
            if isinstance(v, str) and v:
                out.append(v)
    except Exception:
        continue
print('\t'.join(out))
" 2>/dev/null || echo "")
fi
# In-session /add-dir, recorded per session by dir-added-record.sh.
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  _SD_F="$SUPERCHARGER_STATE/scope/.session-dirs-$CLAUDE_CODE_SESSION_ID"
  if [ -f "$_SD_F" ]; then
    while IFS= read -r _d || [ -n "$_d" ]; do
      [ -n "$_d" ] && CC_DIRS="${CC_DIRS:+$CC_DIRS	}$_d"
    done < "$_SD_F"
  fi
fi

REASON=$(FILE_PATH="$FILE_PATH" PROJECT_DIR="$PROJECT_DIR" DISABLED="$DISABLED_CATS" \
         EXTRA_ROOTS="$EXTRA_ROOTS" SESSION_ROOT="$SESSION_ROOT" CC_DIRS="$CC_DIRS" \
         SID="${CLAUDE_CODE_SESSION_ID:-}" \
         python3 <<'PYEOF'
import os, sys, re

p = os.environ.get('FILE_PATH', '')
proj = os.environ.get('PROJECT_DIR', '')
disabled = set(c.strip() for c in os.environ.get('DISABLED', '').split(',') if c.strip())


def _msys_path(x):
    """Git Bash's /c/Users/... -> C:\\Users\\..., on Windows only.

    Native Windows python resolves a leading-slash path against the CURRENT
    DRIVE, so on a runner whose workspace sits on D: the diagnostic measured:

        realpath('/')                    -> 'D:\\'
        realpath('/etc/hosts')           -> 'D:\\etc\\hosts'
        realpath('/c/Users/me/.ssh')     -> 'D:\\c\\Users\\me\\.ssh'

    That last one is the problem: it equals nothing, so a write to the real
    ~/.ssh compared as unrelated and the credential protection did not fire.
    Git Bash hands out exactly that spelling, and whether a payload carries it
    or the native form depends on which side produced the path — so the guard
    normalises instead of assuming.

    Gated on os.name, so POSIX is provably untouched: there, a directory named
    /c is a legitimate path and must never be rewritten.
    """
    if os.name != 'nt' or not x:
        return x
    m = re.match(r'^/([A-Za-z])(/|$)', x)
    if not m:
        return x
    return m.group(1).upper() + ':\\' + x[3:].replace('/', '\\')


p = _msys_path(p)
proj = _msys_path(proj)

# v2.26.83: opt-in trace, inert unless SC_PATHGUARD_DEBUG is set. Added because
# five separate probes each answered ONE input to this guard and none identified
# why a POSIX-form absolute path is allowed on Windows while a drive-letter one is
# blocked. Probing inputs one at a time was not converging; tracing the real code
# through its gates settles it in a single run. Writes to stderr so it can never be
# mistaken for a verdict — the verdict is stdout, and an empty stdout means allow.
_DBG = os.environ.get('SC_PATHGUARD_DEBUG', '') not in ('', '0')


def _dbg(where, **kw):
    if not _DBG:
        return
    bits = '  '.join(f'{k}={v!r}' for k, v in kw.items())
    sys.stderr.write(f'[path-guard:{where}] {bits}\n')


_dbg('input', p=p, proj=proj, disabled=sorted(disabled))

if not p:
    _dbg('exit', why='empty file_path -> allow')
    sys.exit(0)

# v2.23.13: the "project boundary" is the session's cwd, but Claude Code is often
# launched from a SUBDIRECTORY of the repo. Files at the repo ROOT (vercel.json,
# package.json, tsconfig.json …) then sit ABOVE cwd and were wrongly flagged
# "outside project root". Widen the boundary to the enclosing git repo root — but
# LAZILY: resolved only when a write would otherwise be blocked, so the common
# path (writing under cwd) stays fork-free. No repo / no git → boundary stays cwd.
_repo_root_cache = [None]
def _repo_root(start):
    if _repo_root_cache[0] is not None:
        return _repo_root_cache[0]
    rr = ''
    try:
        import subprocess
        r = subprocess.run(['git', '-C', start, 'rev-parse', '--show-toplevel'],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=2)
        out = r.stdout.decode('utf-8', 'replace').strip()
        if r.returncode == 0 and out:
            rr = os.path.realpath(out)
    except Exception:
        rr = ''
    _repo_root_cache[0] = rr
    return rr

# v2.26.41: additionalRoots — sibling directories that count as in-project.
#
# The v2.23.13 widening above covers a SUBDIRECTORY launch (files at the repo
# root sit above cwd). It cannot help two SIBLING repos edited together — a
# free/pro plugin pair under one wrapper dir — because the git toplevel of one
# repo is that repo. Reported from the field: editing pro from free was denied
# in both directions, and the only offered outs were `/sc off` (every guard) or
# disableSecurityCategories:["abs-path"] (also unprotects ~/.ssh, ~/.aws, /etc).
#
# This widens ONLY the "is it inside my project" test. It cannot subtract any
# protection: the credential/system list is checked BEFORE this (3.4 below), and
# selfmod is a separate check that never consults the boundary.
#
# Refusals matter more than the feature — a root that resolves to /, $HOME, or
# any ancestor of $HOME would disable the guard while looking like a whitelist.
_extra_roots_cache = [None]
def _extra_roots(proj_real):
    if _extra_roots_cache[0] is not None:
        return _extra_roots_cache[0]
    out = []
    # v2.26.42: the session's LAUNCH directory, recorded once at SessionStart.
    # Claude Code's cwd follows `cd`, so the boundary used to move mid-session:
    # open Claude in a wrapper holding two repos, end up inside one, and the
    # sibling silently left the project. Carrying the launch dir makes the
    # boundary stable — it is the workspace the user actually opened.
    #
    # It goes through the SAME validation as a configured root: launching from
    # $HOME is common, and pinning to it would make the entire home directory
    # in-project. Refused there, exactly as a configured root would be.
    # Three sources, one validation path: the session launch dir, this project's
    # additionalRoots, and the directories Claude Code itself authorised.
    raw = '\t'.join(s for s in (
        os.environ.get('SESSION_ROOT', ''),
        os.environ.get('EXTRA_ROOTS', ''),
        os.environ.get('CC_DIRS', ''),
    ) if s)
    # The MSYS installation root, or '' anywhere else. Resolved from the shell's own
    # location so it does not hardcode "C:/Program Files/Git": bash lives at
    # <root>/usr/bin/bash, so two levels up is the root. Empty off Windows, which
    # makes every use of it below a no-op there.
    # os.name is the only exact discriminator. On Git Bash the interpreter is NATIVE
    # Windows python, so this is 'nt'; it is 'posix' on macOS and Linux no matter what
    # MSYSTEM says. Two weaker tests were tried first and both were wrong:
    #   - MSYSTEM alone: an env var, so anything may set it.
    #   - the <root>/usr/bin/bash layout: that is where ORDINARY LINUX keeps bash, so
    #     it derived '/' as the MSYS root and reddened the ubuntu suite. It passed
    #     locally only because macOS keeps bash in /bin.
    # Consequence for testing, stated rather than hidden: the positive case cannot be
    # exercised off Windows. The suite pins that this stays INERT here; the Windows
    # recon is what verifies it fires there.
    _msys_root = ''
    if os.name == 'nt' and os.environ.get('MSYSTEM'):
        try:
            import shutil
            _sh = shutil.which('bash') or ''
            # Require the .exe: on Git Bash this resolves through NATIVE Windows
            # python, so bash is always bash.exe, and no POSIX bash ever is.
            #
            # The first version accepted a bare '/usr/bin/bash' too, which is where
            # bash lives on ORDINARY LINUX — so the two-levels-up rule derived '/'
            # as the "MSYS root" and reddened the ubuntu suite. It passed locally
            # because macOS keeps bash in /bin. A layout is not a platform; the
            # executable suffix is the part only Windows has.
            _norm = _sh.replace('\\', '/').lower()
            if _norm.endswith('/usr/bin/bash.exe'):
                _msys_root = os.path.realpath(
                    os.path.join(os.path.dirname(_sh), os.pardir, os.pardir))
        except Exception:
            _msys_root = ''
    _dbg('roots-raw', raw=raw, msys_root=_msys_root)
    if raw:
        try:
            home = os.path.realpath((os.environ.get('HOME') or os.path.expanduser('~')))
        except Exception:
            home = ''
        claude_dir = os.path.join(home, '.claude') if home else ''
        for entry in raw.split('\t'):
            entry = entry.strip()
            if not entry:
                continue
            cand = entry if os.path.isabs(entry) else os.path.join(proj_real, entry)
            try:
                rp = os.path.realpath(cand)
            except Exception:
                continue
            # Must exist and be a directory. A typo'd root that silently "works"
            # is worse than none: it reads as protection that is not there.
            if not os.path.isdir(rp):
                continue
            # Root of the filesystem, $HOME itself, or any ANCESTOR of $HOME
            # (e.g. /Users) would make everything in-project.
            _dbg('root-cand', entry=entry, rp=rp, is_fs_root=(rp == os.path.dirname(rp)),
                 is_home=(bool(home) and rp == home),
                 is_home_ancestor=(bool(home) and home.startswith(rp + os.sep)))
            if rp == os.path.dirname(rp):
                continue
            # v2.26.83: on Git Bash, MSYS rewrites a single-path env var in transit,
            # so a configured root of "/" reaches this loop already turned into the
            # MSYS installation root. Measured on a windows-latest runner:
            #     config  additionalRoots: ["/"]
            #     python  raw='C:/Program Files/Git/'   is_fs_root=False
            # The check above therefore never fires, the refusal is silently
            # bypassed, and the project widens to everything under the Git install
            # — which is how C:/Program Files/Git/etc/hosts read as in-project.
            #
            # Refuse the MSYS root by identity rather than by string: it is wherever
            # bash itself lives (two levels above /usr/bin/bash), so this holds for
            # any install location and stays inert off Windows, where MSYSTEM is
            # unset and the value is empty.
            if _msys_root and (rp == _msys_root or _msys_root.startswith(rp + os.sep)):
                continue
            if home and (rp == home or home.startswith(rp + os.sep)):
                continue
            # Supercharger's own config/state stays out of reach.
            if claude_dir and (rp == claude_dir or rp.startswith(claude_dir + os.sep)):
                continue
            out.append(rp)
    _extra_roots_cache[0] = out
    return out

def _under(target_real, root):
    # `root + os.sep` is '//' when root is '/', which matches nothing — the exact
    # shape of the v2.26.25 root-deletion hole in safety.sh. Containment must not
    # depend on the root having no trailing separator.
    if not root:
        return False
    if target_real == root.rstrip(os.sep) or target_real == root:
        return True
    prefix = root if root.endswith(os.sep) else root + os.sep
    return target_real.startswith(prefix)

def _within_project(target_real, proj_real):
    # inside cwd, or inside the enclosing git repo root (subdir-launch case)
    if _under(target_real, proj_real):
        return True
    if _under(target_real, _repo_root(proj_real)):
        return True
    for er in _extra_roots(proj_real):
        if _under(target_real, er):
            return True
    return False

# --- 3.1 Path traversal: decode and normalize ---
if 'path-traversal' not in disabled:
    raw = p
    # URL-decode (single + double)
    for _ in range(2):
        raw = re.sub(r'%([0-9a-fA-F]{2})', lambda m: chr(int(m.group(1), 16)), raw)
    if '\x00' in raw:
        print('null byte in file path — path-truncation attack risk; opt out via disableSecurityCategories: ["path-traversal"]')
        sys.exit(0)
    if re.search(r'(^|/)\.\.(/|$)', raw):
        print('path traversal sequence (..) in file path: ' + p[:100] + '; opt out via disableSecurityCategories: ["path-traversal"]')
        sys.exit(0)

# --- 3.1b Command substitution in file path (CVE-2026-35021) ---
# CC's editor invocation utility interpolates file paths into shell commands via
# execSync. POSIX double-quote semantics allow $() and backtick expressions to
# be evaluated even inside quotes, so a path like 'foo$(curl …).py' becomes
# an RCE gadget (fixed in v2.1.92). Reject paths containing these sequences.
if 'path-traversal' not in disabled:
    # v2.8.4: also check the URL-decoded form (`raw`, computed above) — an
    # encoded `%24%28…%29` would otherwise slip the literal `$(`/backtick test.
    if '$(' in p or '`' in p or '$(' in raw or '`' in raw:
        print('command substitution sequence in file path ($() or backtick) — '
              'shell metacharacter injection risk (CVE-2026-35021); '
              'opt out via disableSecurityCategories: ["path-traversal"]')
        sys.exit(0)

# --- 3.2 Symlink: resolve the FULL realpath and block symlink-redirected writes ---
# v2.22.1: resolve the BASENAME too. Previously the absolute branch joined the
# basename literally, so an in-repo symlinked file (`innocent.json -> ~/.ssh/…`)
# escaped, and a dir-alias (`g -> .git`) reached git internals while the lexical
# string matcher saw no `.git`. We only act when realpath actually differs from
# the lexical path (a symlink was followed) — plain absolute-outside paths keep
# deferring to abs-path (with its safe-list + memory-store allowance); `..` paths
# already exited in the path-traversal category above.
_dbg('3.2-gate', enabled=('symlink' not in disabled), proj_set=bool(proj))
if 'symlink' not in disabled and proj:
    try:
        proj_real = os.path.realpath(proj)
        cand = p if os.path.isabs(p) else os.path.join(proj_real, p)
        full = os.path.realpath(cand)
        lexical = os.path.normpath(cand)
        _dbg('3.2', isabs=os.path.isabs(p), cand=cand, full=full, lexical=lexical,
             differs=(full != lexical), proj_real=proj_real,
             repo_root=_repo_root(proj_real), within=_within_project(full, proj_real))
        if full != lexical:  # a symlink changed the resolution
            if re.search(r'(^|/)\.git/(hooks|refs|objects|config)(/|$)', full):
                print('write resolves via a symlink into git internals ('
                      + full[:120] + ') — repo integrity risk; '
                      'opt out via disableSecurityCategories: ["symlink"]')
                sys.exit(0)
            if not _within_project(full, proj_real):
                print('path resolves outside the project root via a symlink ('
                      + full[:120] + ') — out-of-project write; '
                      'opt out via disableSecurityCategories: ["symlink"]')
                sys.exit(0)
    except Exception as _e:
        _dbg('3.2-EXCEPTION', err=repr(_e))

# --- 3.3 Git internals + supercharger hooks ---
if 'git-internals' not in disabled:
    git_patterns = [
        r'(^|/)\.git/hooks/',
        r'(^|/)\.githooks/',
        r'(^|/)\.git/refs/',
        r'(^|/)\.git/objects/',
        r'(^|/)\.git/config\b',
    ]
    for pat in git_patterns:
        # v2.22.1: IGNORECASE — a case-insensitive FS (macOS APFS default) resolves
        # `.GIT/config` / `.Git/hooks/` to the real `.git`, but the case-sensitive
        # regex missed them (proven: `.GIT/config` clobbered the real `.git/config`).
        if re.search(pat, p, re.IGNORECASE):
            print('write to git internals (' + pat + ') — repo integrity risk; opt out via disableSecurityCategories: ["git-internals"]')
            sys.exit(0)
    home = (os.environ.get('HOME') or os.path.expanduser('~'))
    # Normalised on both sides. os.path.join builds with backslashes on Windows
    # while a payload may legitimately spell the same path with forward slashes
    # (C:/Users/... is valid there), and startswith between the two forms matches
    # nothing — this guard blocks writes to the hooks dir, so a miss here is a
    # write that disables every other check. Same fault found three times
    # elsewhere in this file; fixed here before it is found a fourth.
    _pn = p.replace(os.sep, '/')
    _hn = home.replace(os.sep, '/').rstrip('/')
    if _pn.startswith(_hn + '/.claude/hooks') or _pn.startswith(_hn + '/.claude/supercharger/hooks'):
        print('write to supercharger hooks dir — would disable security checks; opt out via disableSecurityCategories: ["git-internals"]')
        sys.exit(0)

# --- 3.3b Self-modification — agent disabling its own guardrails (OWASP 2026
# Least-Agency; mirrors the Bash-side check in safety.sh `selfmod` category).
# Ona Security (March 2026) documented Claude Code agents disabling their own
# sandboxes by reasoning about and modifying the blocker. These writes are the
# tool-call channel for the same attack.
if 'selfmod' not in disabled:
    home = (os.environ.get('HOME') or os.path.expanduser('~'))
    selfmod_targets = [
        os.path.join(home, '.claude', 'supercharger', 'scope', '.disabled-security-categories'),
        os.path.join(home, '.claude', 'supercharger', 'scope', '.disabled-hooks'),
        os.path.join(home, '.claude', 'settings.json'),
        os.path.join(home, '.claude', 'CLAUDE.md'),
        # v2.7.5: MCP server config. Real incident: "SymJack" (May 2026) — a
        # symlink disguised as a doc resolved to the user's MCP config on copy,
        # inserting an attacker-controlled MCP server that auto-spawns with full
        # privileges next session. ~/.claude.json holds the mcpServers map.
        os.path.join(home, '.mcp.json'),
        os.path.join(home, '.claude.json'),
    ]
    # The two scope control-files are matched by BASENAME (path-agnostic), like
    # safety.sh's Bash-channel _SELFMOD_CFG — otherwise a plugin install (whose hooks
    # read them at $CLAUDE_PLUGIN_DATA/scope, not the classic path) lets a Write to the
    # plugin-path copy slip past this exact-match list and disable the guardrails.
    # v2.26.33: PREFIX match, not equality. These files gained a per-project
    # suffix (".disabled-hooks-Users-me-proj"), and an exact-basename set stopped
    # matching them the moment they did — silently un-protecting the very files
    # this rule exists to protect. The prefix form covers both spellings.
    _selfmod_basenames = ('.disabled-security-categories', '.disabled-hooks')
    _bn = os.path.basename(p)
    if any(_bn == b or _bn.startswith(b + '-') for b in _selfmod_basenames) or any(p == t for t in selfmod_targets):
        print('self-modification — agent should not edit its own guardrail config (' + os.path.basename(p) + '); opt out via disableSecurityCategories: ["selfmod"]')
        sys.exit(0)
    # Project-level: .supercharger.json (any depth — could be repo root or nested),
    # project-local .claude/settings.json, and .mcp.json (SymJack — MCP server
    # insertion via a project-scoped config write).
    # v2.8.4: match by basename / leading-slash-agnostic regex. The old
    # `endswith('/.supercharger.json')` required a leading slash, so a RELATIVE
    # top-level write (file_path ".supercharger.json" / ".mcp.json" /
    # ".claude/settings.json") bypassed selfmod entirely — the exact guardrail
    # this defends. basename covers the single-file configs at any location.
    # v2.22.1: case-fold — on a case-insensitive FS `.SUPERCHARGER.json` /
    # `.CLAUDE/settings.json` resolve to the real guardrail config but the
    # case-sensitive checks missed them (proven bypass → could disable every
    # security category via `.SUPERCHARGER.json`).
    _norm = p.replace('\\', '/')
    if (os.path.basename(p).lower() in ('.supercharger.json', '.mcp.json')
            or re.search(r'(^|/)\.claude/settings(\.local)?\.json$', _norm, re.IGNORECASE)):
        print('self-modification — agent should not edit project guardrail config (' + os.path.basename(p) + '); opt out via disableSecurityCategories: ["selfmod"]')
        sys.exit(0)

# --- 3.4 Absolute-path writes outside project root ---
if 'abs-path' not in disabled and os.path.isabs(p) and proj:
    # v2.8.11: allow Claude Code's own file-memory store —
    # ~/.claude/projects/<project-enc>/memory/*.md — which the memory feature
    # writes via the Write tool. Previously the abs-path guard blocked it, so
    # `/remember` and auto-memory silently failed under Supercharger. This
    # permits only the LOCATION (narrow: under projects/, in a memory/ dir, .md);
    # the CONTENT is still scanned by memory-write-guard for poisoning. realpath
    # is used so an in-path symlink escaping the store can't abuse the allowance.
    _mem_root = os.path.join(os.path.realpath((os.environ.get('HOME') or os.path.expanduser('~'))), '.claude', 'projects')
    _rp = os.path.realpath(p)
    # Compared with forward slashes on both sides. realpath returns BACKSLASHES on
    # Windows, so the literal '/memory/' could never match there and the allowance
    # never fired: /remember and auto-memory were blocked on Windows for the same
    # reason this block was written to unblock them on POSIX. os.sep on the
    # startswith side had the same flaw in reverse.
    _rp_n = _rp.replace(os.sep, '/')
    _mem_n = _mem_root.replace(os.sep, '/')
    if _rp_n.startswith(_mem_n + '/') and '/memory/' in _rp_n and _rp_n.endswith('.md'):
        sys.exit(0)
    # v2.26.66: allow the harness's own per-session scratchpad, for the same reason
    # as the memory store above. Claude Code's system prompt directs ALL temp files
    # there, yet the Write tool was denied while the identical path succeeded via
    # Bash — so scratch work got pushed into the project tree instead, which is the
    # outcome this guard exists to prevent.
    #
    # NOT a general /tmp allowance: the path must contain this session's own id
    # immediately followed by `scratchpad`, so it names one ephemeral directory that
    # is already writable through the Bash channel. Narrower than the memory-store
    # allowance above, which permits any projects/**/memory/*.md.
    # _rp_n, not _rp: realpath returns backslashes on Windows, so this
    # forward-slash test could never match there and the allowance never fired.
    # Claude Code's prompt sends ALL temp files to the scratchpad, so the Write
    # tool was denied for the one directory it is told to use — the same
    # separator fault as the memory store above, with a louder consequence.
    _sid = os.environ.get('SID', '')
    if _sid and ('/' + _sid + '/scratchpad/') in (_rp_n + '/'):
        sys.exit(0)
    # Built and compared with FORWARD slashes on both sides.
    #
    # Two faults compounded here on Windows, and between them the credential
    # block never fired:
    #   1. expanduser('~/.ssh/') substitutes the profile path (backslashes) and
    #      leaves the rest verbatim -> 'C:\Users\x/.ssh/', mixed separators.
    #   2. `p` is all backslashes by this point, so startswith could not match.
    # And expanduser ignores bash's $HOME on Windows, so even the prefix could be
    # the wrong user's home. On POSIX os.sep is '/' and HOME == expanduser('~'),
    # so every line below is byte-identical to what it replaced.
    _home_n = (os.environ.get('HOME') or os.path.expanduser('~')).replace(os.sep, '/').rstrip('/')
    abs_blocked = [
        _home_n + '/.ssh/',
        _home_n + '/.aws/',
        _home_n + '/.config/',
        _home_n + '/.npmrc',
        _home_n + '/.gitconfig',
        _home_n + '/.bashrc',
        _home_n + '/.zshrc',
        '/etc/',
        '/usr/local/etc/',
    ]
    _p_n = p.replace(os.sep, '/')
    for blk in abs_blocked:
        if _p_n.startswith(blk) or _p_n == blk.rstrip('/'):
            print('write to ' + blk + ' — credential or system config persistence risk; opt out via disableSecurityCategories: ["abs-path"]')
            sys.exit(0)
    # Generic: absolute path resolves outside project
    try:
        proj_real = os.path.realpath(proj)
        target_dir = os.path.dirname(p) or '/'
        target_real = os.path.realpath(target_dir)
        _dbg('3.4-generic', target_dir=target_dir, target_real=target_real,
             proj_real=proj_real, within=_within_project(target_real, proj_real))
        if not _within_project(target_real, proj_real):
            print('absolute path outside project root: ' + p[:100] + '; opt out via disableSecurityCategories: ["abs-path"]')
            sys.exit(0)
    except Exception:
        pass

# --- 3.5 Build artifact injection ---
if 'build-artifacts' not in disabled:
    artifact_patterns = [
        r'(^|/)node_modules/\.bin(/|$)',
        r'(^|/)__pycache__/',
        r'(^|/)\.next/',
        r'(^|/)\.venv/',
        r'(^|/)\.nuxt/',
        r'(^|/)\.output/',
    ]
    for pat in artifact_patterns:
        if re.search(pat, p, re.IGNORECASE):  # v2.22.1: case-insensitive FS (.NEXT/, NODE_MODULES/.BIN)
            print('write to build artifact dir (' + pat + ') — dependency trojaning risk; opt out via disableSecurityCategories: ["build-artifacts"]')
            sys.exit(0)
PYEOF
) || REASON=""
# ^ 2.21.1: fail open, never phantom-deny. Under set -e an unguarded
# VAR=$(python3 …) that exits non-zero (python absent / crash) aborts the hook
# with empty stderr → CC renders a bogus "No stderr output" deny on EVERY
# Write/Edit. Same regression class as the 2.17.3 safety.sh fix.

if [ -n "$REASON" ]; then
  RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] path-guard: BLOCKED $REASON" >&2
  exit 2
fi

exit 0
