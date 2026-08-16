#!/usr/bin/env bash
# Claude Supercharger — Command Normalization Helper
# Helper: not a registered hook — Shared command normaliser (unwraps quoting/obfuscation) sourced by the guards.
# Sourced by PreToolUse hooks that inspect the Bash command string.
# Usage:
#   CMD=$(normalize_cmd "$COMMAND")
#   while IFS= read -r seg; do ...; done < <(split_segments "$CMD")

# Remove heredoc BODIES that are data rather than code.
#
# The guards match the raw command text, and a heredoc body is usually neither
# executed nor interpreted — `cat > corpus.txt <<'EOF'` writes lines to a file.
# Measured on this repo's own block ledger: writing a test fixture containing the
# strings `DROP TABLE users` and `git reset --hard HEAD~1` was blocked four times
# in one session, twice by safety.sh and twice by git-safety.sh, for text that no
# shell would ever run. A gate that fires on inert data is the kind users switch
# off, which costs more than the false positive does.
#
# The exception is the whole safety argument: a body fed to something that
# EXECUTES it is still code. `bash <<'EOF' rm -rf / EOF` runs, and so does
# `psql <<'EOF' DROP TABLE users; EOF`. Those receivers keep their bodies, so
# stripping can never hide a payload from the guards — it only drops text headed
# for a file, a pager or a diff.
#
# `<<<` is a herestring, not a heredoc: it has no body to strip and is left alone.
_HEREDOC_EXECUTORS='bash|sh|zsh|dash|ksh|fish|python|python2|python3|perl|ruby|node|deno|php|osascript|psql|mysql|mariadb|sqlite3|mongosh|mongo|redis-cli|clickhouse-client|cockroach|snowsql|bq|spark-sql|hive|beeline'

strip_heredoc_bodies() {
  local cmd="$1"
  # Hot path: normalize_cmd runs on EVERY Bash tool call, so nothing forks unless
  # the command actually contains a heredoc operator. Commands that do are rare.
  case "$cmd" in
    *'<<'*) ;;
    *) printf '%s' "$cmd"; return 0 ;;
  esac
  # A quoted heredoc, NOT python3 -c with a double-quoted program. Inside a
  # double-quoted -c string bash performs command substitution, and the first
  # draft of this function carried a backtick-quoted example inside a docstring,
  # so running the guard EXECUTED the text it was meant to inspect (observed:
  # a stray "cd: x: No such file or directory" on every call). A quoted-delimiter
  # heredoc body is literal, which removes the whole class rather than this case.
  CMD_INPUT="$cmd" SC_EXEC="$_HEREDOC_EXECUTORS" python3 - <<'SCPYEOF' 2>/dev/null || printf '%s' "$cmd"
import os, re, sys

cmd = os.environ.get('CMD_INPUT', '')
executors = set(os.environ.get('SC_EXEC', '').split('|'))

# <<- allows a tab-indented terminator; <<< is a herestring and is NOT a heredoc.
START = re.compile(r'<<(?!<)(-?)\s*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\2')


def first_token(seg):
    seg = re.sub(r'^\s*(sudo|command|env)\s+', '', seg.strip())
    seg = re.sub(r'^([A-Za-z_][A-Za-z0-9_]*=\S*\s+)+', '', seg)
    parts = seg.split()
    return parts[0].rsplit('/', 1)[-1] if parts else ''


def body_is_executed(line, start, end):
    # Owner: the last segment BEFORE the operator, so "cd x; cat > y <<EOF"
    # resolves to cat rather than cd.
    if first_token(re.split(r'[;&|]', line[:start])[-1]) in executors:
        return True
    # Downstream: "cat <<EOF | sh" feeds the body to a shell even though the
    # owner is cat, so commands after the operator count too.
    for seg in re.split(r'[;&|]', line[end:]):
        if first_token(seg) in executors:
            return True
    return False


lines = cmd.split('\n')
out = []
i = 0
while i < len(lines):
    line = lines[i]
    m = START.search(line)
    if not m:
        out.append(line)
        i += 1
        continue
    dash, delim = m.group(1), m.group(3)
    keep_body = body_is_executed(line, m.start(), m.end())
    out.append(line)
    i += 1
    # Consume through the terminator either way; only the body's fate differs.
    while i < len(lines):
        candidate = lines[i].strip() if dash else lines[i]
        if candidate == delim:
            out.append(lines[i])
            i += 1
            break
        if keep_body:
            out.append(lines[i])
        i += 1

sys.stdout.write('\n'.join(out))
SCPYEOF
}

