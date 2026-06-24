#!/usr/bin/env bash
# Claude Supercharger — Safety Hook
# Event: PreToolUse | Matcher: Bash, PowerShell
#
# Per-category toggles: disable specific security categories via
#   ~/.claude/supercharger/scope/.disabled-security-categories
# One category per line: filesystem, database, destructive, network,
#   credentials, persistence, clipboard, browser, history, selfmod
#
# Or per-project via .supercharger.json:
#   {"disableSecurityCategories": ["clipboard", "history"]}
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

_INPUT=$(cat)
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

# cwd from hook payload, used by the rm guard to detect rm targets that resolve
# to the project root or its ancestors. Optional — fallback paths still apply.
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# Forensic breadcrumb: every fire writes one line. Absence of an entry on a
# missed block means the hook never fired (settings.json drift or CC didn't
# match the event). Presence means it fired but didn't match a rule.
_SAFETY_TRACE="$HOME/.claude/supercharger/scope/.safety-trace.log"
mkdir -p "$(dirname "$_SAFETY_TRACE")" 2>/dev/null || true
printf '[%s] cwd=%s cmd=%.140s\n' "$(date '+%Y-%m-%dT%H:%M:%SZ')" "$PROJECT_DIR" "$COMMAND" >> "$_SAFETY_TRACE" 2>/dev/null || true
# Cap at 1000 lines
if [ -f "$_SAFETY_TRACE" ] && [ "$(wc -l < "$_SAFETY_TRACE" 2>/dev/null || echo 0)" -gt 1000 ]; then
  tail -800 "$_SAFETY_TRACE" > "${_SAFETY_TRACE}.tmp" 2>/dev/null && mv "${_SAFETY_TRACE}.tmp" "$_SAFETY_TRACE" 2>/dev/null || true
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

# Per-segment view for ^-anchored checks (rm, mv) — protects against
# compound bypass like `safe && rm -rf /`. Falls back to CMD if split fails.
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

# Load disabled security categories
_DISABLED_CATS=""
_DISABLED_CATS_FILE="$HOME/.claude/supercharger/scope/.disabled-security-categories"
[ -f "$_DISABLED_CATS_FILE" ] && _DISABLED_CATS=$(<"$_DISABLED_CATS_FILE")

