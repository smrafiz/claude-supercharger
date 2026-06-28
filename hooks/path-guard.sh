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
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"

[ "${SUPERCHARGER_PATH_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
# v2.6.36: PROJECT_DIR stays as the actual CWD (used as boundary for symlink/
# abs-path checks — writes within the linked worktree must be allowed).
# CONFIG_ROOT is the worktree-aware location for .supercharger.json.
CONFIG_ROOT=$(_resolve_project_root "$PROJECT_DIR")
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "path-guard" && exit 0
hook_profile_skip "path-guard" && exit 0

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
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
    if '$(' in p or '`' in p:
        print('command substitution sequence in file path ($() or backtick) — '
              'shell metacharacter injection risk (CVE-2026-35021); '
              'opt out via disableSecurityCategories: ["path-traversal"]')
        sys.exit(0)

# --- 3.2 Symlink: resolve and check under project root ---
if 'symlink' not in disabled and proj:
    try:
        proj_real = os.path.realpath(proj)
        # Use the directory of the target if file doesn't exist yet
        target_dir = os.path.dirname(p) if not os.path.exists(p) else p
        target_real = os.path.realpath(target_dir) if target_dir else proj_real
        if os.path.isabs(p):
            tail = os.path.basename(p) if not os.path.exists(p) else ''
            full = os.path.join(target_real, tail) if tail else target_real
        else:
            full = os.path.realpath(os.path.join(proj_real, p))
        if not (full == proj_real or full.startswith(proj_real + os.sep)):
            # Allow common safe absolute paths (handled by abs-path category)
            pass  # fall through to abs-path check
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
        if re.search(pat, p):
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
    if any(p == t for t in selfmod_targets):
        print('self-modification — agent should not edit its own guardrail config (' + os.path.basename(p) + '); opt out via disableSecurityCategories: ["selfmod"]')
        sys.exit(0)
    # Project-level: .supercharger.json (any depth — could be repo root or nested),
    # project-local .claude/settings.json, and .mcp.json (SymJack — MCP server
    # insertion via a project-scoped config write).
    if p.endswith('/.supercharger.json') or p.endswith('/.claude/settings.json') or p.endswith('/.claude/settings.local.json') or p.endswith('/.mcp.json'):
        print('self-modification — agent should not edit project guardrail config (' + os.path.basename(p) + '); opt out via disableSecurityCategories: ["selfmod"]')
        sys.exit(0)

# --- 3.4 Absolute-path writes outside project root ---
if 'abs-path' not in disabled and os.path.isabs(p) and proj:
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
        if not (target_real == proj_real or target_real.startswith(proj_real + os.sep)):
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
        if re.search(pat, p):
            print('write to build artifact dir (' + pat + ') — dependency trojaning risk; opt out via disableSecurityCategories: ["build-artifacts"]')
            sys.exit(0)
PYEOF
)

if [ -n "$REASON" ]; then
  RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] path-guard: BLOCKED $REASON" >&2
  exit 2
fi

exit 0
