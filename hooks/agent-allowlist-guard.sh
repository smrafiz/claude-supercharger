#!/usr/bin/env bash
# Claude Supercharger — Per-Agent Allowlist Guard (opt-in)
# Event: PreToolUse | Matcher: Bash,Monitor,PowerShell,WebFetch,Write,Edit,MultiEdit,NotebookEdit,Agent,Workflow
# Opt-in: a subagent whose definition declares supercharger-allow lists is held to them.
# Disable: SUPERCHARGER_AGENT_ALLOWLIST=0
#
# An agent definition (~/.claude/agents/<name>.md or <project>/.claude/agents/
# <name>.md) may narrow what that agent can do, in its frontmatter:
#
#   supercharger-allow:
#     bash: ["git status", "git diff*", "npm test"]   # prefixes, or globs
#     webfetch: ["docs.python.org", "*.github.com"]    # host or its subdomains, or globs
#     write: ["src/**", "tests/**"]                    # relative to the project root
#
# Inside that subagent, a call outside a declared list is denied. A tool with no
# list is untouched, an agent with no `supercharger-allow` is untouched, and the
# main session is never touched. Claude Code's own `tools:` field picks WHICH
# tools an agent has; this narrows what it may do with them. The settings-level
# `Bash(prefix *)` rules cannot do that per agent.
#
# Idea from gadievron/raptor's per-agent allowlist hooks (reimplemented, not
# copied): there each agent wires its own hook with its list as arguments. Here
# one hook reads the list from the definition, so the list lives with the agent.
#
# Identity: Claude Code puts `agent_id` and `agent_type` in every tool event
# fired inside a subagent (code.claude.com/docs/en/hooks, common input fields);
# `agent_type` is the definition's frontmatter `name`. A `--agent` session has
# agent_type but no agent_id, and is a main session.
#
# Bash: every segment of a compound command must match, after the shared
# normalizer (cmd-normalize.sh) strips wrappers and env assignments, so
# `git status && curl x` and `env X=1 sudo curl x` are both checked as curl.
# Command substitution, process substitution and output redirects are refused
# under a list: what they run or write is not on the command line to match.
#
# Also denied while a list is declared: editing the agent's own definition (an
# agent that can rewrite its list has none), and spawning nested agents or
# workflows (they would run without the list).
#
# Fails OPEN, with a stderr note, on a list it cannot read. Fails closed on the
# call once a list is read.
#
# Disable: SUPERCHARGER_AGENT_ALLOWLIST=0
set -uo pipefail

# Fork-free stdin read, then the cheapest possible exit: a payload with no
# agent_id is not from a subagent, which is every main-session call.
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"; sc_read_input _INPUT
case "$_INPUT" in *'"agent_id"'*) ;; *) exit 0 ;; esac

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
check_hook_disabled "agent-allowlist-guard" 2>/dev/null && exit 0
hook_profile_skip "agent-allowlist-guard" 2>/dev/null && exit 0
[ "${SUPERCHARGER_AGENT_ALLOWLIST:-1}" = "0" ] && exit 0

