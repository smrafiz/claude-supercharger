#!/usr/bin/env bash
# safety.sh false-positive corpus (v2.26.65)
#
# The patterns match the raw command with no awareness of shell quoting, so prose
# inside an inert argument value was treated as executable. Measured on a benign
# corpus before the fix: 4 of 14 ordinary developer commands denied.
#
# The FP half of this file is only half the point. Every narrowing here has a
# matching attack case, because the last time a guard was narrowed to clear false
# positives (v2.24.9) it opened a real gap. The cases that must STILL deny are the
# ones worth re-reading before touching any pattern below.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Sensitive literals are assembled at runtime. Written out, they would trip the
# deployed guard on the test file itself — this suite cannot be edited or grepped
# without that happening, which is the bug it pins.
E=".env"; NPM=".npmrc"

probe() { # command -> "BLOCK" | "allow"
  local st out rc
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  out=$(ST="$st" CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["ST"]}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/safety.sh" 2>/dev/null)
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'allow'
}

allows() { # label, command
  local got; got=$(probe "$2")
  [ "$got" = "allow" ] && pass || fail "$1: expected allow, got BLOCK"
}
denies() { # label, command
  local got; got=$(probe "$2")
  [ "$got" = "BLOCK" ] && pass || fail "$1: expected BLOCK, got allow — GUARD GAP"
}

echo "=== safety.sh False-Positive Corpus ==="

# --- the four measured false positives ----------------------------------------
begin_test "commit message mentioning truncation is not a SQL command"
allows "truncate-prose" 'git commit -m "fix: truncate the log output before writing"'

begin_test "commit message documenting a schema change is not a schema change"
allows "droptable-prose" 'git commit -m "docs: when to DROP TABLE during a migration"'

begin_test "a release --message carrying prose is not executable"
allows "release-message" "bash tools/release.sh patch --message 'perf: truncate the cache index'"

begin_test "grepping source for a property access is not file access"
allows "process-env" "grep -rn \"process${E}\" src/"

begin_test "a build-tool env property is not file access either"
allows "meta-env" "rg \"import.meta${E}\" ."

# --- the narrowings must NOT open a gap ----------------------------------------
begin_test "GAP CHECK: a payload after a message is still denied"
# The reason only the VALUE is blanked, never the rest of the line.
denies "payload-after-message" 'git commit -m "safe subject" && rm -rf /'

begin_test "GAP CHECK: a payload after a single-quoted message is still denied"
denies "payload-after-sq" "git commit -m 'safe subject' ; rm -rf /"

begin_test "GAP CHECK: blanking is bounded — a payload BETWEEN two messages denies"
# The real hazard of a global s/-m "[^"]*"/g: if the match ran from the first quote
# to the last, everything between two messages would vanish from the scan. `[^"]*`
# bounds it, and this is what proves it.
denies "between-messages" 'git commit -m "a" && rm -rf / && git tag -m "b"'

begin_test "an unterminated quote is allowed, because bash never runs it"
# Asserted deliberately, having first checked what bash does: `git commit -m "oops ;
# rm -rf /` is a syntax error (unexpected EOF looking for a matching quote), so the
# rm cannot execute. An earlier draft of this suite asserted BLOCK here and called
# the result a guard gap; it failed identically against the pre-fix hook, which is
# what prompted checking the shell instead of trusting the assertion.
allows "unterminated" 'git commit -m "oops ; rm -rf /'

begin_test "GAP CHECK: -m does not exempt a real command elsewhere on the line"
denies "m-flag-elsewhere" 'grep -m 1 foo bar.txt && rm -rf /'

begin_test "GAP CHECK: real env-file reads are still denied"
denies "env-read" "cat ${E}"

begin_test "GAP CHECK: named env files are still denied"
# The regression a general left boundary would have introduced: prod/backup/staging
# env files are real credential stores whose names look exactly like the idioms.
denies "prod-env" "cat prod${E}"

begin_test "GAP CHECK: backup env files are still denied"
denies "backup-env" "cat backup${E}"

begin_test "GAP CHECK: direnv files are still denied"
denies "envrc" "cat ${E}rc"

begin_test "GAP CHECK: other credential stores are unaffected"
denies "npmrc" "cat ${NPM}"

begin_test "GAP CHECK: an executed shell string is still denied"
# The case that makes blanket quote-stripping unsafe: here the danger IS the quoted
# text, because bash -c runs it.
denies "bash-c" 'bash -c "rm -rf /"'

report
