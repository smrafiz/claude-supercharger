#!/usr/bin/env bash
# Claude Supercharger — Command Normalization Helper
# Sourced by PreToolUse hooks that inspect the Bash command string.
# Usage:
#   CMD=$(normalize_cmd "$COMMAND")
#   while IFS= read -r seg; do ...; done < <(split_segments "$CMD")

normalize_cmd() {
  local cmd="$1"
  cmd=$(printf '%s\n' "$cmd" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  cmd=$(printf '%s\n' "$cmd" | sed 's/^\\//')
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
  cmd=$(printf '%s\n' "$cmd" | tr -s ' ')
  printf '%s\n' "$cmd"
}

# Split a shell command on &&, ||, ;, |  into individual segments.
# Quote-aware: separators inside ' " ` are not split on.
# Each segment is normalized (sudo/command/env stripped).
# Output: one segment per line.
split_segments() {
  local cmd="$1"
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
    # Single-char separators
    if c == ';' or c == '|' or c == '&':
        segments.append(''.join(buf)); buf = []; i += 1; continue
    buf.append(c)
    i += 1
segments.append(''.join(buf))

# Strip leading sudo/command/env (mirrors normalize_cmd)
prefixes = re.compile(r'^(sudo|command|env)\s+')
# v2.6.80: strip leading POSIX inline env-var assignments (VAR=value cmd ...).
# Same bypass class found in normalize_cmd — segments after a separator can
# also start with FOO=bar (`echo x; FOO=bar rm -rf /` chains).
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
