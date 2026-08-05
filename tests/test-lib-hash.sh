#!/usr/bin/env bash
# Portable MD5 helper (v2.26.50, WINDOWS-SUPPORT-PLAN G2)
#
# Eight hooks derived per-project state KEYS from a chain like:
#
#     printf '%s' "$X" | md5sum 2>/dev/null | cut -d' ' -f1 \
#       || printf '%s' "$X" | md5 -q 2>/dev/null || echo "global"
#
# The fallback is UNREACHABLE: `||` binds to the pipeline, whose status is
# `cut`'s, and cut exits 0 on empty input. With md5sum absent the chain yields
# "" — never the md5 arm, never "global".
#
# An empty key is not a missing feature, it is a COLLISION: every project shares
# `.failed-commands-`, one quality-gate cache, one session-memory file. Same
# class as audit HIGH #13 (v2.26.33), reintroduced through a broken fallback.
# Invisible on macOS/Linux CI because both ship md5sum or md5; Git Bash has
# neither, which is how the Windows work surfaced it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-hash.sh"

echo "=== Portable MD5 Helper Tests ==="

# Run sc_md5 with only the named tools reachable, to exercise each tier.
with_tools() { # "tool1 tool2 ..." , input -> digest
  local tools="$1" input="$2" bindir
  bindir=$(mktemp -d)/bin; mkdir -p "$bindir"
  # Core shell utilities every tier needs.
  local t src
  for t in cut sed printf env bash python3 $tools; do
    src=$(command -v "$t" 2>/dev/null) && [ -n "$src" ] && ln -sf "$src" "$bindir/$t" 2>/dev/null
  done
  # python3 is only linked when explicitly requested OR needed as the last tier.
  case " $tools " in *" python3 "*) ;; *) rm -f "$bindir/python3" ;; esac
  ( export PATH="$bindir"; . "$LIB"; printf '%s' "$input" | sc_md5 )
  rm -rf "$(dirname "$bindir")"
}

KNOWN="/some/project"
# Reference digest from python, independent of which CLI tool is used.
EXPECT=$(printf '%s' "$KNOWN" | python3 -c 'import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())')

begin_test "the helper exists and defines sc_md5"
[ -f "$LIB" ] && grep -q '^sc_md5()' "$LIB" && pass || fail "lib-hash.sh missing or has no sc_md5"

begin_test "md5sum tier produces the correct digest"
if command -v md5sum >/dev/null 2>&1; then
  [ "$(with_tools 'md5sum' "$KNOWN")" = "$EXPECT" ] && pass || fail "md5sum tier wrong: $(with_tools 'md5sum' "$KNOWN")"
else
  pass  # not installed here; the tier is covered by the other platform in CI
fi

begin_test "md5 (BSD) tier produces the correct digest"
if command -v md5 >/dev/null 2>&1; then
  [ "$(with_tools 'md5' "$KNOWN")" = "$EXPECT" ] && pass || fail "md5 tier wrong: $(with_tools 'md5' "$KNOWN")"
else
  pass
fi

begin_test "openssl tier produces the correct digest"
if command -v openssl >/dev/null 2>&1; then
  [ "$(with_tools 'openssl' "$KNOWN")" = "$EXPECT" ] && pass || fail "openssl tier wrong: $(with_tools 'openssl' "$KNOWN")"
else
  pass
fi

begin_test "python3 tier produces the correct digest (the Git Bash path)"
# No md5sum, no md5, no openssl — exactly what Git Bash offers.
[ "$(with_tools 'python3' "$KNOWN")" = "$EXPECT" ] && pass \
  || fail "python3 tier wrong: $(with_tools 'python3' "$KNOWN")"

begin_test "ALL tiers agree with each other"
SEEN=""
for t in md5sum md5 openssl python3; do
  command -v "$t" >/dev/null 2>&1 || continue
  D=$(with_tools "$t" "$KNOWN")
  [ -n "$D" ] && SEEN="$SEEN$D\n"