_cat_enabled() {
  case "$_DISABLED_CATS" in
    *"$1"*) return 1 ;;
    *) return 0 ;;
  esac
}

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  Override: run it in your terminal directly, OR add the relevant category to" >&2
  echo "            \"disableSecurityCategories\" in .supercharger.json (project) — categories:" >&2
  echo "            filesystem, database, destructive, network, credentials, persistence," >&2
  echo "            clipboard, browser, history, selfmod" >&2
  echo "" >&2
  # Log for learning — future sessions will know to avoid this pattern
  local blocks_log="$HOME/.claude/supercharger/scope/.blocked-commands"
  mkdir -p "$(dirname "$blocks_log")" 2>/dev/null || true
  # Redact credentials before logging
  local safe_cmd
  safe_cmd=$(printf '%s' "$COMMAND" | sed \
    -e 's/\(PGPASSWORD=\)[^ ]*/\1[REDACTED]/g' \
    -e 's/\(PASSWORD=\)[^ ]*/\1[REDACTED]/g' \
    -e 's/\(SECRET=\)[^ ]*/\1[REDACTED]/g' \
    -e 's/\(TOKEN=\)[^ ]*/\1[REDACTED]/g' \
    -e 's/\(API_KEY=\)[^ ]*/\1[REDACTED]/g' \
    -e 's/ghp_[A-Za-z0-9]\{36\}/[REDACTED]/g' \
    -e 's/sk-[A-Za-z0-9]\{32,\}/[REDACTED]/g')
  # Truncate to 120 chars to avoid bloating session context
  safe_cmd="${safe_cmd:0:120}"
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# --- Filesystem (category: filesystem) ---
# Validate rm per-segment to defeat compound bypass (`safe && rm -rf /`).
if _cat_enabled "filesystem"; then
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if [[ "$seg" =~ ^rm[[:space:]] ]]; then
      has_recursive=false
      has_force=false

      args="${seg#rm }"

      if [[ "$args" =~ (^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$) ]] || \
         [[ "$args" =~ (^|[[:space:]])--recursive([[:space:]]|$) ]]; then
        has_recursive=true
      fi

      if [[ "$args" =~ (^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$) ]] || \
         [[ "$args" =~ (^|[[:space:]])--force([[:space:]]|$) ]]; then
        has_force=true
      fi

      if $has_recursive && $has_force; then
        # v2.6.80: added ${HOME} braced form (fuzz harness bypass). Also
        # tightened to catch `~/` and `$HOME/` (with trailing slash) since
        # `rm -rf ~/` and `rm -rf $HOME/` are equally destructive.
        if [[ "$args" =~ (^|[[:space:]])(\/[[:space:]]*$|\/\*|~|~\/|\$HOME|\$HOME\/|\$\{HOME\}|\$\{HOME\}\/|\.\.)([[:space:]]|$|\/) ]]; then
          block "recursive force rm on dangerous target"
        fi
        # Catch `rm -rf .`, `./`, `./*`, `*` — deletes CWD contents wholesale
        # (claude-code#29023 vector: ghost-CWD cascade after directory deletion).
        if [[ "$args" =~ (^|[[:space:]])(\.|\.\/|\.\/\*|\*)([[:space:]]|$) ]]; then
          block "recursive force rm on current directory (deletes CWD contents)"
        fi
        # Catch CWD-equivalent refs: $PWD, ${PWD}, $(pwd), `pwd`, "$PWD" — these
        # resolve to the CWD at shell-eval time, so they wipe whichever directory
        # the shell happens to be in (including from a prior `cd X &&` in the
        # same compound). The python check above can't see this because it
        # tokenizes pre-expansion and python's expandvars uses the hook process
        # PWD, not the shell's. Match on the literal substring.
        case "$args" in
          *'$PWD'*|*'${PWD}'*|*'$(pwd)'*|*'`pwd`'*)
            block "recursive force rm on CWD via \$PWD/\$(pwd) (deletes whatever dir the shell is in)"
            ;;
        esac
        # Catch rm targets that resolve to PROJECT_DIR or an ancestor — the
        # exact pattern when Claude runs from a subdir and types the project
        # name as a relative path.
        if [ -n "$PROJECT_DIR" ]; then
          BAD=$(ARGS="$args" CWD="$PROJECT_DIR" python3 <<'PYEOF' 2>/dev/null || true
import os, shlex, sys
args = os.environ.get('ARGS','')
cwd  = os.path.realpath(os.environ.get('CWD','/'))
try:
    tokens = shlex.split(args, posix=True)
except ValueError:
    sys.exit(0)
for tok in tokens:
    if not tok or tok.startswith('-'): continue
    expanded = os.path.expanduser(os.path.expandvars(tok))
    target = os.path.realpath(os.path.join(cwd, expanded))
    # Block if target is cwd or an ancestor of cwd (project-dir wipe).
    if target == cwd or cwd.startswith(target + os.sep):
        print(target); sys.exit(0)
PYEOF
)
          if [ -n "$BAD" ]; then
            block "recursive force rm targeting project root or ancestor ($BAD)"
          fi
        fi
      fi
    fi
  done <<< "$SEGMENTS"
fi

# --- Dangerous patterns (category: database, destructive, network) ---
# v2.6.83: ORM schema-drop with --force/--force-reset. Real incident:
# drizzle-kit push --force on Railway PostgreSQL wiped 60+ tables (Feb 2026).
# Agent picks --force specifically to bypass the interactive confirmation
# stdin prompt — nothing else catches it because no `rm` is invoked.
DB_PATTERNS=(
  'DROP[[:space:]]+TABLE' 'DROP[[:space:]]+DATABASE'
  'drizzle-kit[[:space:]]+push[[:space:]]+([^&|;]*[[:space:]])?--force([[:space:]]|$)'
  'prisma[[:space:]]+db[[:space:]]+push[[:space:]]+([^&|;]*[[:space:]])?--force-reset([[:space:]]|$)'
  'prisma[[:space:]]+migrate[[:space:]]+reset'
  'typeorm[[:space:]]+schema:drop'
  'sequelize[[:space:]]+db:drop'
  'knex[[:space:]]+migrate:rollback[[:space:]]+([^&|;]*[[:space:]])?--all([[:space:]]|$)'
)
DESTRUCT_PATTERNS=(
  'chmod[[:space:]]+(-R[[:space:]]+)?777' 'mkfs\.' 'dd[[:space:]]+if='
  '>[[:space:]]*/dev/sd' 'truncate[[:space:]]+-s[[:space:]]*0'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:' 'kill[[:space:]]+-9[[:space:]]+-1'
)
NETWORK_PATTERNS=(
  'curl.*\|.*bash' 'curl.*\|.*sh' 'wget.*\|.*bash' 'wget.*\|.*sh'
  '\|[[:space:]]*(bash|sh|zsh|dash)([[:space:]]|$)'
  '(^|;|&&|\|\|)[[:space:]]*(bash|sh|zsh)[[:space:]]+-c[[:space:]]'
  '(^|;|&&|\|\|)[[:space:]]*eval[[:space:]]+'
  '(^|;|&&|\|\|)[[:space:]]*source[[:space:]]+/dev/(tcp|udp)/'
  'base64.*\|.*(bash|sh|zsh)' '<<<.*\|.*(bash|sh|zsh)'
)

