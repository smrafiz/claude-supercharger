#!/usr/bin/env bash
# Per-project scope keys survive Windows-style paths (v2.26.83)
#
# Found by running the suite on windows-latest for the first time (Phase 2 item 4
# of the Windows plan, which had never landed): `.allow-patterns-C` — a filename
# truncated at the drive colon.
#
# Git Bash's own $PWD is POSIX (/c/Users/...), but the hook PAYLOAD's cwd on
# Windows is a native path (C:\Users\...) because Claude Code is a Windows binary.
# The key function folded only '/', so a Windows cwd passed through carrying ':'
# and '\' — both ILLEGAL in an NTFS filename. The scope file then failed to write
# or truncated at the colon, collapsing every project on C: onto ONE key. That
# makes per-project allowPatterns and customPatterns leak between projects: a
# guard deliberately widened in one repo is widened in all of them. Audit HIGH #13
# was closed for POSIX and was still open here.
#
# Two properties: Windows paths produce a legal, DISTINCT key; and POSIX keys are
# byte-identical to before, so no installed scope file is orphaned.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=hooks/lib-paths.sh
. "$REPO_DIR/hooks/lib-paths.sh"

bkey() { sc_project_key "$1"; printf '%s' "$SC_PROJECT_KEY"; }
pkey() { PD="$1" python3 -c "
import os,re,sys
sys.path.insert(0,'.')
src=open(sys.argv[1]).read()
m=re.search(r'def _project_key.*?return k or .root.', src, re.S)
# The extracted function reads os.environ (for a bash-supplied key), so the exec
# namespace has to carry os. Without it the call raised NameError, python printed
# nothing, and the test reported an empty key as a channel DISAGREEMENT — a
# harness gap wearing the costume of the bug it was written to catch.
ns={'os': os}
body=m.group(0)
exec(body, ns)
# Unset so this exercises the fallback derivation, which is the half that has to
# stay byte-identical to sc_project_key. The supplied-key path is asserted below.
os.environ.pop('SC_PROJECT_KEY', None)
print(ns['_project_key'](os.environ['PD']))
" "$REPO_DIR/hooks/project-config.sh"; }

echo "=== Project-Key Windows Tests ==="

# --- Windows-style payload cwds ---
begin_test "a Windows drive path yields a filename-legal key"
K=$(bkey 'C:\Users\me\project')
case "$K" in
  *:*|*\\*) fail "key still contains an NTFS-illegal character: $K" ;;
  '')       fail "key came out empty" ;;
  *)        pass ;;
esac

begin_test "two projects on the same drive get DIFFERENT keys"
A=$(bkey 'C:\Users\me\alpha'); B=$(bkey 'C:\Users\me\beta')
[ "$A" != "$B" ] && pass || fail "both projects collapsed onto one key ($A) — configs leak between them"

begin_test "different drives are distinguished"
A=$(bkey 'C:\work\proj'); B=$(bkey 'D:\work\proj')
[ "$A" != "$B" ] && pass || fail "drive letter lost: $A"

begin_test "a mixed-separator path is folded"
K=$(bkey 'C:/Users/me\project')
case "$K" in *:*|*\\*) fail "mixed separators left illegal chars: $K" ;; *) pass ;; esac

begin_test "the Git Bash POSIX form still works"
K=$(bkey '/c/Users/me/project')
[ "$K" = "c-Users-me-project" ] && pass || fail "unexpected key: $K"

# --- POSIX behaviour must be byte-identical (no orphaned scope files) ---
begin_test "a plain POSIX path is unchanged by the fix"
[ "$(bkey '/Users/me/repo')" = "Users-me-repo" ] && pass || fail "POSIX key changed: $(bkey '/Users/me/repo')"

begin_test "root still maps to 'root'"
[ "$(bkey '/')" = "root" ] && pass || fail "root key changed: $(bkey '/')"

begin_test "the >100 char cap still applies"
LONG="/$(printf 'a%.0s' $(seq 1 200))"
LK=$(bkey "$LONG")
[ "${#LK}" -le 100 ] && pass || fail "cap lost — key is ${#LK} chars"

begin_test "the cap still applies to a long WINDOWS path"
WLONG="C:\\$(printf 'b%.0s' $(seq 1 200))"
WK=$(bkey "$WLONG")
[ "${#WK}" -le 100 ] && pass || fail "cap lost on the Windows form — key is ${#WK} chars"

# --- the two implementations must agree ---
begin_test "bash and python key functions agree on a Windows path"
B=$(bkey 'C:\Users\me\project'); P=$(pkey 'C:\Users\me\project')
[ "$B" = "$P" ] && pass || fail "channels disagree — bash='$B' python='$P'"

begin_test "bash and python agree on a POSIX path"
B=$(bkey '/Users/me/repo'); P=$(pkey '/Users/me/repo')
[ "$B" = "$P" ] && pass || fail "channels disagree — bash='$B' python='$P'"

begin_test "bash and python agree on root"
B=$(bkey '/'); P=$(pkey '/')
[ "$B" = "$P" ] && pass || fail "channels disagree — bash='$B' python='$P'"

# --- the fix: hand python the KEY, not just the path -------------------------
# Agreeing above only proves the two copies of the algorithm match. It cannot
# catch the failure that actually happened on Windows, where both copies were
# already identical and the INPUTS differed: PROJECT_DIR crosses as an env var,
# MSYS respells a single-path env var in transit, and python keyed
# 'C:-Program Files-Git-Users-me-proj' for the project bash keyed
# 'Users-me-proj'. Writer and readers then used different scope files and every
# per-project setting silently did nothing.
#
# A key has no separators left, so it crosses unchanged. These pin that python
# HONOURS it rather than re-deriving.
pkey_supplied() { # path, supplied-key -> the key python actually uses
  PD="$1" SC_PROJECT_KEY="$2" python3 -c "
import os,re,sys
src=open(sys.argv[1]).read()
m=re.search(r'def _project_key.*?return k or .root.', src, re.S)
ns={'os': os}
exec(m.group(0), ns)
print(ns['_project_key'](os.environ['PD']))
" "$REPO_DIR/hooks/project-config.sh"
}

begin_test "python uses the key bash supplies, not its own re-derivation"
# The respelled path is what MSYS would hand it; the supplied key is what bash
# saw. Honouring the latter is the whole fix.
GOT=$(pkey_supplied 'C:\Program Files\Git\Users\me\proj' 'Users-me-proj')
[ "$GOT" = "Users-me-proj" ] && pass || fail "python re-derived instead of using the supplied key: '$GOT'"

begin_test "an empty supplied key falls back to deriving one"
# Non-hook callers do not set it, and an empty value must not yield an empty key
# — that would collapse every project onto one shared scope file.
GOT=$(pkey_supplied '/Users/me/repo' '')
[ "$GOT" = "$(bkey '/Users/me/repo')" ] && pass || fail "empty supplied key did not fall back: '$GOT'"

report
