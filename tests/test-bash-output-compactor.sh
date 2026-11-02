#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/bash-output-compactor.sh"

echo "=== bash-output-compactor Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "bash-output-compactor: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "bash-output-compactor: short output passes through unchanged"
INPUT='{"tool_name":"Bash","tool_input":{"command":"git log --oneline -3"},"tool_response":{"stdout":"abc def\nghi jkl\nmno pqr"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no compaction for 3-line output, got: $OUT"

begin_test "bash-output-compactor: long git log compacted with head + tail"
LONG_LOG=""
for i in $(seq 1 60); do LONG_LOG="$LONG_LOG abc${i} commit ${i}\n"; done
LONG_LOG=$(printf '%b' "$LONG_LOG")
LOG_JSON=$(printf '%s' "$LONG_LOG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git log --all"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$LOG_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'updatedToolOutput' && echo "$OUT" | grep -q 'commits omitted' && pass || fail "expected git-log compaction, got: $OUT"

begin_test "bash-output-compactor: long pytest output compacted to summary"
LONG_TEST=""
for i in $(seq 1 60); do LONG_TEST="${LONG_TEST}tests/test_module.py::test_case_${i} ok\n"; done
LONG_TEST="${LONG_TEST}============================== 60 passed in 2.34s ==============================\n"
LONG_TEST=$(printf '%b' "$LONG_TEST")
TEST_JSON=$(printf '%s' "$LONG_TEST" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$TEST_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Test summary' && echo "$OUT" | grep -q '60 passed' && pass || fail "expected test summary, got: $OUT"

begin_test "bash-output-compactor: failing test keeps failure excerpt"
FAIL_TEST="test_one PASSED\ntest_two FAILED\nAssertionError: expected 1 == 2\n"
for i in $(seq 1 50); do FAIL_TEST="$FAIL_TEST test_$i passed\n"; done
FAIL_TEST="$FAIL_TEST 1 failed, 50 passed in 1.5s"
FAIL_TEST=$(printf '%b' "$FAIL_TEST")
TEST_JSON=$(printf '%s' "$FAIL_TEST" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$TEST_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Failure excerpt' && pass || fail "expected failure excerpt, got: $OUT"

begin_test "bash-output-compactor: long npm install compacted"
LONG_INSTALL=""
for i in $(seq 1 60); do LONG_INSTALL="$LONG_INSTALL added pkg-$i\n"; done
LONG_INSTALL="$LONG_INSTALL added 60 packages in 3.4s"
LONG_INSTALL=$(printf '%b' "$LONG_INSTALL")
INSTALL_JSON=$(printf '%s' "$LONG_INSTALL" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$INSTALL_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Install summary' && pass || fail "expected install summary, got: $OUT"

begin_test "bash-output-compactor: skips non-Bash tools"
INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"},"tool_response":{"stdout":"long output"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on Read, got: $OUT"

begin_test "bash-output-compactor: skips unknown command patterns"
LONG=""
for i in $(seq 1 100); do LONG="${LONG}line $i\n"; done
LONG=$(printf '%b' "$LONG")
JSON=$(printf '%s' "$LONG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls -la /usr/bin"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on ls (not in pattern list), got: $OUT"

begin_test "bash-output-compactor: SUPERCHARGER_BASH_COMPACTOR=0 disables hook"
LONG_LOG=""
for i in $(seq 1 60); do LONG_LOG="$LONG_LOG abc${i} commit ${i}\n"; done
LONG_LOG=$(printf '%b' "$LONG_LOG")
LOG_JSON=$(printf '%s' "$LONG_LOG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git log --all"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$LOG_JSON")
OUT=$(SUPERCHARGER_BASH_COMPACTOR=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"

# The summary is all the model sees, so the full output is saved and named: a
# commit in the omitted middle must be readable from the saved file.
begin_test "bash-output-compactor: full output is saved, 0600, and its path is in the summary"
ST=$(mktemp -d)
LONG_LOG=""
for i in $(seq 1 60); do LONG_LOG="$LONG_LOG abc${i} commit ${i}\n"; done
LOG_JSON=$(printf '%b' "$LONG_LOG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git log --all"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$LOG_JSON")
OUT=$(echo "$INPUT" | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null)
SAVED=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedToolOutput' | sed -n 's/.*saved to \([^;]*\);.*/\1/p')
MODE=$(stat -c '%a' "$SAVED" 2>/dev/null || stat -f '%Lp' "$SAVED" 2>/dev/null)  # GNU first: Linux 'stat -f' reports the filesystem and succeeds
# Git Bash on Windows has no POSIX modes: stat reports 644 for every file, so the
# owner-only check is meaningless there (master CI 432c049). The file must still exist.
case "${OSTYPE:-}" in msys*|cygwin*) [ -f "$SAVED" ] && MODE=600 ;; esac
{ [ -n "$SAVED" ] && grep -q 'abc30 commit 30' "$SAVED" && [ "$MODE" = 600 ]; } \
  && pass || fail "saved='$SAVED' mode='$MODE' out=$OUT"
rm -rf "$ST"

# 4.4.2: the excerpt is one 30-line window from the FIRST failure; later failures
# and pytest's short summary fell outside it.
_cview() { jq -r '.hookSpecificOutput.updatedToolOutput // empty'; }
PYT=$(python3 - <<'PY'
o = "============ test session starts ============\n"
o += "tests/test_a.py::test_one FAILED\n"
o += "    def test_one():\n>       assert get() == 5\nE       AssertionError: assert 4 == 5\n"
o += "".join("tests/test_m.py::test_%d PASSED\n" % i for i in range(80))
o += "    def test_late():\n>       load()\nE       KeyError: 'cfg'\n"
o += "========= short test summary info =========\n"
o += "FAILED tests/test_a.py::test_one - AssertionError: assert 4 == 5\n"
o += "FAILED tests/test_z.py::test_late - KeyError: 'cfg'\n"
o += "ERROR tests/test_z.py::test_setup - OSError: no db\n"
o += "======= 2 failed, 80 passed, 1 error in 3.2s =======\n"
print(o)
PY
)
V=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"pytest -q"},"tool_response":{"stdout":sys.stdin.read()},"cwd":"/tmp"}))' <<<"$PYT" \
  | SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" 2>/dev/null | _cview)

begin_test "bash-output-compactor: every failing test is listed, not just the first"
_lost=""
for want in 'FAILED tests/test_a.py::test_one' 'FAILED tests/test_z.py::test_late' 'ERROR tests/test_z.py::test_setup'; do
  printf '%s' "$V" | grep -qF "$want" || _lost="$_lost '$want'"
done
[ -z "$_lost" ] && pass || fail "lost:$_lost — got: $(printf '%s' "$V" | head -12)"

begin_test "bash-output-compactor: the totals come from the summary line, not a test name"
printf '%s' "$V" | grep -qF '[Test summary] 80 passed, 2 failed' && pass || fail "got: $(printf '%s' "$V" | head -1)"

begin_test "bash-output-compactor: omitted marker counts the lines and names the hidden exception types"
printf '%s' "$V" | grep -qE '^\[[0-9]+ lines omitted' && pass || fail "no omitted marker: $(printf '%s' "$V" | tail -4)"

begin_test "bash-output-compactor: install output says how many warning lines the cap dropped"
INST=$(python3 -c "print('\n'.join(['npm warn deprecated pkg%d@1.0.0' % i for i in range(60)] + ['added 900 packages in 12s']))")
V=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":{"stdout":sys.stdin.read()},"cwd":"/tmp"}))' <<<"$INST" \
  | SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" 2>/dev/null | _cview)
printf '%s' "$V" | grep -qF '+45 more warning/error lines omitted' && printf '%s' "$V" | grep -qF 'Warnings/errors (60' \
  && pass || fail "got: $(printf '%s' "$V" | head -3)"

# 4.4.2 generic pass (ideas from headroom lossless_compaction / dense_line_elider).
_gen() { # command, output -> the rewritten view (empty when untouched)
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"tool_response":{"stdout":sys.stdin.read()},"cwd":"/tmp"}))' "$1" \
    | SUPERCHARGER_STATE="$(mktemp -d)" ${3:+env $3} bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.updatedToolOutput // empty'
}
REP=$(python3 -c "print('starting build'); print('\n'.join(['waiting for lock on /var/cache/apt'] * 400)); print('build done')")

