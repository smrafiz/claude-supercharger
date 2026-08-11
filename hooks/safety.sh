#!/usr/bin/env bash
# Claude Supercharger — Safety Hook
# Event: PreToolUse | Matcher: Bash, PowerShell
#
# Per-category toggles: disable specific security categories via
#   ~/.claude/supercharger/scope/.disabled-security-categories
# One category per line: filesystem, database, destructive, network,
#   credentials, persistence, clipboard, browser, history, selfmod, cloud
#
# Or per-project via .supercharger.json:
#   {"disableSecurityCategories": ["clipboard", "history"]}
set -euo pipefail
. "${BASH_SOURCE[0]%/*}/lib-timing.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "${BASH_SOURCE[0]%/*}/lib-json-fast.sh" 2>/dev/null || true

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# 2.22.11: also read PowerShell's field. safety.sh matches Bash AND PowerShell,
# but the PowerShell tool may carry the body in .script/.code rather than
# .command — without this the body would be empty and every check skipped.
# v2.24.1: try a fork-free read before jq. This jq ran on EVERY Bash call — including
# the trivially-safe ones that exit at the fast-path below — so the guard paid a fork
# just to decide it had nothing to do. lib-json-fast refuses anything ambiguous or
# escaped, so the jq/python chain below still runs verbatim whenever it can't be sure.
# Order matches the jq alternation exactly: command, script, code, cmd.
COMMAND=""
if command -v _json_fast_str >/dev/null 2>&1; then
  for _sf_key in command script code cmd; do
    if _json_fast_str "$_sf_key" "$_INPUT"; then COMMAND="$_JSON_FAST_VAL"; break; fi
  done
fi
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // .tool_input.code // .tool_input.cmd // empty' 2>/dev/null || true)
fi
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; ti=json.load(sys.stdin).get('tool_input',{}); print(ti.get('command') or ti.get('script') or ti.get('code') or ti.get('cmd') or '')" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Perf fast-path (v2.14.1) -------------------------------------------------
# The most common agent Bash calls (ls, git status/log/diff, echo…) can't be
# destructive OR read a sensitive file, so skip the full scan — ~40% faster on
# macOS bash 3.2 (measured 150ms → 95ms). FAIL-SAFE BY CONSTRUCTION on two axes:
#   1. only BARE verbs with NO shell metacharacter (so no chain / redirect /
#      subshell / exec can hide inside), and
#   2. only verbs that do NOT read arbitrary file *content* — so cat/head/tail/wc/
#      grep/file/stat are deliberately EXCLUDED and still get the full scan (which
#      catches sensitive-file reads like `cat ~/.my.cnf`). No sensitive-file
#      allowlist to keep in sync — the exclusion is structural.
# Anything not matched here falls through to the complete scan below; the allowlist
# only trades speed, never safety. (Fast-pathed commands are also not written to
# the forensic trace — only scanned commands are.)
case "$COMMAND" in
  # any shell metacharacter → could chain / redirect / subshell / exec → full scan
  *'|'*|*';'*|*'&'*|*'<'*|*'>'*|*'$'*|*'`'*|*'('*|*')'*|*'{'*|*'}'*|*$'\n'*) : ;;
  # content-inert verbs (list names / print / repo status — never cat a secret) → skip
  ls|ls\ *|pwd|echo\ *|printf\ *|which|which\ *|type|type\ *|\
  git\ status*|git\ log*|git\ diff*|git\ show*)
    exit 0 ;;
esac
# -----------------------------------------------------------------------------

# cwd from hook payload, used by the rm guard to detect rm targets that resolve
# to the project root or its ancestors. Optional — fallback paths still apply.
PROJECT_DIR=""
if command -v _json_fast_str >/dev/null 2>&1 && _json_fast_str cwd "$_INPUT"; then
  PROJECT_DIR="$_JSON_FAST_VAL"
else
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# Forensic breadcrumb: every fire writes one line. Absence of an entry on a
# missed block means the hook never fired (settings.json drift or CC didn't
# match the event). Presence means it fired but didn't match a rule.
_SAFETY_TRACE="$SUPERCHARGER_STATE/scope/.safety-trace.log"
# v2.24.1: the directory is statically known and normally exists — test before forking
# (this was `mkdir -p "$(dirname …)"`, i.e. two forks on every single fire).
[ -d "$SUPERCHARGER_STATE/scope" ] || mkdir -p "$SUPERCHARGER_STATE/scope" 2>/dev/null || true
# v2.26.35: `$(date …)` forked on EVERY Bash call — measured 1.59ms, paid even by
# commands that turn out to be harmless. bash 5's printf can format the clock with
# no fork at all; bash 3.2 (macOS default) has no equivalent, so it keeps the fork
# rather than losing the timestamp. The trace is the breadcrumb that distinguishes
# "hook never fired" from "fired but matched nothing", so dropping the time is not
# on the table.
if [ "${BASH_VERSINFO[0]}" -ge 5 ]; then
  printf -v _sfx_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
else
  _sfx_ts=$(date '+%Y-%m-%dT%H:%M:%SZ')
fi
printf '[%s] cwd=%s cmd=%.140s\n' "$_sfx_ts" "$PROJECT_DIR" "$COMMAND" >> "$_SAFETY_TRACE" 2>/dev/null || true
# Cap at 1000 lines
if [ -f "$_SAFETY_TRACE" ] && [ "$(wc -l < "$_SAFETY_TRACE" 2>/dev/null || echo 0)" -gt 1000 ]; then
  tail -800 "$_SAFETY_TRACE" > "${_SAFETY_TRACE}.tmp" 2>/dev/null && mv "${_SAFETY_TRACE}.tmp" "$_SAFETY_TRACE" 2>/dev/null || true
fi

source "${BASH_SOURCE[0]%/*}/cmd-normalize.sh"
# Hardened (2.21.1): same phantom-deny guard as SEGMENTS below — a non-zero from
# the sourced normalizer under set -e would exit with empty stderr, which CC
# renders as a bogus "No stderr output" deny. Fall back to the raw command.
CMD=$(normalize_cmd "$COMMAND" 2>/dev/null) || CMD="$COMMAND"

# Per-segment view for ^-anchored checks (rm, mv) — protects against
# compound bypass like `safe && rm -rf /`. Falls back to CMD if split fails.
# Hardened (2.17.2): swallow the lib's stderr and non-zero exit so a crash in
# the sourced splitter can never propagate as a bare non-zero + empty stderr
# (CC would render that as a phantom "hook error: No stderr output" deny).
# Worst case the segment view collapses to the whole command — still scanned.
SEGMENTS=$(split_segments "$CMD" 2>/dev/null) || SEGMENTS=""
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

# Load disabled security categories
_DISABLED_CATS=""
# v2.26.33: per-project, falling back to the legacy global file. One global file
# meant a project that disabled a security category disabled it for EVERY
# project on the machine — the loosening direction, so this one mattered most.
if type sc_scope_resolve >/dev/null 2>&1; then
  sc_scope_resolve ".disabled-security-categories" "$PROJECT_DIR"
  _DISABLED_CATS_FILE="$SC_SCOPE_FILE"
else
  _DISABLED_CATS_FILE="$SUPERCHARGER_STATE/scope/.disabled-security-categories"
fi
[ -f "$_DISABLED_CATS_FILE" ] && _DISABLED_CATS=$(<"$_DISABLED_CATS_FILE")

# allowPatterns (v2.26.34) — exempt a specific command from a category block
# instead of switching the whole category off. Loaded here so block() can consult
# it. Joined into ONE alternation, kept in its own pass: a bad user regex makes
# grep error, and rc>1 is treated as no-match below, so a broken allow rule
# leaves the command BLOCKED rather than silently permitting it.
_ALLOW_JOINED=""
if type sc_scope_resolve >/dev/null 2>&1; then
  sc_scope_resolve ".allow-patterns" "$PROJECT_DIR"
  _ALLOW_PAT_FILE="$SC_SCOPE_FILE"
else
  _ALLOW_PAT_FILE="$SUPERCHARGER_STATE/scope/.allow-patterns"
fi
if [ -s "$_ALLOW_PAT_FILE" ]; then
  _ALLOW_JOINED=$(tr '\n' '|' < "$_ALLOW_PAT_FILE" 2>/dev/null | sed 's/|$//')
fi

_cat_enabled() {
  case "$_DISABLED_CATS" in
    *"$1"*) return 1 ;;
    *) return 0 ;;
  esac
}

block() {
  # allowPatterns exemption. Deliberately NOT applied to self-modification: the
  # patterns live in .supercharger.json, which the selfmod rule protects, so a
  # rule that could exempt selfmod would be able to authorise edits to the file
  # granting it that power. That bootstrap hole is closed here, in code.
  if [ -n "${_ALLOW_JOINED:-}" ]; then
    case "$1" in
      *self-modification*|*guardrail*) : ;;
      *)
        if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$_ALLOW_JOINED" 2>/dev/null; then
          # Visible, not silent: an exemption is a widened guard and belongs in
          # the ledger that /why and the [BLOCKS] summary read.
          local _al="$SUPERCHARGER_STATE/scope/.blocked-commands"
          mkdir -p "$(dirname "$_al")" 2>/dev/null || true
          printf '[%s] ALLOWED by allowPatterns (would have blocked: %s) — %.400s\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$1" "$COMMAND" >> "$_al" 2>/dev/null || true
          echo "[Supercharger] safety: allowPatterns exempted this command (would have blocked: $1)" >&2
          exit 0
        fi
        ;;
    esac
  fi
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  Override: run it in your terminal directly, OR add the relevant category to" >&2
  echo "            \"disableSecurityCategories\" in .supercharger.json (project) — categories:" >&2
  echo "            filesystem, database, destructive, network, credentials, persistence," >&2
  echo "            clipboard, browser, history, selfmod, cloud" >&2
  echo "" >&2
  # Log for learning — future sessions will know to avoid this pattern
  local blocks_log="$SUPERCHARGER_STATE/scope/.blocked-commands"
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
  # v2.26.17: collapse newlines/tabs BEFORE shortening. The ledger is line-based —
  # /why reads the last N lines and learn-from-blocks parses it into the [BLOCKS]
  # summary injected into every session. A multi-line command wrote a multi-line
  # entry, so a fragment like `rm -rf .` appeared as its own row and read as a real
  # destructive block. Shortening alone would still leave an embedded newline.
  safe_cmd="${safe_cmd//$'\n'/ }"; safe_cmd="${safe_cmd//$'\r'/ }"; safe_cmd="${safe_cmd//$'\t'/ }"
  # v2.26.67: 400, was 120. The original rationale — "avoid bloating session context"
  # — stopped being true in v2.26.63, when the [BLOCKS] summary switched to injecting
  # REASONS only and never command text. So the cap no longer protects the context
  # window; it only starves /why and post-hoc analysis.
  #
  # Measured cost of that: a false-positive investigation on 2026-08-06 could not use
  # its own ledger, because the blocks being investigated were `--message` values that
  # sit past character 120 — the fragment retained neither the trigger nor the flag.
  # The log is capped at 500 lines and rotated at 30 days, so 400 costs a few KB.
  safe_cmd="${safe_cmd:0:400}"
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  # v2.7.23: cap the log (was unbounded append — grew to 3.4MB). Keep last 500.
  if [ "$(wc -l < "$blocks_log" 2>/dev/null || echo 0)" -gt 600 ]; then
    tail -n 500 "$blocks_log" > "$blocks_log.tmp" 2>/dev/null && mv "$blocks_log.tmp" "$blocks_log" 2>/dev/null || true
  fi
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# --- Filesystem (category: filesystem) ---
# Validate rm per-segment to defeat compound bypass (`safe && rm -rf /`).
if _cat_enabled "filesystem"; then
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    # v2.26.17: `^rm` required the segment to begin with `rm` at column 0. Segment
    # output is read line-by-line by the loop above, so an INDENTED continuation line
    # arrived as `    rm -rf /` and this anchor rejected it — `echo one\n<TAB>rm -rf /`
    # was ALLOWED while the unindented form was denied. Leading whitespace is now
    # tolerated. This is the change that closed the evasion (see 2.26.18: the
    # cmd-normalize newline work was defence in depth, not the fix).
    if [[ "$seg" =~ ^[[:space:]]*rm[[:space:]] ]]; then
      has_recursive=false
      has_force=false

      # segment may now arrive indented (newline-split); strip before slicing
      seg="${seg#"${seg%%[![:space:]]*}"}"
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
        # v2.26.25: the root arm was `\/[[:space:]]*$` — root ONLY as the last token,
        # so `rm / -rf` slipped by. Now a bare `\/`; the trailing group still requires
        # space/end/slash after it, so `/etc` and `/tmp/x` are untouched. The python
        # block below is the real check — this stays correct because it is the only
        # guard left if python3 is missing (`|| true` fails open).
        if [[ "$args" =~ (^|[[:space:]])(\/|\/\*|~|~\/|\$HOME|\$HOME\/|\$\{HOME\}|\$\{HOME\}\/|\.\.)([[:space:]]|$|\/) ]]; then
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
        # Catch rm targets that resolve to PROJECT_DIR/ancestor (project-dir wipe),
        # OR to a protected absolute system dir (/etc, /usr, ...), OR to home /
        # a sensitive home dotdir (~/.ssh, ...) / another user's home. v2.7.41:
        # added the absolute-target class — previously only cwd-ancestors were
        # caught, so `rm -rf /etc` and `rm -rf ~/.ssh` (absolute) slipped through.
        BAD=$(ARGS="$args" CWD="${PROJECT_DIR:-/}" python3 <<'PYEOF' 2>/dev/null || true
import os, shlex, sys
args = os.environ.get('ARGS','')
cwd  = os.path.realpath(os.environ.get('CWD','/') or '/')
home = os.path.realpath(os.path.expanduser('~'))
SYS_ROOTS = ('/etc','/usr','/bin','/sbin','/lib','/lib64','/boot','/sys','/dev',
             '/proc','/root','/System','/Library','/private/etc')
# NB: deliberately NOT /var or /private/var — macOS temp dirs (mktemp -d ->
# /var/folders/... -> /private/var/...) live there and are legit to rm.
HOME_SENS = ('.ssh','.aws','.gnupg','.config','.kube','.docker','.gcloud','.azure',
             '.password-store','.gpg','.netrc')
try:
    tokens = shlex.split(args, posix=True)
except ValueError:
    sys.exit(0)
for tok in tokens:
    if not tok or tok.startswith('-'): continue
    expanded = os.path.expanduser(os.path.expandvars(tok))
    target = os.path.realpath(os.path.join(cwd, expanded))
    # 1. cwd or an ancestor of cwd (project-dir wipe)
    # v2.26.25: `target + os.sep` is '//' when target is '/', so cwd.startswith()
    # was always False and ROOT — the ancestor that contains everything — was the
    # one ancestor this check could never catch. Every root spelling lands here
    # ('/', '//', '/.', '/..', '"/"' after shlex all realpath to '/'), so the
    # reordered `rm / -rf` and `rm -rf / --no-preserve-root` passed both layers.
    prefix = target if target.endswith(os.sep) else target + os.sep
    if target == cwd or cwd.startswith(prefix):
        print(target); sys.exit(0)
    # 2. protected absolute system root (or under one)
    for r in SYS_ROOTS:
        if target == r or target.startswith(r + os.sep):
            print(target); sys.exit(0)
    # 3. home itself, another user's home (/Users/x, /home/x), or a dotdir in home
    if target == home:
        print(target); sys.exit(0)
    p = target.split('/')
    if len(p) == 3 and p[1] in ('Users','home') and p[2]:
        print(target); sys.exit(0)
    if target.startswith(home + os.sep):
        if target[len(home):].lstrip('/').split('/')[0] in HOME_SENS:
            print(target); sys.exit(0)
PYEOF
)
        if [ -n "$BAD" ]; then
          block "recursive force rm on protected path ($BAD)"
        fi

        # v2.26.83: the python resolver above is INERT ON WINDOWS, and everything it
        # is the only guard for therefore failed OPEN. Proven on a windows-latest
        # runner, not inferred — `rm -rf /etc` (both flag orders), `rm /. -rf`, and
        # deleting the project dir or an ancestor of it were all ALLOWED.
        #
        # Cause: every check there realpath()s the token first. On Windows that maps
        # `/etc` to `D:\etc`, which never equals the POSIX literal in SYS_ROOTS, and
        # os.sep is a backslash so `r + os.sep` builds the nonsense prefix `/etc\`.
        # All three checks (cwd-ancestor, system root, home) break the same way.
        # `rm -rf /` kept blocking via the bash arm above, which is exactly why the
        # CI smoke test stayed green and hid this for the whole port.
        #
        # A TEXT match, gated to Windows. Text is the right layer here: the operator
        # typed `/etc` whatever the platform, so no path resolution is needed to know
        # what they meant. The gate makes the macOS/Linux path provably unchanged —
        # $OSTYPE is never msys/cygwin there, so this block cannot execute.
        #
        # Deliberately mirrors SYS_ROOTS rather than inventing a list, and omits
        # /var for the same reason the python side does (macOS temp dirs).
        case "$OSTYPE" in
          msys*|cygwin*|win32*)
            # System roots, and anything beneath one.
            if [[ "$args" =~ (^|[[:space:]])\"?/(etc|usr|bin|sbin|lib|lib64|boot|sys|dev|proc|root|System|Library)(/|\"?[[:space:]]|\"?$) ]]; then
              block "recursive force rm on protected path (Windows text match)"
            fi
            # Root spellings the bash arm above does not cover: `/.`, `/..`, `//`.
            # Their python equivalents all realpath to '/' on POSIX, which is how
            # they were caught there.
            if [[ "$args" =~ (^|[[:space:]])\"?/(\.|\.\.|/)+\"?([[:space:]]|$) ]]; then
              block "recursive force rm on root (Windows text match)"
            fi
            # The project dir itself, or any ancestor of it. Both forms are POSIX
            # under Git Bash (/d/a/...), so a plain prefix comparison is exact — no
            # resolution, and no drive-letter conversion to get wrong.
            #
            # BOTH the payload's cwd and $PWD, because they are different claims and
            # either being wiped is the thing worth stopping. PROJECT_DIR is the
            # authoritative project for this tool call (payload .cwd, falling back
            # to $PWD at line 77); $PWD is merely where the hook happens to run.
            # Checking only $PWD left a session whose project differs from the
            # hook's cwd with its own root unprotected — `rm -rf <project>` was
            # allowed outright on Windows, where the python resolver that normally
            # catches this cannot run. Checking only PROJECT_DIR would drop the
            # $PWD case that already had coverage. A guard should widen here, not
            # trade one blind spot for another.
            for _tok in $args; do
              case "$_tok" in
                -*) continue ;;
              esac
              _t="${_tok%/}"; _t="${_t%\"}"; _t="${_t#\"}"
              [ -z "$_t" ] && continue
              case "$_t" in
                /*)
                  for _base in "$PROJECT_DIR" "$PWD"; do
                    [ -n "$_base" ] || continue
                    if [ "$_base" = "$_t" ] || case "$_base" in "$_t"/*) true ;; *) false ;; esac; then
                      block "recursive force rm on the project directory or an ancestor (Windows text match)"
                    fi
                  done
                  ;;
              esac
            done
            # v2.26.84: credential dirs reached through an EXPANDED home path. The
            # bash arm above catches `~/.ssh` and `$HOME/.ssh`, and the python
            # resolver catches the expanded form everywhere it works — but on
            # Windows it realpaths `/c/Users/x/.ssh` onto the wrong drive, so it
            # matches neither home nor HOME_SENS. Git Bash expands `~` before the
            # command is ever recorded, so the expanded form is the NORMAL shape
            # there, not an edge case.
            #
            # Measured with the resolver stubbed inert (which is what Windows is):
            #   rm -rf ~/.ssh                 BLOCK   (bash arm)
            #   rm -rf $HOME/.ssh             BLOCK   (bash arm)
            #   rm -rf /c/Users/x/.ssh        allow   <- the gap
            #
            # $HOME here is the hook's own bash HOME, which on Git Bash is the same
            # POSIX form the command text carries — so this compares like with like
            # instead of resolving anything. Mirrors HOME_SENS in the python block.
            if [ -n "${HOME:-}" ]; then
              for _sens in .ssh .aws .gnupg .config .kube .docker .gcloud .azure \
                           .password-store .gpg .netrc; do
                case "$args" in
                  *"$HOME/$_sens"*)
                    block "recursive force rm on a credential directory ($_sens) (Windows text match)"
                    ;;
                esac
              done
            fi
            ;;
        esac
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
  # 2.22.2: allow a /*…*/ SQL comment as an inter-keyword separator, not just
  # whitespace — `DROP/**/TABLE` is valid SQL that the plain [[:space:]]+ missed.
  'DROP([[:space:]]|/\*[^/]*\*/)+TABLE' 'DROP([[:space:]]|/\*[^/]*\*/)+DATABASE'
  'drizzle-kit[[:space:]]+push[[:space:]]+([^&|;]*[[:space:]])?--force([[:space:]]|$)'
  'prisma[[:space:]]+db[[:space:]]+push[[:space:]]+([^&|;]*[[:space:]])?--force-reset([[:space:]]|$)'
  'prisma[[:space:]]+migrate[[:space:]]+reset'
  'typeorm[[:space:]]+schema:drop'
  'sequelize[[:space:]]+db:drop'
  'knex[[:space:]]+migrate:rollback[[:space:]]+([^&|;]*[[:space:]])?--all([[:space:]]|$)'
  # v2.10.5: TRUNCATE (always destructive; Postgres allows the TABLE keyword to be
  # omitted). The leading letter/quote after the space avoids colliding with the
  # unix `truncate -s 0` command (already caught by DESTRUCT_PATTERNS), whose next
  # char is `-`. From sangrokjung/claude-forge db-guard overlap audit.
  'TRUNCATE([[:space:]]|/\*[^/]*\*/)+(TABLE([[:space:]]|/\*[^/]*\*/)+)?["`a-zA-Z_]'
  # DELETE FROM <table> with NO WHERE clause — the mass-wipe footgun (agent means
  # to filter but forgets). Gated: the table identifier must be immediately
  # followed by a statement terminator (;, closing shell quote, backtick, pipe,
  # &, ), or end-of-command), so `DELETE FROM t WHERE ...` (space+letter after the
  # ident) never matches. POSIX ERE has no lookahead, so this is positive-shape.'
)
DELETE_NOWHERE='DELETE([[:space:]]|/\*[^/]*\*/)+FROM([[:space:]]|/\*[^/]*\*/)+["`a-zA-Z_][a-zA-Z0-9_"`.]*[[:space:]]*(;|"|'\''|`|\||&|\)|$)'
DB_PATTERNS+=("$DELETE_NOWHERE")
DESTRUCT_PATTERNS=(
  'chmod[[:space:]]+(-R[[:space:]]+)?777'
  # v2.23.22: setuid/setgid bit — chmod 4755 / 6755 / 2755 / +s / u+s / g+s creates
  # a privilege-escalation / persistence binary. Only chmod 777 was caught before.
  # 4-digit modes with a special leading bit (2/4/6/7); benign 3-digit + 0/1-lead pass.
  'chmod[[:space:]]+([2467][0-7]{3}([[:space:]]|$)|[ugoa]*\+s([[:space:]]|$))'
  'mkfs\.' 'dd[[:space:]]+if='
  '>[[:space:]]*/dev/sd' 'truncate[[:space:]]+-s[[:space:]]*0'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:' 'kill[[:space:]]+-9[[:space:]]+-1'
  # v2.7.41: find-based recursive deletion — same destructive power as rm -rf,
  # and previously unguarded (find . -delete / find ~ -exec rm -rf {}).
  'find[[:space:]].*-delete([[:space:]]|$)' 'find[[:space:]].*-exec[[:space:]]+rm([[:space:]]|$)'
  # v2.9.9: Docker data destruction — `docker volume rm/prune` and `system prune
  # --volumes` delete named volumes (databases, uploads) irreversibly. Plain
  # `system prune` (no --volumes) is left allowed — it only clears dangling
  # images/stopped containers. (from mafiaguy/claude-security-guardrails)
  'docker[[:space:]]+volume[[:space:]]+(rm|prune)([[:space:]]|$)'
  'docker[[:space:]]+system[[:space:]]+prune[^;&|]*--volumes'
  # v2.9.9: system power/shutdown — an agent must not halt the user's machine
  # mid-session. Anchored to COMMAND position (start / after a separator / sudo)
  # so a commit message or echo mentioning "reboot"/"shutdown" is NOT blocked.
  '(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(shutdown|reboot|poweroff|halt)([[:space:]]|$)'
  '(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?init[[:space:]]+[06]([[:space:]]|$)'
  # v2.9.13: partition/disk-destruction — same irreversible class as mkfs/dd
  # (covered above), but the partition-editor family was missing. Read-only forms
  # are excluded: `fdisk -l`, `sfdisk -l`, `parted -l/print`, bare `wipefs` (all
  # list, no /dev target right after the tool / no destructive subcommand).
  # (from wintermeyer/heinzel guard-taboos.sh)
  'wipefs[[:space:]]([^;&|]*[[:space:]])?(-a|--all)([[:space:]]|$)'
  '(^|[[:space:]])(fdisk|gdisk)[[:space:]]+/dev/'
  '(^|[[:space:]])sfdisk[[:space:]]+/dev/'
  'parted[[:space:]][^;&|]*(mklabel|mkpart|resizepart|[[:space:]]rm[[:space:]])'
)
NETWORK_PATTERNS=(
  'curl.*\|.*bash' 'curl.*\|.*sh' 'wget.*\|.*bash' 'wget.*\|.*sh'
  # v2.24.6: this was a blanket "any pipe into a shell". It also caught
  # `printf '{...}' | bash ./hooks/statusline.sh`, where the piped bytes are the
  # script's stdin DATA and the code being run is a named local file — the pipe
  # adds no capability (anyone who can write that file can already run it).
  # Narrowed to the forms where the PIPED BYTES ARE THE CODE:
  #   (a) no script operand at all  — `… | bash`, `… | sh -s`
  #   (b) an explicit -c            — `… | bash -c '…'`
  #   (c) an explicit stdin operand — `… | bash -`, `… | bash /dev/stdin`
  # curl/wget piped to a shell keep their own dedicated patterns above, so the
  # download-and-execute case stays covered twice over.
  '[^|]\|[[:space:]]*(bash|sh|zsh|dash)([[:space:]]+-[[:alnum:]-]+)*[[:space:]]*([;&|)]|$)'
  '[^|]\|[[:space:]]*(bash|sh|zsh|dash)[[:space:]]+-[[:alnum:]]*c([[:space:]]|[;&|)]|$)'
  # The trailing class MUST accept a command separator, not just space-or-end:
  # `… | bash -; echo done` and `… | bash /dev/stdin; echo done` slipped through
  # while it was `([[:space:]]|$)`, because `;` is neither. The old blanket pattern
  # caught these, so narrowing had silently reopened them — found by the
  # pipe-to-shell bases added to fuzz-safety.sh, which is why they were added.
  '[^|]\|[[:space:]]*(bash|sh|zsh|dash)([[:space:]]+-[[:alnum:]-]+)*[[:space:]]+(-|/dev/stdin|/dev/fd/[0-9]+|/proc/self/fd/[0-9]+)([[:space:]]|[;&|)]|$)'
  '(^|;|&|&&|\|\|)[[:space:]]*(bash|sh|zsh)[[:space:]]+-c[[:space:]]'
  '(^|;|&|&&|\|\|)[[:space:]]*eval[[:space:]]+'
  '(^|;|&|&&|\|\|)[[:space:]]*source[[:space:]]+/dev/(tcp|udp)/'
  'base64.*\|.*(bash|sh|zsh)([[:space:]]|$)' '<<<.*\|.*(bash|sh|zsh)([[:space:]]|$)'
  # v2.7.5: `ps` env-dump piped to an encoder/exfil channel. Real incident:
  # "Comment and Control" (CVSS 9.4, Apr 2026) — PR-title injection ran
  # `ps auxeww | base64` to read every process's environment (ANTHROPIC_API_KEY,
  # GITHUB_TOKEN) and exfil it base64-encoded via a PR comment, bypassing secret
  # scanning. Gated on the `e` (env) flag AND a base64/network pipe, so the
  # ubiquitous `ps aux | grep` / `ps -ef | grep` stay allowed.
  'ps[[:space:]]+[a-z-]*e[a-z-]*.*\|.*(base64|curl|wget|ncat|[[:space:]]nc[[:space:]]|xxd|openssl[[:space:]]+enc)'
)
# v2.9.14: cloud/container/IaC credential-theft + escape (category: cloud). An
# agent should not steal instance credentials, mint cloud keys, escape a
# container, read k8s secrets, or tear down infra unprompted. Opt out per-project
# with disableSecurityCategories:["cloud"] for devops work. (from efij Stallion)
CLOUD_PATTERNS=(
  # Cloud instance-metadata SSRF — steals IAM/instance creds (AWS/GCP/ECS IMDS)
  '(169\.254\.169\.254|metadata\.google\.internal|169\.254\.170\.2|/latest/meta-data/|computeMetadata/v1|/metadata/instance)'
  # Assume-role / service-account impersonation → fresh live cloud creds
  'aws[[:space:]]+sts[[:space:]]+assume-role'
  '(--impersonate-service-account|workload-identity-pools[[:space:]]+create-cred-config)'
  'az[[:space:]]+account[[:space:]]+get-access-token'
  # Long-lived cloud key creation
  'aws[[:space:]]+iam[[:space:]]+create-access-key'
  'gcloud[[:space:]]+iam[[:space:]]+service-accounts[[:space:]]+keys[[:space:]]+create'
  'az[[:space:]]+ad[[:space:]]+(app|sp)[[:space:]]+credential[[:space:]]+reset'
  # Container escape — host sockets, privileged/host namespaces, nsenter, chroot /host
  # (--net=host deliberately omitted: too common in legit dev to block)
  '(--privileged|--pid=host|--cap-add=SYS_ADMIN|/var/run/docker\.sock|/run/docker\.sock|/run/containerd/containerd\.sock|/run/crio/crio\.sock|/run/podman/podman\.sock|chroot[[:space:]]+/host|(^|[[:space:]])nsenter([[:space:]]|$))'
  # k8s: cluster-admin RBAC grant + secret exfil (gated on kubectl verb / data form)
  'kubectl[^;&|]*(apply|create)[^;&|]*(clusterrolebinding|cluster-admin)'
  'kubectl[[:space:]]+(get|describe)[[:space:]]+secret[^;&|]*(-o[[:space:]]+ya?ml|-o[[:space:]]+json|jsonpath=\{\.data)'
  # IaC teardown of live resources (destroy subcommand, not `plan -destroy`)
  '(terraform|tofu|opentofu|terragrunt)[[:space:]]+destroy([[:space:]]|$)'
  'pulumi[[:space:]]+destroy([[:space:]]|$)'
  # Secret material passed through a container build
  '--build-arg[=[:space:]][^[:space:]]*(TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_KEY|API_KEY)='
)
# v2.9.14: persistence tamper beyond the crontab/shell-profile/ssh-key blocks
# already in the persistence category below (category: persistence). All gated
# on a WRITE verb so reads/status stay allowed. (from efij Stallion, cluster 2)
# NOTE ssh-config StrictHostKeyChecking=no / ProxyCommand deliberately NOT
# blocked — too common in legit CI/jump-host automation (would cry-wolf).
PERSIST_PATTERNS=(
  # /etc/sudoers write, visudo, NOPASSWD grant
  '((>>?|tee|sed[[:space:]]+-i|cp|mv)[^;&|]*/etc/sudoers|(^|[[:space:]])visudo([[:space:]]|$)|NOPASSWD:)'
  # append/copy into an authorized_keys file (backdoor SSH access)
  '((>>?|tee|cp|mv|sed[[:space:]]+-i)[^;&|]*authorized_keys|(^|[[:space:]])ssh-copy-id([[:space:]]|$))'
  # scheduled-task persistence: launchd/systemd/cron writes, launchctl load, schtasks /create
  '((>>?|tee|cp|mv)[^;&|]*(Library/(LaunchAgents|LaunchDaemons)|/etc/systemd/system|/\.config/systemd/user|/etc/cron)|launchctl[[:space:]]+(bootstrap|load)|schtasks[^;&|]*/create)'
  # /etc/hosts remap of a package/AI/registry domain (traffic hijack)
  '(github\.com|githubusercontent|anthropic|registry\.npmjs|pypi\.org|files\.pythonhosted|registry-1\.docker)[^;&|]*(>>?|tee)[^;&|]*/etc/hosts'
)
# v2.9.16: exfil/tunnel command patterns (category: network). (from efij Stallion, cluster 3)
EXFIL_PATTERNS=(
  # Chrome/Chromium remote-debug (CDP) — drives the LIVE browser to dump
  # cookies/sessions over a socket; the browser category only guards on-disk paths.
  '(--remote-debugging-(port|pipe))'
  # Reverse tunnels / public exposure of a local port — post-compromise egress + C2
  # that bypasses the no-outbound model. ssh -R (reverse) / -D (dynamic SOCKS).
  '((^|[[:space:]])(ngrok|cloudflared|localtunnel|serveo|chisel|bore|pinggy)([[:space:]]|$)|tailscale[[:space:]]+funnel|(^|[[:space:]])ssh[[:space:]]+[^;&|]*-[RD]([[:space:]]|$))'
  # Remote-script dropper (SPLIT form the `| sh` rule misses): fetch a script file,
  # then chmod +x / interpret / ./ it in the same command chain.
  '(curl|wget)[^;&|]*\.(sh|bash|ps1|py)([[:space:]]|>|$)[^;]*(;|&&|\|\|)[[:space:]]*(chmod[^;&|]*\+x|(^|[[:space:]])(bash|sh|python|node)[[:space:]]|\./)'
)
# v2.9.14: credential-store abuse commands (category: credentials).
CRED_CMD_PATTERNS=(
  # enable plaintext git credential store (downgrades secure helper)
  'git[[:space:]]+config[^;&|]*credential\.helper[[:space:]]+store'
  # dump the OS credential store
  '(security[[:space:]]+dump-keychain|secret-tool[[:space:]]+lookup|(^|[[:space:]])cmdkey[[:space:]]+/list)'
  # v2.24.13: targeted Keychain READS. `dump-keychain` was covered, but the
  # single-item lookups were not — and they are the form actually used, since they
  # need no GUI confirmation and return one credential straight to stdout:
  #   security find-generic-password -s github -w     (token/password by service)
  #   security find-internet-password -s github.com -w
  # `-w` prints the secret alone. Also `export` (bulk key material out of a keychain)
  # and `find-certificate -p` (PEM incl. private keys where permitted).
  # This shape was already listed as dangerous in tests/fuzz-safety.sh but no pattern
  # implemented it, so it sat in the false-negative count as 100 of 300 entries.
  '(^|[[:space:]])security[[:space:]]+(find-(generic|internet)-password|export|find-certificate)([[:space:]]|$)'
)
# v2.24.13: synthetic input injection (category: clipboard — same "drive the user's
# desktop" surface). `osascript -e 'tell app "System Events" to keystroke ...'` types
# into whatever window has focus, so it can drive a GUI app, a password prompt, or a
# terminal the agent is not supposed to touch — an authorization bypass that never
# goes through a guarded tool. `key code` is the same primitive by keycode, and
# cliclick is the third-party equivalent. Like the Keychain reads above, this was
# declared dangerous by the fuzzer (125 of the 300 false negatives) with no pattern
# behind it. Anchored on the keystroke/click verbs so ordinary osascript automation
# (notifications, `display dialog`, app queries) still passes.
INPUT_INJECT_PATTERNS=(
  'osascript[^;&|]*(keystroke|key[[:space:]]+code)'
  '(^|[[:space:]])cliclick([[:space:]]|$)'
  'osascript[^;&|]*System[[:space:]]+Events[^;&|]*(click|perform[[:space:]]+action)'
)

