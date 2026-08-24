#!/usr/bin/env bash
# Claude Supercharger — Tool Preferences (per-project rejection chains with suggestions)
# Event: PreToolUse | Matcher: Bash,Monitor,WebFetch
# Reads .supercharger.json `toolPreferences` map. When Claude tries to run a
# disallowed tool, denies with a suggested replacement instead of a blanket block.
#
# Example .supercharger.json:
#   {"toolPreferences": {"npm": "pnpm", "jest": "vitest", "pip": "uv pip"}}
#
# v2.29.16: `preferGhCli` (bool, default false/absent) — when true and `gh` is on
# PATH, curl/wget/WebFetch to a GitHub URL is denied with the matching `gh`
# subcommand suggested instead. Adapted from trailofbits/skills' gh-cli plugin,
# which does this unconditionally for everyone with `gh` installed; here it is
# opt-in, same shape as toolPreferences, because it is a workflow opinion, not a
# safety rule — a hard deny is real friction if the user does not want it. The
# payoff is real, not stylistic: `gh` carries the authenticated token, so
# unauthenticated curl hits GitHub's 60/hr rate limit and cannot reach private
# repos at all.
#
#   {"preferGhCli": true}
#
# Disable: SUPERCHARGER_TOOL_PREFS=0

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TOOL_PREFS:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# v2.24.0: fork-free `cwd` first — this jq ran on every Bash call, before the
# "is there even a config?" exit below. jq stays as the fallback.
if command -v _json_fast_str >/dev/null 2>&1 && _json_fast_str cwd "$_INPUT"; then
  PROJECT_DIR="$_JSON_FAST_VAL"
else
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "tool-preferences" && exit 0
hook_profile_skip "tool-preferences" && exit 0

# v2.6.36: read .supercharger.json from main worktree root if in a linked worktree
CONFIG="$(_resolve_project_root "$PROJECT_DIR")/.supercharger.json"
[ ! -f "$CONFIG" ] && exit 0

# v2.24.0: a config exists, but most don't define toolPreferences or preferGhCli —
# and finding that out used to cost two more jq forks plus a ~30ms python3. Reading
# the file is a builtin redirect and the test is fork-free; same terminal state (no
# prefs -> exit 0). v2.29.16 widened this to also catch preferGhCli.
_TP_CFG_BODY=$(<"$CONFIG")
case "$_TP_CFG_BODY" in
  *toolPreferences*|*preferGhCli*) ;;
  *) exit 0 ;;
esac

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
# v2.29.16: was `[ "$TOOL_NAME" != "Bash" ]`, a hard exit that predated Monitor
# joining this hook's matcher in v2.29.7 (lib/hooks.sh) — the registration was
# widened but this internal gate never was, so Monitor commands got zero
# tool-preferences coverage for two releases despite being "covered". Verified
# live before fixing: an npm command routed through Monitor produced no
# suggestion while the identical Bash command did. Same failure shape as the
# Monitor egress gap this file's own sweep exists to catch elsewhere.
case "$TOOL_NAME" in
  Bash|Monitor|WebFetch) ;;
  *) exit 0 ;;
esac

CMD=""
URL=""
if [ "$TOOL_NAME" = "WebFetch" ]; then
  URL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.url // empty' 2>/dev/null || true)
  [ -z "$URL" ] && exit 0
else
  CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  [ -z "$CMD" ] && exit 0
fi

# `gh` availability decides the whole preferGhCli branch, so it is checked once
# here (cheap PATH lookup) rather than inside the python fork below.
_TP_GH=0
command -v gh >/dev/null 2>&1 && _TP_GH=1