normalize_cmd() {
  local cmd="$1"
  # Data-only heredoc bodies come out before any matching happens, so every guard
  # sourcing this helper (safety, git-safety, enforce-pkg-manager, commit-guard)
  # gets the same answer — one place, no cross-guard drift.
  cmd=$(strip_heredoc_bodies "$cmd")
  # v2.8.12: pure-bash — was 4×sed + 1×tr (~10ms of forks per call). This helper
  # is sourced by safety.sh, git-safety.sh, enforce-pkg-manager.sh and runs on
  # EVERY Bash tool call, so the forks compounded on the hot path. Parameter
  # expansion is behavior-identical (verified by fuzz-safety + cmd-normalize tests).
  # Trim leading, then trailing whitespace (spaces + tabs).
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  # Strip one leading backslash (was sed 's/^\\//').
  cmd="${cmd#\\}"
  while [[ "$cmd" =~ ^(sudo|command|env)[[:space:]]+ ]]; do
    cmd="${cmd#${BASH_REMATCH[0]}}"
  done
  # v2.6.80: strip leading POSIX inline env-var assignments (VAR=value cmd ...).
  # Fuzz harness found this bypass: `env FOO=bar rm -rf /` stripped to
  # `FOO=bar rm -rf /` and the first token check saw `FOO=bar` instead of `rm`,
  # so the rm-deny rules never fired. Same applies to bare `PATH=/usr/bin rm`
  # without `env`. Loop until no leading assignment remains.
  while [[ "$cmd" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    cmd="${cmd#${BASH_REMATCH[0]}}"
  done
  # Collapse runs of spaces to one (matches `tr -s ' '` — spaces only, not tabs).
  while [[ "$cmd" == *"  "* ]]; do cmd="${cmd//  / }"; done
  printf '%s\n' "$cmd"
}

# Split a shell command on &&, ||, ;, |  into individual segments.
# Quote-aware: separators inside ' " ` are not split on.
# Each segment is normalized (sudo/command/env stripped).
# Output: one segment per line.
split_segments() {
  local cmd="$1"
  # v2.8.12: fork-free fast-path. The python splitter only earns its ~31ms fork
  # when the command actually contains a shell separator (&& || ; |). Most Bash
  # calls (npm test, git status, cat x) have none → a single segment. Any of
  # those chars ANYWHERE (even inside quotes) falls through to the quote-aware
  # python splitter, so this can never mis-split a quoted separator.
  case "$cmd" in
    *'&'*|*'|'*|*';'*) ;;
    *)
      local seg="$cmd"
      # Mirror the python per-segment logic (strip() first, THEN prefixes) so the
      # fast-path is self-contained and order-identical to the fork path.
      seg="${seg#"${seg%%[![:space:]]*}"}"; seg="${seg%"${seg##*[![:space:]]}"}"
      while [[ "$seg" =~ ^(sudo|command|env)[[:space:]]+ ]]; do seg="${seg#${BASH_REMATCH[0]}}"; done
      while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do seg="${seg#${BASH_REMATCH[0]}}"; done
      [ -n "$seg" ] && printf '%s\n' "$seg"
      return ;;
  esac
  CMD_INPUT="$cmd" python3 -c "
import os, re
cmd = os.environ.get('CMD_INPUT', '')

# Walk char-by-char, track quote state, split on shell separators outside quotes.
segments = []
buf = []
i = 0
n = len(cmd)
quote = None  # current quote char or None

while i < n:
    c = cmd[i]
    if quote:
        # Inside a quoted region — include verbatim, watch for closing quote
        buf.append(c)
        if c == '\\\\' and i + 1 < n and quote == '\"':
            # In double quotes, backslash escapes next char
            buf.append(cmd[i + 1])
            i += 2
            continue
        if c == quote:
            quote = None
        i += 1
        continue
    if c in ('\"', \"'\", '\`'):
        quote = c
        buf.append(c)
        i += 1
        continue
    # Two-char operators
    if c == '&' and i + 1 < n and cmd[i + 1] == '&':
        segments.append(''.join(buf)); buf = []; i += 2; continue
    if c == '|' and i + 1 < n and cmd[i + 1] == '|':
        segments.append(''.join(buf)); buf = []; i += 2; continue
    # Single-char separators. '\n' included in v2.26.17 because a newline separates
    # commands exactly as ';' does; reached only outside quotes, so a newline inside a
    # quoted string still does not split. NOTE (2.26.18): this was NOT what fixed the
    # indented-continuation evasion -- safety.sh's read loop already split segment
    # output on newlines. The fix was allowing leading whitespace in the ^-anchored
    # rm/mv checks. This stays as defence in depth for 'a && b' plus newline shapes.
    # (No backticks in this block: it lives inside python3 -c "...", where bash would
    #  treat them as command substitution and RUN them.)
    if c == ';' or c == '|' or c == '&' or c == '\n':
        segments.append(''.join(buf)); buf = []; i += 1; continue
    buf.append(c)
    i += 1
segments.append(''.join(buf))

# Strip leading sudo/command/env (mirrors normalize_cmd)
prefixes = re.compile(r'^(sudo|command|env)\s+')
# v2.6.80: strip leading POSIX inline env-var assignments (VAR=value cmd ...).
# Same bypass class found in normalize_cmd — segments after a separator can
# also start with FOO=bar (a chained segment after a separator).
env_var = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=\S*\s+')
for seg in segments:
    seg = seg.strip()
    while True:
        m = prefixes.match(seg)
        if not m:
            break
        seg = seg[m.end():].lstrip()
    while True:
        m = env_var.match(seg)
        if not m:
            break
        seg = seg[m.end():].lstrip()
    if seg:
        print(seg)
" 2>/dev/null
}
