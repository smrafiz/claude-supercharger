#!/usr/bin/env bash
# readback mode: failure-tracker counts repo-declared gate failures (READBACK.md)
# and nudges at the 2nd. Gate strings are untrusted repo text: matched literally.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# RB_HOOK lets the regression proof point at an origin/master copy of the hook.
FT="${RB_HOOK:-$REPO_DIR/hooks/failure-tracker.sh}"
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
SCOPE="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE"

echo "=== Readback Arm Tests ==="

EXP2='{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"readback: the same gate command has failed 2 times this session. Stop patching: write readback-handoff now and continue in a fresh session."}}'
EXP3="${EXP2/failed 2 times/failed 3 times}"
EXPPTU="${EXP2/PostToolUseFailure/PostToolUse}"

# payload EVENT CMD SID AGENT KIND CWD  (KIND: fail | ok | failout | intr | clean)
payload() {
  python3 - "$@" <<'PY'
import json, sys
ev, cmd, sid, agent, kind, cwd = sys.argv[1:7]
d = {"hook_event_name": ev, "tool_name": "Bash", "tool_input": {"command": cmd}, "session_id": sid, "cwd": cwd}
if agent: d["agent_id"] = agent
if ev == "PostToolUseFailure":
    d["error"] = "Exit code 1\n1 failed"
else:
    r = {"interrupted": False, "stderr": "", "stdout": "3 passed"}
    if kind == "failout": r["stdout"] = "FAILED tests/a.py::t"
    if kind == "intr": r["interrupted"] = True
    d["tool_response"] = r
print(json.dumps(d))
PY
}
# run PROJECT EVENT CMD SID [AGENT] [KIND] -> stdout of the hook (10s alarm if perl exists)
run() {
  local p="$1" ev="$2" cmd="$3" sid="$4" agent="${5:-}" kind="${6:-fail}" pl
  pl=$(payload "$ev" "$cmd" "$sid" "$agent" "$kind" "$p")
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$pl" | CLAUDE_PROJECT_DIR="$p" perl -e 'alarm 10; exec @ARGV' bash "$FT" 2>/dev/null
  else
    printf '%s' "$pl" | CLAUDE_PROJECT_DIR="$p" bash "$FT" 2>/dev/null
  fi
}
mkproj() { # name content -> dir holding READBACK.md
  local d="$T/$1"; mkdir -p "$d"; printf '%s' "$2" > "$d/READBACK.md"; printf '%s' "$d"
}
TABLE_PY='| Item | Your value | Example |
|---|---|---|
| Targeted test | `pytest <file>` | `npm test -- <file>` |
| Full suite | make check (CI) | `make` |
'

begin_test "S-1: no READBACK.md => failure event empty stdout, ledger untouched"
P="$T/s1"; mkdir -p "$P"; rm -f "$SCOPE"/.readback-fails-* "$SCOPE"/.failed-commands-*
o1=$(run "$P" PostToolUseFailure "pytest x" s1); o2=$(run "$P" PostToolUseFailure "pytest x" s1)
[ -z "$o1$o2" ] && [ -z "$(ls -A "$SCOPE" | grep -E 'readback-fails|failed-commands')" ] && pass || fail "out=[$o1$o2]"

begin_test "S-2: gate fails x2 => fixed context on the 2nd only (N=2)"
P=$(mkproj s2 "$TABLE_PY")
o1=$(run "$P" PostToolUseFailure "pytest tests/a.py" s2); o2=$(run "$P" PostToolUseFailure "pytest tests/a.py" s2)
[ -z "$o1" ] && [ "$o2" = "$EXP2" ] && pass || fail "o1=[$o1] o2=[$o2]"

begin_test "S-2: 3rd failure re-emits with N=3"
o3=$(run "$P" PostToolUseFailure "pytest tests/a.py" s2)
[ "$o3" = "$EXP3" ] && pass || fail "o3=[$o3]"

