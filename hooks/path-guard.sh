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

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_PATH_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
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
if [ -f "$CONFIG_ROOT/.supercharger.json" ]; then
  DISABLED_CATS=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_ROOT/.supercharger.json') as f:
        d = json.load(f)
    cats = d.get('disableSecurityCategories', [])
    print(','.join(cats))
except Exception:
    pass
" 2>/dev/null || echo "")
fi
_cat_enabled() { case ",$DISABLED_CATS," in *",$1,"*) return 1 ;; esac; return 0; }

REASON=$(FILE_PATH="$FILE_PATH" PROJECT_DIR="$PROJECT_DIR" DISABLED="$DISABLED_CATS" python3 <<'PYEOF'
import os, sys, re

p = os.environ.get('FILE_PATH', '')
proj = os.environ.get('PROJECT_DIR', '')
disabled = set(c.strip() for c in os.environ.get('DISABLED', '').split(',') if c.strip())

if not p:
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

def _within_project(target_real, proj_real):
    # inside cwd, or inside the enclosing git repo root (subdir-launch case)
    if target_real == proj_real or target_real.startswith(proj_real + os.sep):
        return True
    rr = _repo_root(proj_real)
    return bool(rr) and (target_real == rr or target_real.startswith(rr + os.sep))

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
if 'symlink' not in disabled and proj:
    try:
        proj_real = os.path.realpath(proj)
        cand = p if os.path.isabs(p) else os.path.join(proj_real, p)
        full = os.path.realpath(cand)
        lexical = os.path.normpath(cand)
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
    except Exception:
        pass

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
    home = os.path.expanduser('~')
    if p.startswith(os.path.join(home, '.claude', 'hooks')) or p.startswith(os.path.join(home, '.claude', 'supercharger', 'hooks')):
        print('write to supercharger hooks dir — would disable security checks; opt out via disableSecurityCategories: ["git-internals"]')
        sys.exit(0)

# --- 3.3b Self-modification — agent disabling its own guardrails (OWASP 2026
# Least-Agency; mirrors the Bash-side check in safety.sh `selfmod` category).
# Ona Security (March 2026) documented Claude Code agents disabling their own
# sandboxes by reasoning about and modifying the blocker. These writes are the
# tool-call channel for the same attack.
if 'selfmod' not in disabled:
    home = os.path.expanduser('~')
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
    _mem_root = os.path.join(os.path.realpath(os.path.expanduser('~')), '.claude', 'projects')
    _rp = os.path.realpath(p)
    if _rp.startswith(_mem_root + os.sep) and '/memory/' in _rp and _rp.endswith('.md'):
        sys.exit(0)
    abs_blocked = [
        os.path.expanduser('~/.ssh/'),
        os.path.expanduser('~/.aws/'),
        os.path.expanduser('~/.config/'),
        os.path.expanduser('~/.npmrc'),
        os.path.expanduser('~/.gitconfig'),
        os.path.expanduser('~/.bashrc'),
        os.path.expanduser('~/.zshrc'),
        '/etc/',
        '/usr/local/etc/',
    ]
    for blk in abs_blocked:
        if p.startswith(blk) or p == blk.rstrip('/'):
            print('write to ' + blk + ' — credential or system config persistence risk; opt out via disableSecurityCategories: ["abs-path"]')
            sys.exit(0)
    # Generic: absolute path resolves outside project
    try:
        proj_real = os.path.realpath(proj)
        target_dir = os.path.dirname(p) or '/'
        target_real = os.path.realpath(target_dir)
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
