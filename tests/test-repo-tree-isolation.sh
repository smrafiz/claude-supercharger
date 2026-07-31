#!/usr/bin/env bash
# Repo-tree isolation (v2.26.3)
#
# 2.24.8 isolated HOME per test file so the suite stopped writing to the real
# ~/.claude. It left the OTHER piece of shared mutable state untouched: the repo
# checkout itself. tests/test-hook-new.sh scaffolded fixtures into $REPO_DIR/hooks/
# and deleted each one straight after, while install.sh — running concurrently in
# test-install.sh — does `cp "$source_dir/hooks/"*.sh`. Expand the glob while a
# fixture exists, copy it after cleanup removed it, and cp fails: the hook deploy
# aborts and settings.json is never written. 3 failures in 11 full runs.
#
# Nothing detected it for six releases, because the residue was always cleaned up.
# A post-hoc `git status` check would see a pristine tree and report success — the
# damage happens DURING the run, in the window between create and delete. So this
# is a static check on the test sources, in the shape of test-suite-count-invariance.
#
# The rule: a $REPO_DIR-rooted path may be READ, never written. Copying a config
# fixture out of the repo into $HOME is fine and must not be flagged — several tests
# do exactly that. What is banned is the repo tree as a write TARGET.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Repo Tree Isolation Tests ==="

SCAN=$(cat <<'PY'
import re, sys, glob, os

# Verbs where EVERY path argument is a target.
MUTATORS = ('rm', 'touch', 'mkdir', 'chmod', 'chown', 'ln', 'tee')
# Verbs where only the LAST argument is a target; earlier ones are sources, and
# reading a config fixture out of the repo is legitimate.
LAST_ARG_ONLY = ('cp', 'mv')

# Quote chars as \x27/\x22 — an unbalanced literal quote inside this heredoc breaks
# bash 3.2's $( ) parser, which matches quotes through a quoted heredoc body.
HEREDOC = re.compile(r'<<-?\s*[\x27\x22]?([A-Za-z_][A-Za-z0-9_]*)[\x27\x22]?')
Q = r'[\x27\x22]?'


def repo_token(varnames):
    # "$REPO_DIR/... , "${HOOKS_DIR}/... , $TOOL — a bare repo-rooted var counts too,
    # since `rm -f $TOOL` is still a write into the tree.
    alt = '|'.join(sorted(varnames, key=len, reverse=True))
    return re.compile(Q + r'\$\{?(?:' + alt + r')\}?(?:/|\b)')


def scan_file(path):
    problems = []
    lines = open(path, errors='replace').read().split('\n')
    # Seeded with REPO_DIR and grown transitively: TOOL="$REPO_DIR/tools/x.sh" makes
    # TOOL repo-rooted, and HOOKS_DIR="$REPO_DIR/hooks" is how the real bug was spelt.
    varnames = {'REPO_DIR'}
    heredoc_end = None
    for i, raw in enumerate(lines, 1):
        s = raw.strip()
        if heredoc_end is not None:
            if s == heredoc_end:
                heredoc_end = None
            continue
        if not s or s.startswith('#'):
            continue
        m = HEREDOC.search(raw)
        if m:
            heredoc_end = m.group(1)
            continue

        tok = repo_token(varnames)

        # Grow the alias set before testing the line, so an assignment that both
        # defines and uses a repo path is judged with the new name in hand.
        am = re.match(r'^(?:local\s+|export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', s)
        if am and tok.search(am.group(2)):
            varnames.add(am.group(1))
            tok = repo_token(varnames)
            continue

        # Redirection: `> $REPO_DIR/x`. The lookbehind skips 2>&1 and fd dups.
        if re.search(r'(?<![0-9&<>])>>?\s*' + tok.pattern, s):
            problems.append((path, i, s))
            continue

        # The verb must be in COMMAND position. Splitting on ;/|/&&/|| gets most of
        # the way; what remains are the shell keywords and the function-definition
        # prefix that legitimately sit in front of it — the real defect was spelt
        # `cleanup_hook() { rm -f "$HOOKS_DIR/$1.sh"; }` and its guard as
        # `[ -f x ] && mv x y`. Position matters, because tests pass attack strings
        # as ARGUMENTS: `run_hook "$SAFETY_HOOK" "rm -r -f /"` contains rm and a
        # repo path and is a read, and matching the verb anywhere flagged it.
        for seg in re.split(r'[;|]|&&|\|\|', s):
            words = seg.split()
            while words and (words[0] in ('{', '!', 'then', 'do', 'else', 'elif')
                             or re.match(r'^[A-Za-z_][A-Za-z0-9_]*\(\)\{?$', words[0])):
                words = words[1:]
            if not words:
                continue
            cmd = os.path.basename(words[0])
            args = [w for w in words[1:] if not w.startswith('-')]
            if not args:
                continue
            if cmd in MUTATORS:
                targets = args
            elif cmd in LAST_ARG_ONLY:
                targets = args[-1:]
            elif cmd == 'sed' and '-i' in words:
                targets = args[-1:]
            else:
                continue
            if any(tok.search(t) for t in targets):
                problems.append((path, i, s))
                break
    return problems


out = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], 'tests', 'test-*.sh'))):
    for p, i, s in scan_file(path):
        out.append('%s:%d' % (os.path.basename(p), i))