DANGEROUS_PATTERNS=()
_cat_enabled "database" && DANGEROUS_PATTERNS+=("${DB_PATTERNS[@]}")
_cat_enabled "destructive" && DANGEROUS_PATTERNS+=("${DESTRUCT_PATTERNS[@]}")
_cat_enabled "network" && DANGEROUS_PATTERNS+=("${NETWORK_PATTERNS[@]}")

if [ ${#DANGEROUS_PATTERNS[@]} -gt 0 ]; then
  JOINED_DANGEROUS=$(IFS='|'; echo "${DANGEROUS_PATTERNS[*]}")
  if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$JOINED_DANGEROUS"; then
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
      if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$pattern"; then
        block "dangerous pattern: $pattern"
      fi
    done
  fi
fi

if _cat_enabled "filesystem"; then
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if [[ "$seg" =~ ^mv[[:space:]]+(\/|~|\$HOME)[[:space:]] ]]; then
      block "mv from root or home directory"
    fi
  done <<< "$SEGMENTS"
fi

# --- Credential leakage (category: credentials) ---
if _cat_enabled "credentials"; then
  CRED_PATTERNS=(
    '[Aa][Pp][Ii][_-]?[Kk][Ee][Yy][[:space:]]*='
    '[Ss][Ee][Cc][Rr][Ee][Tt][_-]?[Kk][Ee][Yy][[:space:]]*='
    '[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn][[:space:]]*='
    'AKIA[0-9A-Z]{16}'
    'ghp_[0-9a-zA-Z]{36}'
    'sk-[0-9a-zA-Z]{48}'
    'AIza[0-9A-Za-z_-]{35}'
    'sk_live_[0-9a-zA-Z]{24}'
    'pk_live_[0-9a-zA-Z]{24}'
    'npm_[0-9a-zA-Z]{36}'
    'pypi-[0-9a-zA-Z_-]{16,}'
    '[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*='
    'DB_PASSWORD[[:space:]]*='
    'MYSQL_ROOT_PASSWORD[[:space:]]*='
    '-----BEGIN[[:space:]]+(RSA|EC|DSA|OPENSSH)?[[:space:]]*PRIVATE[[:space:]]+KEY-----'
    'eyJ[0-9a-zA-Z_-]{10,}\.[0-9a-zA-Z_-]{10,}\.'
    # CVE-2026-35020: TERMINAL env var injected with shell metacharacters is
    # passed via shell=true in CC terminal launcher → RCE (fixed v2.1.92).
    # CVE-2026-21852: ANTHROPIC_BASE_URL override in env redirects API traffic
    # to attacker infra before consent prompt (fixed v2.0.65).
    # Block export of these vars when the value contains shell metacharacters.
    'export[[:space:]]+(TERMINAL|ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY)[[:space:]]*=.*[$`;&|]'
  )

  JOINED_CRED=$(IFS='|'; echo "${CRED_PATTERNS[*]}")
  # v2.6.80: scan the ORIGINAL command, not the normalized one. cmd-normalize
  # strips leading `VAR=value` env-var assignments, which is correct for the
  # destructive-command rules (so `API_KEY=x rm -rf /` triggers the rm rule),
  # but it would hide credential leaks like `API_KEY=secret123 echo done`
  # where the secret IS the env-var value.
  if printf '%s\n' "$COMMAND" | LC_ALL=C grep -qE "$JOINED_CRED"; then
    block "potential credential in command — never embed secrets in commands"
  fi
fi

# --- Unauthorized persistence (category: persistence) ---
if _cat_enabled "persistence"; then
  if [[ "$CMD" =~ (crontab[[:space:]]+-e|crontab[[:space:]]+-) ]]; then
    block "cron job modification — agent should not create persistent scheduled tasks"
  fi

  if [[ "$CMD" =~ (>>?[[:space:]]*(~|\$HOME)?/?\.(bashrc|zshrc|profile|bash_profile|zprofile)) ]]; then
    block "shell profile modification — agent should not modify shell startup files"
  fi

  # v2.6.77: tee -a bypass — `tee -a ~/.bashrc <<< 'x'` achieves the same
  # append without a `>` redirect, so the regex above missed it.
  if [[ "$CMD" =~ tee[[:space:]]+(-[a-zA-Z]*a[a-zA-Z]*|--append)[[:space:]]+[^|]*\.(bashrc|zshrc|profile|bash_profile|zprofile) ]]; then
    block "shell profile modification via tee -a — agent should not modify shell startup files"
  fi

  if [[ "$CMD" =~ ssh-keygen|ssh-add|ssh-copy-id ]]; then
    block "SSH key operation — agent should not manage SSH keys"
  fi
fi

# --- Clipboard exfiltration (category: clipboard) ---
if _cat_enabled "clipboard" && [[ "$CMD" =~ (pbpaste|pbcopy|xclip|xsel|wl-paste|wl-copy) ]]; then
  block "clipboard access — agent should not read or write clipboard"
fi

# --- Sensitive app data paths (category: browser) ---
if _cat_enabled "browser"; then
  if [[ "$CMD" =~ (Application[[:space:]]+Support/(Google/Chrome|Arc|Firefox|BraveSoftware|Microsoft[[:space:]]+Edge)/|/Cookies|/Login[[:space:]]+Data|/History) ]]; then
    block "browser data access — agent should not read browser cookies, passwords, or history"
  fi

  if [[ "$CMD" =~ (Library/Keychains|Library/Messages|Signal/sql|1Password|gnome-keyring|\.password-store) ]]; then
    block "sensitive app data — agent should not access keychains, messages, or password managers"
  fi
fi

# --- Shell history (category: history) ---
if _cat_enabled "history" && [[ "$CMD" =~ (\.(bash_history|zsh_history|python_history|psql_history|mysql_history|node_repl_history)) ]]; then
  block "shell history access — may contain credentials or sensitive commands"
fi

# --- Self-modification prevention (category: selfmod) ---
if _cat_enabled "selfmod" && [[ "$CMD" =~ (\.claude/settings\.json|\.claude/CLAUDE\.md) ]]; then
  if [[ "$CMD" =~ (>|>>|sed|awk|tee|mv|cp|rm|cat.*>|python.*open|echo.*>) ]]; then
    block "self-modification — agent should not directly edit its own config files"
  fi
fi

# --- Unified detector (shell-wrapper, env-file, exfiltration) ---
# Single python3 fork covers 3 categories that previously required 3 separate hooks.
# Fast-path: skip the fork unless the command contains a trigger keyword.
_NEED_PY=false
case "$CMD" in
  *python*\ -c*|*node\ -e*|*perl\ -e*|*ruby\ -e*|*dash\ -c*|*ksh\ -c*|*fish\ -c*) _NEED_PY=true ;;
  *.env*|*.npmrc*|*.pypirc*|*.pgpass*|*.netrc*|*.git-credentials*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*|*.pem*|*.key*|*.p12*|*.pfx*|*.ppk*) _NEED_PY=true ;;
  *aws*|*gsutil*|*azcopy*|*az\ storage*|*rclone*|*s3cmd*) _NEED_PY=true ;;
  *curl*|*wget*|*nc\ *|*netcat*) _NEED_PY=true ;;
  *dnscat*|*iodine*|*dns2tcp*|*dnsexfil*) _NEED_PY=true ;;
  *xargs*|*find*\ -name*|*find*\ -iname*|*find*\ -regex*|*find*\ -exec*) _NEED_PY=true ;;
  *secret*|*credential*|*wallet*) _NEED_PY=true ;;
esac

if [ "$_NEED_PY" = "true" ] && [ -x "$(command -v python3 2>/dev/null)" ]; then
  # Cap Python fork at 500ms — defensive against runaway regex / deep traversal.
  if command -v gtimeout >/dev/null 2>&1; then _TIMEOUT="gtimeout 0.5"
  elif command -v timeout >/dev/null 2>&1; then _TIMEOUT="timeout 0.5"
  else _TIMEOUT=""
  fi
  PY_REASON=$(CMD="$CMD" DISABLED_CATS="$_DISABLED_CATS" $_TIMEOUT python3 "$(dirname "${BASH_SOURCE[0]}")/safety-detect.py" 2>/dev/null)
  if [ -n "$PY_REASON" ]; then
    block "$PY_REASON"
  fi
fi

# --- Production reads (warn only — exit 1, not exit 2) ---
if [[ "$CMD" =~ (kubectl[[:space:]]+exec|docker[[:space:]]+exec).*prod ]]; then
  echo "" >&2
  echo "Supercharger warning: Production container access detected." >&2
  echo "  Live credentials may appear in your conversation transcript." >&2
  echo "" >&2
  exit 0
fi

exit 0