begin_test "generic: a long run of identical lines collapses to one line and a count"
V=$(_gen "./build.sh" <<<"$REP")
printf '%s' "$V" | grep -qF 'previous line repeated 399 more times' && printf '%s' "$V" | grep -qF 'build done' \
  && printf '%s' "$V" | grep -qF 'starting build' && pass || fail "got: $(printf '%s' "$V" | head -4)"

begin_test "generic: dense minified lines keep head and tail"
DENSE=$(python3 -c "import random; random.seed(1); print('<script>'); [print(''.join(random.choice('abcdef0123456789{}();=') for _ in range(4000))) for _ in range(5)]; print('</script>')")
V=$(_gen "curl -s https://example.com/app.js" <<<"$DENSE")
printf '%s' "$V" | grep -q 'chars elided' && printf '%s' "$V" | grep -qF '</script>' && pass || fail "got: ${V:0:120}"

begin_test "generic: a large output of distinct lines is left alone"
DIST=$(python3 -c "print('\n'.join('row %d: value %d status ok' % (i, i*7) for i in range(600)))")
V=$(_gen "./report.sh" <<<"$DIST")
[ -z "$V" ] && pass || fail "rewrote distinct lines: ${V:0:80}"

begin_test "generic: SUPERCHARGER_COMPACT_GENERIC=0 turns it off"
V=$(_gen "./build.sh" "" SUPERCHARGER_COMPACT_GENERIC=0 <<<"$REP")
[ -z "$V" ] && pass || fail "still rewrote: ${V:0:80}"