# 2.22.11: PowerShell-native destructive / code-exec / remote-fetch-to-exec /
# policy-bypass patterns. safety.sh matches the PowerShell tool but every other
# pattern here is unix-only, so these were the whole PowerShell surface. Matched
# case-insensitively (PS is case-insensitive) and specific enough not to fire on
# Bash. Gated under the destructive/network categories.
POWERSHELL_PATTERNS=(
  'Remove-Item[^;&|]*-(Recurse|Force|r[[:space:]]|fo)'
  'Remove-Item[^;&|]*-(Recurse|Force)'
  '(^|[^A-Za-z])(Invoke-Expression|iex)([[:space:]]|\()'
  '(Invoke-WebRequest|Invoke-RestMethod|iwr|irm|New-Object[[:space:]]+Net\.WebClient)[^;&|]*(DownloadString|DownloadFile|OutFile)'
  '(DownloadString|DownloadData)[[:space:]]*\('
  '(Invoke-WebRequest|Invoke-RestMethod|iwr|irm)[^;&|]*\|[[:space:]]*(iex|Invoke-Expression)'
  '(Set-ExecutionPolicy|-ExecutionPolicy)[[:space:]]+(Bypass|Unrestricted)'
  '(powershell|pwsh)[^;&|]*[[:space:]]-e(nc|ncodedcommand)?[[:space:]]'
  '(powershell|pwsh)[^;&|]*-(nop|NoProfile)[^;&|]*-(w|WindowStyle)[[:space:]]*Hidden'
)