begin_test "S-2b: PostToolUse output FAILED with exit 0 never counts"
P=$(mkproj s2b "$TABLE_PY"); rm -f "$SCOPE"/.readback-fails-s2b
o=""; for i in 1 2 3; do o="$o$(run "$P" PostToolUse "pytest tests/a.py" s2b "" failout)"; done
case "$o" in *readback*) fail "o=[$o]" ;; *) [ ! -s "$SCOPE/.readback-fails-s2b" ] && pass || fail "state written" ;; esac

begin_test "S-3: fail, success, fail => no emit"
P=$(mkproj s3 "$TABLE_PY")
o="$(run "$P" PostToolUseFailure "pytest a" s3)$(run "$P" PostToolUse "pytest a" s3 "" ok)$(run "$P" PostToolUseFailure "pytest a" s3)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "S-4: non-gate failures x3 => nothing from the readback branch"
P=$(mkproj s4 "$TABLE_PY"); rm -f "$SCOPE"/.readback-fails-s4
o="$(run "$P" PostToolUseFailure "ls x" s4)$(run "$P" PostToolUseFailure "ls x" s4)$(run "$P" PostToolUseFailure "ls x" s4)"
[ -z "$o" ] && [ ! -e "$SCOPE/.readback-fails-s4" ] && pass || fail "o=[$o]"

begin_test "S-17: generic ledger path unchanged with READBACK.md present (3rd marker failure nudges)"
P=$(mkproj s17 "$TABLE_PY")
mk() { python3 -c "import json,sys; print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash','tool_input':{'command':'make zz'},'tool_response':{'interrupted':False,'stderr':'make: command not found','stdout':''},'cwd':sys.argv[1],'session_id':'s17'}))" "$P"; }
for i in 1 2; do mk | CLAUDE_PROJECT_DIR="$P" bash "$FT" >/dev/null 2>&1; done
o=$(mk | CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null)
case "$o" in *'[LEARNING]'*'failed 2 times'*) pass ;; *) fail "o=[$o]" ;; esac

begin_test "S-5: project dir with a space works"
P=$(mkproj "s5 dir" "$TABLE_PY")
o1=$(run "$P" PostToolUseFailure "pytest q" s5); o2=$(run "$P" PostToolUseFailure "pytest q" s5)
[ -z "$o1" ] && [ "$o2" = "$EXP2" ] && pass || fail "o2=[$o2]"