begin_test "install: warnings differing only in versions are grouped with a count"
# Only the part after the first ':' is normalised, so distinct packages
# (glob@7 vs rimraf@3) stay distinct while one message repeated per version folds.
INST=$(python3 -c "print('\n'.join(['npm warn ERESOLVE overriding peer dependency: react@18.%d.0' % i for i in range(30)] + ['npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported'] + ['resolving %d' % i for i in range(30)] + ['added 900 packages in 12s']))")
V=$(_gen "npm install" <<<"$INST")
printf '%s' "$V" | grep -qF 'x30 similar]' && printf '%s' "$V" | grep -qF 'rimraf@3.0.2' && pass || fail "got: $(printf '%s' "$V" | head -5)"

# 4.4.3: with `pytest -v` the first FAILED line is a one-line progress entry, so
# the excerpt window filled with PASSED neighbours and never showed the assertion.
VERB=$(python3 - <<'PY'
o = "".join("tests/t.py::test_%d PASSED\n" % i for i in range(40))
o += "tests/t.py::test_login FAILED\n" + "".join("tests/u.py::test_%d PASSED\n" % i for i in range(40))
o += "=================================== FAILURES ===================================\n"
o += ">       assert login().status == 200\nE       AssertionError: assert 401 == 200\n"
o += "=========================== short test summary info ============================\n"
o += "FAILED tests/t.py::test_login - AssertionError: assert 401 == 200\n"
o += "========== 1 failed, 80 passed in 2.0s ==========\n"
print(o)
PY
)
begin_test "bash-output-compactor: a -v run's excerpt shows the assertion, not PASSED neighbours"
V=$(_gen "pytest -v" <<<"$VERB")
printf '%s' "$V" | grep -qF 'E       AssertionError: assert 401 == 200' && [ "$(printf '%s' "$V" | grep -c 'PASSED')" -lt 5 ] \
  && pass || fail "got: $(printf '%s' "$V" | head -8)"

report