DANGEROUS_PATTERNS=()
_cat_enabled "database" && DANGEROUS_PATTERNS+=("${DB_PATTERNS[@]}")
if _cat_enabled "destructive" || _cat_enabled "network"; then DANGEROUS_PATTERNS+=("${POWERSHELL_PATTERNS[@]}"); fi
_cat_enabled "destructive" && DANGEROUS_PATTERNS+=("${DESTRUCT_PATTERNS[@]}")
_cat_enabled "network" && DANGEROUS_PATTERNS+=("${NETWORK_PATTERNS[@]}")
_cat_enabled "network" && DANGEROUS_PATTERNS+=("${EXFIL_PATTERNS[@]}")
_cat_enabled "cloud" && DANGEROUS_PATTERNS+=("${CLOUD_PATTERNS[@]}")
_cat_enabled "persistence" && DANGEROUS_PATTERNS+=("${PERSIST_PATTERNS[@]}")
_cat_enabled "credentials" && DANGEROUS_PATTERNS+=("${CRED_CMD_PATTERNS[@]}")
_cat_enabled "clipboard" && DANGEROUS_PATTERNS+=("${INPUT_INJECT_PATTERNS[@]}")

# v2.26.65: blank the VALUE of -m/--message before pattern matching. These patterns
# match the raw command with no awareness of shell quoting, so prose inside a commit
# or release message was treated as executable. Measured on a benign corpus: 4 of 14
# ordinary commands denied, two of them commit messages —
#   git commit -m "fix: truncate the log output"   -> TRUNCATE ... pattern
#   git commit -m "docs: when to DROP TABLE"       -> DROP TABLE pattern
# Both are inert: a message body is data git stores, never a command it runs.
#
# safety-detect.py's check_sensitive_read has exempted `git commit`/`git tag` since
# it was written, so this follows the existing design rather than inventing a hole.
#
# Scoped deliberately:
#   - Only the quoted VALUE is blanked, never the rest of the line, so
#     `git commit -m "x" && rm -rf /` still denies on the rm.
#   - Only -m/--message. `git commit -F -` heredoc bodies are NOT stripped: finding a
#     heredoc terminator in a newline-collapsed string is ambiguous, and guessing wrong
#     removes real commands from the scan — a false NEGATIVE, the direction that must
#     not fail. Use -m for messages that trip a pattern.
#   - An unterminated quote matches nothing and is left intact, so malformed input is
#     scanned in full rather than silently skipped.
# v2.26.68: --body and --notes join the list. The v2.26.65 pass enumerated -m and
# --message and stopped there, so `gh pr create --body "...DROP TABLE..."` still
# denied. safety-detect.py check_sensitive_read had ALREADY listed `gh pr|issue|
# release create` as message-bearing — the enumeration existed and was not consulted.
CMD_SCAN="$CMD"
case "$CMD_SCAN" in
  *-m\ *|*--message\ *|*--body\ *|*--notes\ *)
    CMD_SCAN=$(printf '%s' "$CMD_SCAN" | LC_ALL=C sed -E \
      -e "s/((^|[[:space:]])(-m|--message|--body|--notes)[[:space:]]+)'[^']*'/\1''/g" \
      -e 's/((^|[[:space:]])(-m|--message|--body|--notes)[[:space:]]+)"[^"]*"/\1""/g')
    ;;