print('\n'.join(out))
PY
)

begin_test "no test writes into the repo tree (shared state the suite runs in parallel over)"
PROBLEMS=$(python3 -c "$SCAN" "$REPO_DIR" 2>&1)
if [ -z "$PROBLEMS" ]; then
  pass
else
  fail "repo-tree writes (race the parallel suite): $(printf '%s' "$PROBLEMS" | tr '\n' ' ')"
fi

# Guard the guard. Each shape below is checked against the real defect or the real
# legitimate usage it must not confuse — a checker validated only by watching it
# pass is the thing this project keeps finding bugs in.
TD=$(mktemp -d); mkdir -p "$TD/tests"
trap 'rm -rf "$TD"' EXIT

begin_test "the checker flags the exact shape that raced test-install (rm via an alias var)"
cat > "$TD/tests/test-fixture-alias.sh" <<'EOS'
HOOKS_DIR="$REPO_DIR/hooks"
cleanup_hook() { rm -f "$HOOKS_DIR/${1}.sh"; }
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
printf '%s' "$OUT" | grep -q 'test-fixture-alias.sh' && pass || fail "missed the aliased rm: $OUT"
rm -f "$TD/tests/test-fixture-alias.sh"

begin_test "the checker flags a redirect into the repo tree"
cat > "$TD/tests/test-fixture-redir.sh" <<'EOS'
echo "fixture" > "$REPO_DIR/hooks/scratch.sh"
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
printf '%s' "$OUT" | grep -q 'test-fixture-redir.sh' && pass || fail "missed the redirect: $OUT"
rm -f "$TD/tests/test-fixture-redir.sh"

begin_test "the checker flags a copy INTO the repo tree"
cat > "$TD/tests/test-fixture-cpin.sh" <<'EOS'
cp "$HOME/.claude/settings.json" "$REPO_DIR/hooks/seed.json"
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
printf '%s' "$OUT" | grep -q 'test-fixture-cpin.sh' && pass || fail "missed the inbound cp: $OUT"
rm -f "$TD/tests/test-fixture-cpin.sh"

begin_test "the checker allows copying a fixture OUT of the repo (test-economy-switch's shape)"
cat > "$TD/tests/test-fixture-cpout.sh" <<'EOS'
cp "$REPO_DIR/configs/economy/lean.md" "$HOME/.claude/rules/economy.md"
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "false positive on a read-out cp: $OUT"
rm -f "$TD/tests/test-fixture-cpout.sh"

begin_test "the checker allows running a repo script and discarding its output"
cat > "$TD/tests/test-fixture-run.sh" <<'EOS'
TOOL="$REPO_DIR/tools/hook-new.sh"
bash "$TOOL" my-hook >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --mode full > "$HOME/.out" 2>&1
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "false positive on invoking a repo script: $OUT"
rm -f "$TD/tests/test-fixture-run.sh"

begin_test "the checker allows an attack string passed as an argument (test-hooks' shape)"
cat > "$TD/tests/test-fixture-arg.sh" <<'EOS'
HOOK="$REPO_DIR/hooks/destructive-prompt-scanner.sh"
run_hook "$REPO_DIR/hooks/safety.sh" "rm -r -f /"
OUT=$(printf '%s' '{"prompt":"please rm -rf /var/www now"}' | bash "$HOOK" 2>&1)
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "flagged a verb sitting in an argument, not command position: $OUT"
rm -f "$TD/tests/test-fixture-arg.sh"

begin_test "the checker ignores repo paths inside heredoc fixture bodies"
cat > "$TD/tests/test-fixture-heredoc.sh" <<'EOS'
cat > "$HOME/sample.sh" <<'INNER'
rm -f "$REPO_DIR/hooks/not-real.sh"
INNER
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "flagged a heredoc body (it is data, not code): $OUT"

report