REASON=$(CMD="$CMD" URL="$URL" TOOL_NAME="$TOOL_NAME" CONFIG="$CONFIG" GH_AVAILABLE="$_TP_GH" python3 <<'PYEOF'
import os, json, re, shlex, sys

# NOTE: this heredoc lives inside RESULT=$(...). NO BACKTICKS anywhere in this
# body -- a quoted heredoc does NOT shield backtick balance from the outer bash
# parser (verified: a single unbalanced backtick inside <<'PYEOF' breaks the
# OUTER script's parse with "unexpected EOF while looking for matching `" even
# though the delimiter is quoted). sendmessage-guard.sh follows the same rule
# for the same reason -- see hooks/workflow-guard.sh for the measured write-up.

cmd = os.environ.get('CMD', '')
url = os.environ.get('URL', '')
tool_name = os.environ.get('TOOL_NAME', '')
config_path = os.environ.get('CONFIG', '')
gh_available = os.environ.get('GH_AVAILABLE') == '1'

try:
    with open(config_path) as f:
        d = json.load(f)
except Exception:
    sys.exit(0)

# -- toolPreferences: binary -> suggested replacement (Bash/Monitor only) ------
prefs = d.get('toolPreferences') or {}
if isinstance(prefs, dict) and prefs and tool_name in ('Bash', 'Monitor') and cmd:
    try:
        tokens = shlex.split(cmd)
    except Exception:
        tokens = cmd.split()

    if tokens:
        i = 0
        while i < len(tokens) and '=' in tokens[i] and not tokens[i].startswith('-'):
            i += 1
        if i < len(tokens):
            bin_name = os.path.basename(tokens[i])
            if bin_name in ('npx', 'bunx', 'pnpx') and i + 1 < len(tokens):
                bin_name = tokens[i + 1]
            if bin_name in prefs:
                suggested = prefs[bin_name]
                print("This project prefers '%s' over '%s' (per .supercharger.json toolPreferences). Use '%s' with the same arguments." % (suggested, bin_name, suggested))
                sys.exit(0)

# -- preferGhCli: redirect GitHub curl/wget/WebFetch to the matching gh subcommand
if not (d.get('preferGhCli') is True and gh_available):
    sys.exit(0)

GH_HOST_RE = re.compile(
    r'https?://(github\.com|api\.github\.com|raw\.githubusercontent\.com|gist\.github\.com)/\S*')

if tool_name in ('Bash', 'Monitor'):
    if not re.search(r'(^|[\s;|&])(curl|wget)[\s]', cmd):
        sys.exit(0)
    m = GH_HOST_RE.search(cmd)
    if not m:
        sys.exit(0)
    target = m.group(0)
else:
    target = url

# Normalize to host + path for pattern matching, regardless of source.
m = re.match(r'https?://([^/\s]+)/?(\S*)', target)
if not m:
    sys.exit(0)
host, path = m.group(1), (m.group(2) or '').split('?')[0].split('#')[0]

CLONE_NOTE = ("gh repo clone %(o)s/%(r)s \"${TMPDIR:-/tmp}/gh-clones-${CLAUDE_SESSION_ID}/%(r)s\" -- --depth 1, "
              "then use the Explore agent on the clone. Do NOT fetch and decode file "
              "contents via the API -- clone the repo instead")

suggestion = None
if host == 'api.github.com':
    if re.match(r'repos/([^/]+)/([^/]+)/pulls', path):
        o, r = re.match(r'repos/([^/]+)/([^/]+)/', path).groups()
        suggestion = "gh pr list --repo %s/%s" % (o, r)
    elif re.match(r'repos/([^/]+)/([^/]+)/issues', path):
        o, r = re.match(r'repos/([^/]+)/([^/]+)/', path).groups()
        suggestion = "gh issue list --repo %s/%s" % (o, r)
    elif re.match(r'repos/([^/]+)/([^/]+)/releases', path):
        o, r = re.match(r'repos/([^/]+)/([^/]+)/', path).groups()
        suggestion = "gh release list --repo %s/%s" % (o, r)
    elif re.match(r'repos/([^/]+)/([^/]+)/contents', path):
        o, r = re.match(r'repos/([^/]+)/([^/]+)/', path).groups()
        suggestion = CLONE_NOTE % {'o': o, 'r': r}
    elif path:
        suggestion = "gh api %s" % path
elif host == 'raw.githubusercontent.com':
    m2 = re.match(r'([^/]+)/([^/]+)/', path)
    if m2:
        o, r = m2.groups()
        suggestion = CLONE_NOTE % {'o': o, 'r': r}
elif host == 'gist.github.com':
    suggestion = "gh gist view"
elif host == 'github.com':
    m2 = re.match(r'([^/]+)/([^/]+)(/.*)?$', path)
    if m2:
        o, r, rest = m2.groups()
        rest = rest or ''
        if '/releases/download/' in rest:
            suggestion = "gh release download --repo %s/%s" % (o, r)
        elif rest.startswith('/blob/') or rest.startswith('/tree/'):
            suggestion = CLONE_NOTE % {'o': o, 'r': r}
        else:
            suggestion = "gh repo view %s/%s" % (o, r)

if suggestion:
    print("Use '%s' instead of %s to a GitHub URL. gh uses your authenticated token "
          "-- works on private repos and avoids the 60/hr unauthenticated rate limit. "
          "(.supercharger.json preferGhCli)" % (suggestion, tool_name))
PYEOF
)

if [ -n "$REASON" ]; then
  RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] tool-preferences: SUGGESTED $REASON" >&2
  exit 2
fi

exit 0