done
UNIQ=$(printf "$SEEN" | sort -u | grep -c . || true)
[ "$UNIQ" = "1" ] && pass || fail "tiers disagree ($UNIQ distinct digests)"

begin_test "no backend at all yields empty, not a partial string"
OUT=$(with_tools '' "$KNOWN")
[ -z "$OUT" ] && pass || fail "expected empty with no backend, got [$OUT]"

begin_test "output is always digest-shaped or empty"
# A tool that prints an error to stdout must not become a state-file name.
OUT=$(with_tools 'python3' "$KNOWN")
case "$OUT" in
  [0-9a-f]*) [ ${#OUT} -eq 32 ] && pass || fail "digest length ${#OUT}, expected 32" ;;
  "") fail "python3 tier produced nothing" ;;
  *) fail "non-hex output: [$OUT]" ;;
esac

# --- the bug this replaces ---------------------------------------------------
begin_test "the OLD chain returned empty (proving the fallback was unreachable)"
BINDIR=$(mktemp -d)/bin; mkdir -p "$BINDIR"
for t in cut printf bash sed; do
  s=$(command -v "$t" 2>/dev/null) && [ -n "$s" ] && ln -sf "$s" "$BINDIR/$t" 2>/dev/null
done
OLD=$(PATH="$BINDIR" bash -c 'X=/some/project; printf "%s" "$X" | md5sum 2>/dev/null | cut -d" " -f1 || printf "%s" "$X" | md5 -q 2>/dev/null || echo "global"' 2>/dev/null)
rm -rf "$(dirname "$BINDIR")"
[ -z "$OLD" ] && pass || fail "old chain returned [$OLD] — the premise of this fix is wrong"

begin_test "no hook still uses the broken md5sum||md5 chain"
# lib-hash.sh quotes the broken chain in its own header comment, explaining why
# it exists — matching that would fail forever on the documentation.
BAD=$(grep -ln 'md5sum 2>/dev/null | cut' "$REPO_DIR"/hooks/*.sh 2>/dev/null | grep -v 'lib-hash\.sh' || true)
[ -z "$BAD" ] && pass || fail "still present in: $BAD"

begin_test "every sc_md5 caller can resolve the helper"
MISS=""
for f in $(grep -rl 'sc_md5' "$REPO_DIR"/hooks/*.sh | grep -v lib-hash); do
  grep -q 'lib-hash' "$f" || MISS="$MISS $(basename "$f")"
done
[ -z "$MISS" ] && pass || fail "callers without the source line:$MISS"

begin_test "every tier costs exactly ONE fork (no pipe to cut/sed)"
# lib-suppress calls sc_md5 on its dedup path, which runs on every Bash tool
# call. The first version piped md5sum through `cut` and openssl through `sed`,
# making those tiers 2 forks — measured as budget-cap 7.4 -> 10.6 ms median,
# with the baseline below the min of six samples. Trimming is bash parameter
# expansion now. A pipe inside a tier is the regression.
PIPED=$(sed -n '/^sc_md5()/,/^}/p' "$LIB" | grep -nE '^\s*out=\$\(.*\|' || true)
[ -z "$PIPED" ] && pass || fail "a tier pipes to another process: $PIPED"

begin_test "trimming uses parameter expansion, not a subprocess"
sed -n '/^sc_md5()/,/^}/p' "$LIB" | grep -q 'out="${out%%' && pass \
  || fail "md5sum output is no longer trimmed with \${out%% *}"

begin_test "callers fall back to a NAMED key, never an empty suffix"
# `.failed-commands-` with nothing after it is the collision this fix exists for.
BAD=""
for f in failure-tracker learn-from-prompts session-memory-write compaction-backup; do
  grep -q 'global' "$REPO_DIR/hooks/$f.sh" || BAD="$BAD $f"
done
[ -z "$BAD" ] && pass || fail "no empty-hash fallback in:$BAD"

report
