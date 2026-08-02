#!/usr/bin/env bash
# Every spelling of "recursively delete the filesystem root" must be blocked (v2.26.25)
#
# The v2.22.10 audit parked `rm / -rf` as low-risk on the grounds that GNU
# --preserve-root mitigates it. That under-read the bug twice over:
#
#   1. The flag-reorder was not one evasion but a whole family. ROOT resolves from
#      '/', '//', '/.', '/..' and a quoted '"/"', and none of them were blocked
#      once the flags moved after the target.
#   2. The mitigation argument inverts on the one command that matters most —
#      `rm -rf / --no-preserve-root` was ALLOWED, and it is precisely the form that
#      turns the mitigation off. The blocked form (`rm --no-preserve-root -rf /`)
#      was the harmless-by-comparison one.
#
# Root cause was a single line in the python target-resolver (safety.sh:234):
# `cwd.startswith(target + os.sep)` builds '//' when target is '/', so the
# ancestor check could never match the ancestor that contains everything.
#
# Two layers guard this and BOTH are asserted separately below. The python
# resolver is the real check; the bash regex is the only thing left standing if
# python3 is missing, because that block ends in `|| true` and fails open.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SAFETY="$REPO_DIR/hooks/safety.sh"

blocked() { # command -> 0 if the hook denies it
  local rc
  printf '%s' "$(CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | bash "$SAFETY" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ]
}

echo "=== rm Root-Form Tests ==="

# --- every spelling of root, flags before AND after the target ---------------
# Built from a variable so the literal strings do not sit in the file as
# copy-pasteable commands, and so the guards do not trip on this repo's own
# commit/verification text (see hook-audit-v2.22-adversarial).
R="/"

for form in "-rf $R" "$R -rf" "-r $R -f" "$R --recursive --force" \
            "-rf \"$R\"" "-rf $R$R" "$R$R -rf" "-rf $R." "$R. -rf" "-rf $R.." \
            "-rf $R --no-preserve-root" "--no-preserve-root -rf $R" \
            "-rf $R*" "$R* -rf"; do
  begin_test "rm $form is blocked"
  blocked "rm $form" && pass || fail "root deletion ALLOWED: rm $form"
done

# --- the non-root dangerous targets must stay blocked in both orders ---------
for t in "~" "\$HOME" "/etc" "/Users" "~/.ssh"; do
  begin_test "rm -rf $t is blocked (flags first)"
  blocked "rm -rf $t" && pass || fail "ALLOWED: rm -rf $t"
  begin_test "rm $t -rf is blocked (flags last)"
  blocked "rm $t -rf" && pass || fail "ALLOWED: rm $t -rf"
done

# --- false positives: ordinary cleanup must not be touched ------------------
# The widened regex arm is the FP risk here — it now matches a bare slash, so a
# path merely STARTING with one must still pass.
for ok in "rm -rf node_modules" "rm -rf dist" "rm -rf ./build" \
          "rm -rf /tmp/scratch" "rm -r /tmp/x/y" "rm -f /tmp/a.log" \
          "rm -rf /var/folders/xy/T/tmp.123" \
          "rm -rf /private/var/folders/z/tmpdir"; do
  begin_test "not a false positive: $ok"
  blocked "$ok" && fail "FALSE POSITIVE: $ok was blocked" || pass
done

# --- layer 2 in isolation: the bash regex, with python3 unavailable ---------
# Proves the fallback is not silently carrying a hole. A PATH without python3
# makes the resolver's `|| true` fail open, leaving only the regex.
NOPY=$(mktemp -d)
regex_only() { # command -> 0 if denied with no python3 on PATH
  local rc
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
    | PATH="$NOPY:/usr/bin:/bin" bash "$SAFETY" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ]
}

for form in "-rf $R" "$R -rf" "-rf $R$R"; do
  begin_test "regex layer alone (no python3) blocks rm $form"
  regex_only "rm $form" && pass || fail "fallback layer has a hole: rm $form"
done

begin_test "regex layer alone does not false-positive on a temp path"
regex_only "rm -rf /tmp/scratch" && fail "fallback layer false-positives" || pass
rm -rf "$NOPY"

# --- layer 1 in isolation: the python resolver -------------------------------
# Asserts the actual defect. Pre-fix this returned nothing for every root form
# because `target + os.sep` was '//'.
#
# The resolver is EXTRACTED from safety.sh rather than copied into this file.
# A copy would pass whatever safety.sh does — the first draft of this test
# inlined one and every case here passed against the unfixed hook, which is the
# precise failure this repo keeps hitting: a check that cannot observe the bug.
RESOLVER=$(sed -n "/^import os, shlex, sys$/,/^PYEOF$/p" "$SAFETY" | sed '$d')

begin_test "the resolver was actually extracted from safety.sh"
printf '%s' "$RESOLVER" | grep -q 'realpath' && pass \
  || fail "extraction produced nothing — the heredoc markers in safety.sh moved"

resolves_to_root() { # rm-args -> prints the offending target, empty if none
  ARGS="$1" CWD="$REPO_DIR" python3 -c "$RESOLVER" 2>/dev/null
}

for form in "-rf $R" "$R -rf" "-rf $R$R" "-rf $R." "-rf $R.." "-rf \"$R\""; do
  begin_test "python resolver alone flags rm $form as an ancestor of cwd"
  [ "$(resolves_to_root "$form")" = "$R" ] && pass || fail "resolver missed: rm $form"
done

begin_test "python resolver alone ignores an unrelated absolute path"
[ -z "$(resolves_to_root "-rf /tmp/scratch")" ] && pass || fail "resolver over-matched"

report