begin_test "S-6: gate cells are never executed"
P1=$(mkproj s6a "| Targeted test | \`touch $T/pwned\` | x |
"); P2=$(mkproj s6b "| Targeted test | \$(touch $T/pwned2) | x |
")
run "$P1" PostToolUseFailure "touch $T/pwned" s6 >/dev/null; run "$P1" PostToolUseFailure "touch $T/pwned" s6 >/dev/null
run "$P2" PostToolUseFailure "ls" s6 >/dev/null; run "$P2" PostToolUseFailure "ls" s6 >/dev/null
[ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ] && pass || fail "a gate cell was executed"

begin_test "S-7: glob/bracket/backtick/backslash-0/NUL gates match literally only"
P=$(mkproj s7 '| Targeted test | `*` | x |
| Full suite | `[x` | x |
| New warnings | ` | x |
| Secret scan | `a\0b` | x |
')
printf '| Secret scan | `nul\000byte` | x |\n' >> "$P/READBACK.md"
o=""; for c in "ls x" "x" "ab" "a" "foo bar"; do o="$o$(run "$P" PostToolUseFailure "$c" s7)$(run "$P" PostToolUseFailure "$c" s7)"; done
l1=$(run "$P" PostToolUseFailure '*' s7); l2=$(run "$P" PostToolUseFailure '*' s7)
b1=$(run "$P" PostToolUseFailure 'a\0b' s7); b2=$(run "$P" PostToolUseFailure 'a\0b' s7)
[ -z "$o" ] && [ -z "$l1" ] && [ "$l2" = "$EXP2" ] && [ -z "$b1" ] && [ "$b2" = "$EXP2" ] && pass || fail "o=[$o] l2=[$l2] b2=[$b2]"

begin_test "S-8: hostile session_id writes only under scope/ (sanitised)"
P=$(mkproj s8 "$TABLE_PY"); rm -f "$SCOPE"/.readback-fails-x
run "$P" PostToolUseFailure "pytest z" '../../x' >/dev/null
[ -f "$SCOPE/.readback-fails-x" ] && [ ! -e "$T/x" ] && [ ! -e "$SCOPE/../../x" ] && pass || fail "state file location wrong"

begin_test "S-8b: empty session_id uses the fixed fallback name"
rm -f "$SCOPE"/.readback-fails-nosession
run "$P" PostToolUseFailure "pytest z" '' >/dev/null
[ -f "$SCOPE/.readback-fails-nosession" ] && pass || fail "no fallback state file"

begin_test "S-9: FIFO / directory / dev-zero symlink / 5MB line => no output, fast"
ok=1
P="$T/s9a"; mkdir -p "$P"; mkfifo "$P/READBACK.md"
P2="$T/s9b"; mkdir -p "$P2/READBACK.md"
P3="$T/s9c"; mkdir -p "$P3"; ln -s /dev/zero "$P3/READBACK.md"
P4="$T/s9d"; mkdir -p "$P4"; head -c 5000000 /dev/zero | tr '\0' 'a' > "$P4/READBACK.md"
S0=$SECONDS
for d in "$P" "$P2" "$P3" "$P4"; do o="$(run "$d" PostToolUseFailure "pytest x" s9)$(run "$d" PostToolUseFailure "pytest x" s9)"; [ -z "$o" ] || ok=0; done
[ "$ok" = 1 ] && [ $((SECONDS - S0)) -lt 8 ] && pass || fail "ok=$ok elapsed=$((SECONDS - S0))"

begin_test "S-10: a gate row beyond byte 65536 is ignored"
P="$T/s10"; mkdir -p "$P"; { head -c 70000 /dev/zero | tr '\0' 'a'; printf '\n| Targeted test | `pytest` | x |\n'; } > "$P/READBACK.md"
o="$(run "$P" PostToolUseFailure "pytest" s10)$(run "$P" PostToolUseFailure "pytest" s10)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "S-11: /sc off (disabled flag) => no output"
P=$(mkproj s11 "$TABLE_PY"); : > "$SCOPE/.supercharger-disabled"
o="$(run "$P" PostToolUseFailure "pytest k" s11)$(run "$P" PostToolUseFailure "pytest k" s11)"
rm -f "$SCOPE/.supercharger-disabled"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "S-12: agent_id counts separately from the main thread"
P=$(mkproj s12 "$TABLE_PY")
a=$(run "$P" PostToolUseFailure "pytest m" s12); b=$(run "$P" PostToolUseFailure "pytest m" s12 ag1); c=$(run "$P" PostToolUseFailure "pytest m" s12 ag1)
[ -z "$a" ] && [ -z "$b" ] && [ "$c" = "$EXP2" ] && pass || fail "a=[$a] b=[$b] c=[$c]"

begin_test "S-13: interrupted PostToolUse on a gate counts silently (no emit); a clean one resets"
P=$(mkproj s13 "$TABLE_PY")
a=$(run "$P" PostToolUse "pytest i" s13 "" intr); b=$(run "$P" PostToolUse "pytest i" s13 "" intr)
c=$(run "$P" PostToolUse "pytest j" s13 "" intr); d=$(run "$P" PostToolUse "pytest j" s13 "" clean); e=$(run "$P" PostToolUse "pytest j" s13 "" intr)
f=$(run "$P" PostToolUseFailure "pytest i" s13)
[ -z "$a$b" ] && [ -z "$c$d$e" ] && [ "$f" = "$EXP3" ] && pass || fail "a=[$a] b=[$b] c=[$c$d$e] f=[$f]"

begin_test "S-13b: interrupted PostToolUse (count 1) then PostToolUseFailure of the same gate => N=2"
P=$(mkproj s13b "$TABLE_PY")
a=$(run "$P" PostToolUse "pytest w" s13b "" intr); b=$(run "$P" PostToolUseFailure "pytest w" s13b)
[ -z "$a" ] && [ "$b" = "$EXP2" ] && pass || fail "a=[$a] b=[$b]"

begin_test "single JSON object (or empty) on stdout for gate failures in each event"
P=$(mkproj s13c "$TABLE_PY"); ok=1
for i in 1 2 3; do
  for ev in PostToolUseFailure PostToolUse; do
    o=$(run "$P" "$ev" "pytest v" s13c "" intr)
    [ -z "$o" ] || printf '%s' "$o" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null || ok=0
  done
done
[ "$ok" = 1 ] && pass || fail "stdout was not a single JSON object"

begin_test "gate cell cut leaving an unbalanced quote is skipped (shell -c with a quoted subshell)"
P=$(mkproj s19 '| Targeted test | `bash -c "(cd web && npm test)"` | x |
')
o="$(run "$P" PostToolUseFailure "bash -c 'make lint'" s19)$(run "$P" PostToolUseFailure "bash -c 'make lint'" s19)$(run "$P" PostToolUseFailure 'bash -c' s19)$(run "$P" PostToolUseFailure 'bash -c' s19)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "gate cell cut leaving balanced quotes is kept (--grep (unit))"
P=$(mkproj s19b '| Targeted test | `npm test -- --grep (unit)` | x |
')
o1=$(run "$P" PostToolUseFailure "npm test -- --grep x" s19b); o2=$(run "$P" PostToolUseFailure "npm test -- --grep x" s19b)
[ -z "$o1" ] && [ "$o2" = "$EXP2" ] && pass || fail "o2=[$o2]"

begin_test "a gate row straddling byte 65536 is dropped (no shorter gate)"
P="$T/s20"; mkdir -p "$P"
{ head -c $((65536 - 25)) /dev/zero | tr '\0' 'a'; printf '\n| Targeted test | pytest tests/unit | x |\n'; } > "$P/READBACK.md"
o="$(run "$P" PostToolUseFailure "pytest" s20)$(run "$P" PostToolUseFailure "pytest" s20)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "hand-edited state count '08' does not crash; junk resets to 1"
P=$(mkproj s21 "$TABLE_PY")
K=$(printf '%s\n%s' "" "pytest h" | cksum); K="${K%% *}"
printf '%s 08\n' "$K" > "$SCOPE/.readback-fails-s21"
o=$(payload PostToolUseFailure "pytest h" s21 "" fail "$P" | CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null); rc=$?
printf '%s junk\n' "$K" > "$SCOPE/.readback-fails-s21"
o2=$(run "$P" PostToolUseFailure "pytest h" s21)
printf '%s 99999999999999\n' "$K" > "$SCOPE/.readback-fails-s21"
o3=$(run "$P" PostToolUseFailure "pytest h" s21)
[ "$rc" = 0 ] && [ "$o" = "${EXP2/failed 2 times/failed 9 times}" ] && [ -z "$o2$o3" ] && pass || fail "rc=$rc o=[$o] o2=[$o2] o3=[$o3]"

begin_test "profile fast/minimal => readback path silent"
P=$(mkproj s22 "$TABLE_PY"); o=""
for prof in fast minimal; do
  pl=$(payload PostToolUseFailure "pytest pr" "s22$prof" "" fail "$P")
  o="$o$(printf '%s' "$pl" | SUPERCHARGER_PROFILE=$prof CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null)$(printf '%s' "$pl" | SUPERCHARGER_PROFILE=$prof CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null)"
done
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "hook listed in the disabled-hooks file => readback path silent"
P=$(mkproj s23 "$TABLE_PY"); printf 'failure-tracker\n' > "$SCOPE/.disabled-hooks"
o="$(run "$P" PostToolUseFailure "pytest dh" s23)$(run "$P" PostToolUseFailure "pytest dh" s23)"
rm -f "$SCOPE/.disabled-hooks"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "no READBACK.md: a failure event the generic path WOULD record is not recorded (early exit)"
P="$T/s24"; mkdir -p "$P"; rm -f "$SCOPE"/.failed-commands-*
pl=$(python3 -c "import json,sys; print(json.dumps({'hook_event_name':'PostToolUseFailure','tool_name':'Bash','tool_input':{'command':'make zz'},'error':'Exit code 1','tool_response':{'interrupted':True,'stderr':'make: command not found','stdout':''},'cwd':sys.argv[1],'session_id':'s24'}))" "$P")
o="$(printf '%s' "$pl" | CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null)$(printf '%s' "$pl" | CLAUDE_PROJECT_DIR="$P" bash "$FT" 2>/dev/null)"
[ -z "$o" ] && [ -z "$(ls -A "$SCOPE" | grep failed-commands)" ] && pass || fail "o=[$o]"

begin_test "S-14: empty value cell never falls back to the Example column"
P=$(mkproj s14 '| Targeted test | | pytest |
| Full suite | | `make` |
')
o="$(run "$P" PostToolUseFailure "pytest" s14)$(run "$P" PostToolUseFailure "pytest" s14)$(run "$P" PostToolUseFailure "make" s14)$(run "$P" PostToolUseFailure "make" s14)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "S-15: CRLF READBACK.md parses"
P="$T/s15"; mkdir -p "$P"; printf '| Item | Your value | Example |\r\n|---|---|---|\r\n| Targeted test | `pytest <file>` | x |\r\n' > "$P/READBACK.md"
o1=$(run "$P" PostToolUseFailure "pytest f" s15); o2=$(run "$P" PostToolUseFailure "pytest f" s15)
[ -z "$o1" ] && [ "$o2" = "$EXP2" ] && pass || fail "o2=[$o2]"

begin_test "S-16: other rows (T1 reviewer:, near-miss labels) never become gates"
P=$(mkproj s16 '| T1 reviewer: | `pytest` | x |
| Targeted testing | `pytest` | x |
| Notes | `pytest` | x |
')
o="$(run "$P" PostToolUseFailure "pytest" s16)$(run "$P" PostToolUseFailure "pytest" s16)"
[ -z "$o" ] && pass || fail "o=[$o]"

begin_test "gate match forms: '&&' and ';' chains count, 'xpytest' does not"
P=$(mkproj s18 "$TABLE_PY")
a="$(run "$P" PostToolUseFailure "cd sub && pytest x" s18)"; b="$(run "$P" PostToolUseFailure "cd sub && pytest x" s18)"
c="$(run "$P" PostToolUseFailure "xpytest" s18)$(run "$P" PostToolUseFailure "xpytest" s18)"
d="$(run "$P" PostToolUseFailure "true; make check" s18)"; e="$(run "$P" PostToolUseFailure "true; make check" s18)"
[ -z "$a" ] && [ "$b" = "$EXP2" ] && [ -z "$c" ] && [ -z "$d" ] && [ "$e" = "$EXP2" ] && pass || fail "a=[$a] b=[$b] c=[$c] d=[$d] e=[$e]"

begin_test "syntax: bash -n lib-readback.sh and failure-tracker.sh"
bash -n "$REPO_DIR/hooks/lib-readback.sh" && bash -n "$REPO_DIR/hooks/failure-tracker.sh" && pass || fail "syntax"

report