esac

if [ ${#DANGEROUS_PATTERNS[@]} -gt 0 ]; then
  JOINED_DANGEROUS=$(IFS='|'; echo "${DANGEROUS_PATTERNS[*]}")
  if printf '%s\n' "$CMD_SCAN" | LC_ALL=C grep -qiE "$JOINED_DANGEROUS"; then
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
      if printf '%s\n' "$CMD_SCAN" | LC_ALL=C grep -qiE "$pattern"; then
        block "dangerous pattern: $pattern"
      fi
    done
  fi
fi

# --- Per-project custom patterns (v2.26.21) ----------------------------------
# Deliberately a SEPARATE grep from the built-ins above, never joined with them.
# Every built-in pattern is combined into one alternation and matched in a single
# call; a malformed user regex added to that alternation would make grep error, the
# `if` go false, and EVERY built-in destructive pattern silently stop matching. One
# bad character in a project config would disable the guard.
#
# Isolated, the worst case is that the custom patterns themselves do not fire — the
# built-ins are untouched, and the failure is announced rather than silent.
# Additive only: a project can tighten the guard, never loosen it.
# v2.26.34: per-project. This was the last config file on a shared global path
# after v2.26.33 — one project's extra block rules fired in every other project,
# surfacing as false positives somewhere the user never configured anything.
if type sc_scope_resolve >/dev/null 2>&1; then
  sc_scope_resolve ".custom-patterns" "$PROJECT_DIR"
  _CUSTOM_PAT_FILE="$SC_SCOPE_FILE"
else
  _CUSTOM_PAT_FILE="$SUPERCHARGER_STATE/scope/.custom-patterns"
fi
if [ -s "$_CUSTOM_PAT_FILE" ]; then
  _CUSTOM_JOINED=$(tr '\n' '|' < "$_CUSTOM_PAT_FILE" 2>/dev/null | sed 's/|$//')
  if [ -n "$_CUSTOM_JOINED" ]; then
    printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$_CUSTOM_JOINED" 2>/dev/null
    _CUSTOM_RC=$?
    if [ "$_CUSTOM_RC" -eq 0 ]; then
      while IFS= read -r _cp; do
        [ -z "$_cp" ] && continue
        if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$_cp" 2>/dev/null; then
          block "custom project pattern: $_cp"
        fi
      done < "$_CUSTOM_PAT_FILE"
    elif [ "$_CUSTOM_RC" -gt 1 ]; then
      # Invalid regex in .supercharger.json. Say so — a silently ignored rule the user
      # believes is protecting them is worse than no rule.
      echo "[Supercharger] customPatterns in .supercharger.json contains an invalid regex — those rules are NOT active. Built-in guards are unaffected." >&2
    fi
  fi
fi

if _cat_enabled "filesystem"; then
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if [[ "$seg" =~ ^[[:space:]]*mv[[:space:]]+(\/|~|\$HOME)[[:space:]] ]]; then
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

  # 2.22.2: permissive target (a quote between `$HOME`/`~`/`/`/`.bashrc` broke the
  # old contiguous regex — `>> "$HOME/.bashrc"`, `>> ~/'.bashrc'`) + copy verbs
  # (cp/mv/install/rsync/dd overwriting a profile evaded the redirect-only check).
  _PROF_FILE='\.(bashrc|zshrc|profile|bash_profile|zprofile)([[:space:]"'\''`;&|)]|$)'
  _PROF_REDIR=">>?[[:space:]]*[^|;&<>()]*${_PROF_FILE}"
  _PROF_COPY="(^|[[:space:];&|])(cp|mv|install|rsync|dd)[[:space:]][^|;&]*${_PROF_FILE}"
  if [[ "$CMD" =~ $_PROF_REDIR ]] || [[ "$CMD" =~ $_PROF_COPY ]]; then
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
# v2.8.6: keep parity with path-guard's selfmod set (Write/Edit channel). This
# is the Bash channel for the SAME attack — writing guardrail config via a shell
# redirect. It had drifted narrow (only .claude/settings.json + CLAUDE.md), so
# `echo '{"disableSecurityCategories":[...]}' > .supercharger.json` and appends
# to the scope disable-files slipped through and could disable the guards.
# v2.10.6: only fire when a guardrail-config file is the TARGET of a WRITE. The
# prior check ORed "mentions a config name" with "contains any >/verb substring",
# so a READ-ONLY command like `cat scope/.disabled-hooks 2>/dev/null` tripped it
# (the `2>` fd-redirect matched the bare `>`) — a false positive on introspection
# commands like /sc-status. Now the redirect/verb must target the config file
# itself; plain reads and unrelated fd-redirects are allowed through.
_SELFMOD_CFG='(\.claude/settings(\.local)?\.json|\.claude/CLAUDE\.md|\.claude\.json|\.supercharger\.json|\.mcp\.json|\.disabled-security-categories|\.disabled-hooks)'
# (a) redirect INTO a config file: `> cfg`, `>> cfg`, `2> cfg` (fd + optional path)
_SELFMOD_REDIR="[0-9]*>>?[[:space:]]*[^[:space:];&|]*$_SELFMOD_CFG"
# (b) in-place edit / move / copy / remove / truncate whose argument is a config file
_SELFMOD_VERB="(^|[[:space:];&|])(sed[[:space:]]+-i|tee|mv|cp|rm|truncate|install|ln|rsync|dd[[:space:]]+of=)[^;&|]*$_SELFMOD_CFG"
# (c) interpreter opening a config file in write/append mode
_SELFMOD_PY="(python|perl|ruby)[^;&|]*open[^;&|]*${_SELFMOD_CFG}[^;&|]*,[[:space:]]*['\"][wa]"
if _cat_enabled "selfmod" \
   && { [[ "$CMD" =~ $_SELFMOD_REDIR ]] || [[ "$CMD" =~ $_SELFMOD_VERB ]] || [[ "$CMD" =~ $_SELFMOD_PY ]]; }; then
  block "self-modification — agent should not directly edit its own guardrail config files"
fi

# --- Unified detector (shell-wrapper, env-file, exfiltration) ---
# Single python3 fork covers 3 categories that previously required 3 separate hooks.
# Fast-path: skip the fork unless the command contains a trigger keyword.
_NEED_PY=false
case "$CMD" in
  *python*\ -c*|*node\ -e*|*node\ --eval*|*node\ -p*|*node\ --print*|*perl\ -e*|*ruby\ -e*|*dash\ -c*|*ksh\ -c*|*fish\ -c*) _NEED_PY=true ;;
  *npx*\ -c*|*deno\ eval*|*bun\ -e*|*bun\ --eval*) _NEED_PY=true ;;
  # v2.7.14: gate must be a SUPERSET of safety-detect.py's _SENSITIVE_NAME_RE,
  # else those detector patterns are unreachable. Added .my.cnf/.authinfo/.crt/.cer.
  *.env*|*.npmrc*|*.pypirc*|*.pgpass*|*.my.cnf*|*.authinfo*|*.netrc*|*.git-credentials*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*|*.pem*|*.key*|*.crt*|*.cer*|*.p12*|*.pfx*|*.ppk*) _NEED_PY=true ;;
  # v2.10.1: terraform var / token-store files (from chuckreynolds secret-guardrails)
  *.tfvars*|*.tokens.json*) _NEED_PY=true ;;
  *kubeconfig*|*.kube/config*) _NEED_PY=true ;;
  *aws*|*gsutil*|*azcopy*|*az\ storage*|*rclone*|*s3cmd*) _NEED_PY=true ;;
  *curl*|*wget*|*nc\ *|*netcat*) _NEED_PY=true ;;
  *dnscat*|*iodine*|*dns2tcp*|*dnsexfil*) _NEED_PY=true ;;
  # v2.9.16: DNS resolver tools — the detector's dig/nslookup exfil arm needs these.
  *dig\ *|*nslookup*|*drill\ *|*\ host\ *) _NEED_PY=true ;;
  *xargs*|*find*\ -name*|*find*\ -iname*|*find*\ -regex*|*find*\ -exec*) _NEED_PY=true ;;
  *secret*|*credential*|*wallet*) _NEED_PY=true ;;
esac

if [ "$_NEED_PY" = "true" ] && [ -x "$(command -v python3 2>/dev/null)" ]; then
  # Cap Python fork at 500ms — defensive against runaway regex / deep traversal.
  if command -v gtimeout >/dev/null 2>&1; then _TIMEOUT="gtimeout 0.5"
  elif command -v timeout >/dev/null 2>&1; then _TIMEOUT="timeout 0.5"
  else _TIMEOUT=""
  fi
  # `|| PY_REASON=""` (2.17.3): the deep scanner is defense-in-depth ON TOP of the
  # regex checks already run above. If it exits non-zero for ANY reason — missing
  # file (python exits 2), crash, or the 0.5s timeout — `set -e` would otherwise
  # kill this hook with empty stderr, which CC renders as a phantom
  # "hook error: No stderr output" deny. Fail OPEN to the regex verdict instead.
  PY_REASON=$(CMD="$CMD" DISABLED_CATS="$_DISABLED_CATS" $_TIMEOUT python3 "${BASH_SOURCE[0]%/*}/safety-detect.py" 2>/dev/null) || PY_REASON=""
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