# Second cheap exit, one grep fork: no agent definition anywhere declares a list.
# Directories: user agents, the payload cwd and every parent up to the repo root
# (a subagent's cwd can be a subdirectory), and CLAUDE_PROJECT_DIR.
_AA_CWD=""
[[ "$_INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && _AA_CWD="${BASH_REMATCH[1]}"
_AA_DIRS=()
[ -d "$HOME/.claude/agents" ] && _AA_DIRS+=("$HOME/.claude/agents")
[ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.claude/agents" ] && _AA_DIRS+=("$CLAUDE_PROJECT_DIR/.claude/agents")
_aa_d="${_AA_CWD:-$PWD}"
while [ -n "$_aa_d" ]; do
  [ -d "$_aa_d/.claude/agents" ] && _AA_DIRS+=("$_aa_d/.claude/agents")
  [ -e "$_aa_d/.git" ] && break
  case "$_aa_d" in /|*:/|*:\\) break ;; esac
  _aa_n="${_aa_d%/*}"; [ -z "$_aa_n" ] && _aa_n="/"
  [ "$_aa_n" = "$_aa_d" ] && break
  _aa_d="$_aa_n"
done
[ "${#_AA_DIRS[@]}" -eq 0 ] && exit 0
grep -rqs --include='*.md' 'supercharger-allow' "${_AA_DIRS[@]}" 2>/dev/null || exit 0

# Slow path: a list exists somewhere. The resolver decides whether it is THIS
# agent's and whether the call is inside it. Its stderr (fail-open notes) passes
# through. A crash yields no verdict, which is an allow plus a note.
_AA_OUT=$(printf '%s' "$_INPUT" | PWD_DIR="$PWD" python3 "$HOOKS_DIR/agent-allowlist-detect.py") || _AA_OUT=""
_AA_US=$'\x1f'
_AA_VERDICT="${_AA_OUT%%"$_AA_US"*}"

. "$HOOKS_DIR/lib-deny.sh"

_aa_ledger() {
  local _st="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}/scope"
  mkdir -p "$_st" 2>/dev/null || true
  printf '[%s] agent-allowlist — %s — %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$2" \
    >> "$_st/.blocked-commands" 2>/dev/null || true
}

case "$_AA_VERDICT" in
  ALLOW) exit 0 ;;
  DENY)
    _r="${_AA_OUT#DENY"$_AA_US"}"
    _reason="${_r%%"$_AA_US"*}"; _remedy="${_r#*"$_AA_US"}"
    _aa_ledger "outside a per-agent list" "${_reason:0:160}"
    sc_deny "$_reason" "$_remedy"
    ;;
  SEG) ;;
  *)
    echo "[Supercharger] agent-allowlist-guard: resolver gave no verdict; call not checked (failing open)" >&2
    exit 0
    ;;
esac

# Bash: SEG <agent> <file> <patterns> <command>
_r="${_AA_OUT#SEG"$_AA_US"}"
_agent="${_r%%"$_AA_US"*}"; _r="${_r#*"$_AA_US"}"
_file="${_r%%"$_AA_US"*}";  _r="${_r#*"$_AA_US"}"
_pats="${_r%%"$_AA_US"*}";  _cmd="${_r#*"$_AA_US"}"

# shellcheck source=hooks/cmd-normalize.sh
. "$HOOKS_DIR/cmd-normalize.sh"
_norm=$(normalize_cmd "$_cmd" 2>/dev/null) || _norm="$_cmd"
_segs=$(split_segments "$_norm" 2>/dev/null) || _segs=""
[ -z "$_segs" ] && _segs="$_norm"

_aa_match() { # segment -> 0 when some pattern allows it
  local seg="$1" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      *'*'*|*'?'*|*'['*)
        # shellcheck disable=SC2053  # $p is a glob on purpose
        [[ "$seg" == $p ]] && return 0 ;;
      *)
        [ "$seg" = "$p" ] && return 0
        case "$seg" in "$p "*) return 0 ;; esac ;;
    esac
  done <<< "$_pats"
  return 1
}

while IFS= read -r _seg; do
  _seg="${_seg#"${_seg%%[![:space:]]*}"}"; _seg="${_seg%"${_seg##*[![:space:]]}"}"
  [ -z "$_seg" ] && continue
  _aa_match "$_seg" && continue
  _shown=$(printf '%s' "$_pats" | head -8 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [ -z "$_shown" ] && _shown="(empty: nothing allowed)"
  _aa_ledger "outside a per-agent bash list" "$_agent: ${_seg:0:120}"
  sc_deny "subagent '$_agent' may only run commands on the supercharger-allow.bash list in $_file: $_shown. \`${_seg:0:200}\` is not on it." \
    "stay inside the list, or hand this step back to the parent session in your report. Only the user widens the list."
done <<< "$_segs"

exit 0
