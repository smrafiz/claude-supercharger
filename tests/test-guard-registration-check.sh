#!/usr/bin/env bash
# Suite for hooks/guard-registration-check.sh (v2.29.22)
#
# An install that silently stops registering is indistinguishable from a working
# one — and project-config announces "Guardrails are on" either way. Measured
# before this hook existed: with an empty hooks key, every other SessionStart
# hook stayed silent while that claim still went out. This asserts the check
# closes that, and — more importantly — that it does NOT cry wolf, because a
# false "you are unprotected" warning is what trains people to disable it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/guard-registration-check.sh"
# Assembled so this file never contains the literal tag it searches for, which
# would otherwise make the repo's own settings match by accident.
TAG='#''supercharger'

_mkhome() {  # $1 = settings body, or "" for no file; $2 = optional stamp value
  local h; h=$(mktemp -d); mkdir -p "$h/.claude" "$h/.claude/supercharger"
  [ -n "$1" ] && printf '%s\n' "$1" > "$h/.claude/settings.json"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$h/.claude/supercharger/.registration-count"
  printf '%s' "$h"
}
# N registrations, each carrying the tag, as one settings body.
_settings_with() {  # $1 = how many
  local i out=""
  for ((i = 0; i < $1; i++)); do
    out="$out{\"hooks\":[{\"command\":\"h$i $TAG\"}]},"
  done
  printf '{"hooks":{"PreToolUse":[%s]}}' "${out%,}"
}
_warns() {  # $1 = home, $2 = optional CLAUDE_PLUGIN_ROOT -> "warns"/"silent"
  local out
  if [ -n "${2:-}" ]; then
    out=$(printf '{}' | HOME="$1" CLAUDE_PLUGIN_ROOT="$2" bash "$HOOK" 2>/dev/null)
  else
    out=$(printf '{}' | HOME="$1" bash "$HOOK" 2>/dev/null)
  fi
  [ -z "$out" ] && echo "silent" || echo "warns"
}

begin_test "guard-reg: warns when the hooks key is empty"
H=$(_mkhome '{"hooks":{}}')
[ "$(_warns "$H")" = "warns" ] && pass || fail "did not warn on an empty hooks key"
rm -rf "$H"

begin_test "guard-reg: warns when only foreign hooks are registered"
# Someone else's hooks present is not our hooks present.
H=$(_mkhome '{"hooks":{"PreToolUse":[{"hooks":[{"command":"other-tool"}]}]}}')
[ "$(_warns "$H")" = "warns" ] && pass || fail "did not warn when only foreign hooks exist"
rm -rf "$H"

begin_test "guard-reg: silent when our hooks ARE registered"
H=$(_mkhome "{\"hooks\":{\"PreToolUse\":[{\"hooks\":[{\"command\":\"x $TAG\"}]}]}}")
[ "$(_warns "$H")" = "silent" ] && pass || fail "false positive on a healthy install"
rm -rf "$H"

begin_test "guard-reg: silent under a plugin runtime, whatever settings.json says"
# THE false-positive that matters: a plugin install registers from the plugin's
# own hooks.json and has no user settings.json entry. Warning there would hit
# exactly the users who are fully protected — the plugin/installer path
# divergence that has caused silent no-ops in this repo before.
H=$(_mkhome '{"hooks":{}}')
[ "$(_warns "$H" "/fake/plugin/root")" = "silent" ] && pass || fail "cried wolf under a plugin runtime"
rm -rf "$H"

begin_test "guard-reg: fails OPEN when settings.json is unreadable"
# An unreadable file is not evidence of a missing install.
H=$(_mkhome "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "warned without evidence"
rm -rf "$H"

begin_test "guard-reg: kill switch disables it"
H=$(_mkhome '{"hooks":{}}')
OUT=$(printf '{}' | HOME="$H" SUPERCHARGER_GUARD_REG_CHECK=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch ignored"
rm -rf "$H"

begin_test "guard-reg: the warning is parseable systemMessage JSON"
# stderr from a hook lands in the debug log unhandled; stdout JSON is parsed and
# shown. A warning nobody sees is the very failure this hook reports.
H=$(_mkhome '{"hooks":{}}')
printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'systemMessage' in d, d
assert 'NOT PROTECTING' in d['systemMessage']
" 2>/dev/null && pass || fail "output is not valid systemMessage JSON"
rm -rf "$H"

begin_test "guard-reg: registered on SessionStart in the generated artifact"
python3 - "$REPO_DIR" <<'PY' && pass || fail "not registered in hooks.json"
import json,sys,pathlib
d=json.loads((pathlib.Path(sys.argv[1])/"hooks/hooks.json").read_text())["hooks"]
ok=any('guard-registration-check' in h.get('command','')
       for g in d.get('SessionStart',[]) for h in g.get('hooks',[]))
sys.exit(0 if ok else 1)
PY

# --- PARTIAL loss (v4.0.1) ---------------------------------------------------
# The check fired only at exactly zero. Measured on 2026-08-30 against the live
# install: 1-of-154 registered was silent, and so was the real shape left behind
# by a /sc off + /sc on, where 59 of 154 came back as "matcher": null and the
# surviving 95 still carried the tag. Presence is a proxy; the defect is partial.

begin_test "guard-reg: warns when most registrations are GONE but some remain"
H=$(_mkhome "$(_settings_with 1)" 154)
[ "$(_warns "$H")" = "warns" ] && pass || fail "1 of 154 registrations did not warn"
rm -rf "$H"

begin_test "guard-reg: silent when the count matches the stamp"
H=$(_mkhome "$(_settings_with 154)" 154)
[ "$(_warns "$H")" = "silent" ] && pass || fail "false positive on a complete install"
rm -rf "$H"

begin_test "guard-reg: silent when MORE are registered than stamped"
# A user adding their own tagged hook, or an install that grew, must not warn.
H=$(_mkhome "$(_settings_with 160)" 154)
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf when registrations exceeded the stamp"
rm -rf "$H"

begin_test "guard-reg: fails OPEN when there is no stamp"
# Installs predating the stamp must keep the old presence behaviour, not warn.
H=$(_mkhome "$(_settings_with 1)")
[ "$(_warns "$H")" = "silent" ] && pass || fail "warned without a stamp to compare against"
rm -rf "$H"

begin_test "guard-reg: fails OPEN on a garbage or zero stamp"
H=$(_mkhome "$(_settings_with 1)" "abc"); R1=$(_warns "$H"); rm -rf "$H"
H=$(_mkhome "$(_settings_with 1)" 0);     R2=$(_warns "$H"); rm -rf "$H"
[ "$R1" = "silent" ] && [ "$R2" = "silent" ] && pass || fail "garbage=$R1 zero=$R2"

begin_test "guard-reg: the partial warning is parseable systemMessage JSON"
H=$(_mkhome "$(_settings_with 1)" 154)
OUT=$(printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null)
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
m=d['systemMessage']
assert 'PARTIAL' in m, m
assert '1 of 154' in m, m
" >/dev/null 2>&1 && pass || fail "unparseable or wrong partial warning: $OUT"
rm -rf "$H"

begin_test "guard-reg: install.sh stamps the count it registered"
# Without the stamp the comparison above can never run, and the check silently
# reverts to the presence proxy it had before.
#
# v4.0.38: this used to require the literal `grep -o -- '#supercharger'`, which
# pinned the IMPLEMENTATION rather than the property — and that implementation
# was the bug: grepping the whole file counted the statusLine and MCP tags too.
# Assert that the stamp is WRITTEN and that it counts the hooks subtree; the
# metric-parity test further down proves the number is the right one.
grep -q 'registration-count' "$REPO_DIR/install.sh" \
  && grep -q "d.get('hooks', {})).count('$TAG')" "$REPO_DIR/install.sh" \
  && pass || fail "install.sh does not write .registration-count from the hooks subtree"

# --- v4.0.9: the stamp itself can be stripped ---------------------------------
#
# This check reads its baseline from a file nothing protects. Measured against
# the deployed harness-tamper-guard on 2026-09-01:
#     rm -f  ~/.claude/supercharger/.registration-count   allow
#     : >    ~/.claude/supercharger/.registration-count   allow
#     rm -rf ~/.claude/supercharger/hooks                 deny
# so removing the baseline silently disabled the check that notices missing
# registrations. Pattern named by PIsberg/vibetags' locked-files action: "a
# stripped lock is absent from the regenerated report and so invisible to any
# report-based check." The second signal is `.version`, written by the same
# install run.
#
# Both directions matter. Warning when the version says a stamp should exist is
# the fix; STAYING SILENT below the floor is what stops it crying wolf at the
# older installs this hook exists to serve.

_mkhome_ver() {  # $1 = settings body; $2 = version or "" ; $3 = stamp or ""
  local h; h=$(mktemp -d); mkdir -p "$h/.claude" "$h/.claude/supercharger"
  printf '%s\n' "$1" > "$h/.claude/settings.json"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$h/.claude/supercharger/.version"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$h/.claude/supercharger/.registration-count"
  printf '%s' "$h"
}

begin_test "guard-reg: a MISSING stamp warns when the version says it should exist"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.9" "")
[ "$(_warns "$H")" = "warns" ] && pass || fail "stamp stripped at 4.0.9 and the check went silent"
rm -rf "$H"

begin_test "guard-reg: the floor release itself warns"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.1" "")
[ "$(_warns "$H")" = "warns" ] && pass || fail "4.0.1 introduced the stamp; absence should warn"
rm -rf "$H"

begin_test "guard-reg: an install BELOW the floor stays silent (legitimately stampless)"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.0" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf at a pre-stamp install"
rm -rf "$H"

begin_test "guard-reg: a much older install stays silent"
H=$(_mkhome_ver "$(_settings_with 2)" "2.29.41" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf at 2.29.41"
rm -rf "$H"

begin_test "guard-reg: no version file means no verdict"
H=$(_mkhome_ver "$(_settings_with 2)" "" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "claimed a verdict with no second signal"
rm -rf "$H"

begin_test "guard-reg: an unparseable version means no verdict"
# Fail open on junk rather than guess — the same rule the stamp parser follows.
H=$(_mkhome_ver "$(_settings_with 2)" "not-a-version" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "claimed a verdict from an unparseable version"
rm -rf "$H"

begin_test "guard-reg: a present, satisfied stamp is still silent at 4.0.9"
# The regression this pairs with: the new branch must not fire when nothing is wrong.
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.9" "2")
[ "$(_warns "$H")" = "silent" ] && pass || fail "new branch fires on a healthy install"
rm -rf "$H"

# --- v4.0.11: the count can be right while the FILES are gone -----------------
#
# A registration names a file. If the file is missing the entry still carries the
# tag, still counts, and the hook never runs — measured before this existed: 5
# registrations with 2 of the 5 files deleted produced complete silence.
#
# v2.17.3 is the real instance: an installer that copied only hooks/*.sh left
# safety-detect.py absent on every install, python exited 2, and the deny reached
# users as a phantom "hook error: No stderr output". The count was perfect
# throughout, which is exactly why counting is not enough.

# $1 = how many registrations, $2 = how many of their files actually exist
_mkhome_files() {
  local h sc i p out="" n="$1" have="$2"
  h=$(mktemp -d); sc="$h/.claude/supercharger"
  mkdir -p "$sc/hooks" "$sc/scope"
  printf '4.0.11\n' > "$sc/.version"
  printf '%s\n' "$n" > "$sc/.registration-count"
  for ((i = 0; i < n; i++)); do
    p="$sc/hooks/h$i.sh"
    # chmod, because install.sh does: registrations invoke the file DIRECTLY, so
    # a 0644 hook is found by the existence check and still never runs. The Write
    # tool creates 0644, which is exactly how the bit goes missing in practice.
    [ "$i" -lt "$have" ] && { printf '#!/usr/bin/env bash\nexit 0\n' > "$p"; chmod +x "$p"; }
    out="$out{\"hooks\":[{\"type\":\"command\",\"command\":\"$p $TAG\"}]},"
  done
  printf '{"hooks":{"PreToolUse":[%s]}}' "${out%,}" > "$h/.claude/settings.json"
  printf '%s' "$h"
}

begin_test "guard-reg: registered hooks whose FILES are gone are reported"
H=$(_mkhome_files 5 3)
_warn_out=$(printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null)
case "$_warn_out" in
  *"2 REGISTERED HOOK FILE(S) MISSING"*) pass ;;
  "") fail "2 of 5 hook files missing and the check stayed silent" ;;
  *) fail "wrong message: ${_warn_out:0:90}" ;;
esac
rm -rf "$H"

begin_test "guard-reg: silent when every registered file is present"
# The cry-wolf half — a healthy install must not be told its guards are gone.
H=$(_mkhome_files 5 5)
[ "$(_warns "$H")" = "silent" ] && pass || fail "warned about missing files on a complete install"
rm -rf "$H"

begin_test "guard-reg: the missing-file warning is parseable systemMessage JSON"
# A malformed payload is worse than none: Claude Code drops the line and the
# session is told nothing, which is the failure this hook exists to prevent.
H=$(_mkhome_files 4 1)
printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if "systemMessage" in d and "MISSING" in d["systemMessage"] else 1)' \
  && pass || fail "warning is not valid systemMessage JSON"
rm -rf "$H"

# --- v4.0.19: EXISTS is not RUNS -------------------------------------------
#
# Every registration on this machine invokes its hook as a bare path (measured:
# 158 of 158), so a file that has lost its executable bit passes the existence
# check above and still never fires. Measured on a full copy of the installed
# tree — a lib-less copy errors for unrelated reasons and lies about the control:
#
#     executable, given a destructive command   exit 2    deny, guard runs
#     same hook, +x removed                     exit 126  permission denied
#     `[ -f ]` PASSES, `[ -x ]` FAILS
#
# Sibling arm of the v4.0.11 missing-file check: that one fixed half the
# question, this is the other half.

begin_test "guard-reg: a registered hook that is not EXECUTABLE is reported"
H=$(_mkhome_files 4 4)
chmod -x "$H/.claude/supercharger/hooks/h1.sh"
if [ -x "$H/.claude/supercharger/hooks/h1.sh" ]; then
  # The filesystem does not store the execute bit — MSYS/NTFS derives it, so
  # `chmod -x` is a no-op and `[ -x ]` stays true. v4.0.19's Git Bash job failed
  # here for exactly that reason. The check cannot fire on such a filesystem and
  # a hook cannot lose the bit there either, so there is nothing to assert.
  # Gated on the PRECONDITION, not on a platform name: true wherever it is true.
  pass
else
  _x_out=$(printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null)
  case "$_x_out" in
    *"NOT EXECUTABLE"*) pass ;;
    "") fail "a non-executable registered hook was not reported" ;;
    *) fail "wrong message: ${_x_out:0:90}" ;;
  esac
fi
rm -rf "$H"

begin_test "guard-reg: a MISSING file outranks a non-executable one"
# Both broken at once: the missing file is the more serious finding and the one
# whose fix (re-run the installer) also restores the mode.
H=$(_mkhome_files 4 3)
chmod -x "$H/.claude/supercharger/hooks/h0.sh" 2>/dev/null || true
_x_out=$(printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null)
case "$_x_out" in
  *"MISSING"*) pass ;;
  *) fail "expected the missing-file message to win, got: ${_x_out:0:80}" ;;
esac
rm -rf "$H"

begin_test "guard-reg: an interpreter-invoked hook does not need the bit"
# `bash /path/hook.sh` ignores the mode entirely; flagging it would cry wolf at
# an install that is completely fine.
H=$(_mkhome_files 3 3)
python3 - "$H" <<'PY'
import json, os, sys
h = sys.argv[1]
sc = os.path.join(h, ".claude", "supercharger")
tag = "#" + "supercharger"
ents = []
for i in range(3):
    p = os.path.join(sc, "hooks", "h%d.sh" % i)
    os.chmod(p, 0o644)                      # no executable bit anywhere
    ents.append({"hooks": [{"type": "command", "command": "bash %s %s" % (p, tag)}]})
json.dump({"hooks": {"PreToolUse": ents}},
          open(os.path.join(h, ".claude", "settings.json"), "w"))
PY
[ "$(_warns "$H")" = "silent" ] && pass || fail "flagged an interpreter-invoked hook"
rm -rf "$H"

# --- v4.0.35: at-rest permissions on the state tree --------------------------
# Nothing in the codebase set a mode, so the state tree inherited the user's
# umask. Measured 2026-09-06: umask 022 -> drwxr-xr-x, umask 077 -> drwx------.
# Contents are the blocked-command ledger, handoff briefs, tool history and
# subagent reports — no credentials (event-logger redacts), but working context.
# Harmless on a single-user laptop, readable by any local user on a shared host,
# CI runner or multi-user container.
#
# install.sh fixes it at install time; this hook is the repair path for installs
# that never re-run it. It lives here rather than lib-paths.sh because 21 hooks
# source that on hot paths and would each pay a syscall.
# Source: akasecurity/ai-tc SECURITY.md, see [[candidate-card-number-luhn]].
_GRP_HOOK="$REPO_DIR/hooks/guard-registration-check.sh"
_grp_mode() { ls -ld "$1" 2>/dev/null | awk '{print substr($1,1,10)}'; }

# chmod is ADVISORY on MSYS/NTFS: the mode is derived from the file rather than
# stored, so `chmod 700` does not stick and this assertion fails on Git Bash
# through no fault of the code. Gate on the PRECONDITION actually holding, never
# on a platform name — the same rule the artifact-guard tests already follow, and
# the same limitation ai-tc's SECURITY.md discloses about its own store ("those
# POSIX modes are a no-op on Windows"). Quoted in v4.0.35's message and then not
# applied to this test, which is how it went red on Windows.
_GRP_T=$(mktemp -d); mkdir -p "$_GRP_T/state/scope"; chmod 755 "$_GRP_T/state" "$_GRP_T/state/scope"
chmod 700 "$_GRP_T/state" 2>/dev/null || true
if [ "$(_grp_mode "$_GRP_T/state")" != "drwx------" ]; then
  begin_test "state-tree tightening (skipped — filesystem ignores chmod)"
  pass
  rm -rf "$_GRP_T"
else
  chmod 755 "$_GRP_T/state"
  begin_test "a world-readable state tree is tightened to 0700"
  printf '{"session_id":"p","cwd":"/tmp"}' | SUPERCHARGER_STATE="$_GRP_T/state" bash "$_GRP_HOOK" >/dev/null 2>&1
  [ "$(_grp_mode "$_GRP_T/state")" = "drwx------" ] && [ "$(_grp_mode "$_GRP_T/state/scope")" = "drwx------" ] \
    && pass || fail "state=$(_grp_mode "$_GRP_T/state") scope=$(_grp_mode "$_GRP_T/state/scope")"
  rm -rf "$_GRP_T"
fi

begin_test "a SYMLINKED state dir leaves the target's permissions alone"
# chmod follows symlinks, so a state dir pointing at a synced or shared folder
# would have someone else's directory silently retightened.
_GRP_R=$(mktemp -d); mkdir -p "$_GRP_R/shared"; chmod 755 "$_GRP_R/shared"
_GRP_L=$(mktemp -d); rm -rf "$_GRP_L/state"; ln -s "$_GRP_R/shared" "$_GRP_L/state"
printf '{"session_id":"p","cwd":"/tmp"}' | SUPERCHARGER_STATE="$_GRP_L/state" bash "$_GRP_HOOK" >/dev/null 2>&1
[ "$(_grp_mode "$_GRP_R/shared")" = "drwxr-xr-x" ] && pass \
  || fail "chmod went through the symlink: $(_grp_mode "$_GRP_R/shared")"
rm -rf "$_GRP_R" "$_GRP_L"

begin_test "install.sh sets the mode too, and skips symlinks"
grep -q 'chmod 700 "\$_sc_secure_dir"' "$REPO_DIR/install.sh" \
  && grep -q 'if \[ -L "\$_sc_secure_dir" \]' "$REPO_DIR/install.sh" && pass \
  || fail "install.sh does not secure the state dir, or does it through symlinks"

# --- v4.0.37: the doctor's Delivery & Integrity checks -----------------------
# claude-check.sh trusted the version stamp everywhere. These four checks do not,
# because the stamp is exactly what lied when update.sh compared the repo to
# itself and reported success while deploying nothing ([[silent-success-tooling]]).
_DOC="$REPO_DIR/tools/claude-check.sh"

begin_test "doctor: verifies the deployed code against the version stamp"
grep -q '_doc_code=' "$_DOC" && grep -q 'Install integrity' "$_DOC" && pass \
  || fail "no stamp-vs-code check — every other check trusts the stamp"

begin_test "doctor: checks session notices are on a channel that renders"
# Raw stdout from a SessionStart hook is never shown; systemMessage is.
grep -q 'Session notices use a channel that renders' "$_DOC" && pass \
  || fail "a muted user-facing hook would look healthy"

begin_test "doctor: checks state-directory permissions, and skips symlinks"
grep -q 'State directory is private' "$_DOC" && grep -q 'if \[ -L "\$_doc_d" \]' "$_DOC" \
  && pass || fail "missing the permissions check, or it follows symlinks"

begin_test "doctor: reads the update cache rather than the network"
# A doctor that hangs on a slow connection is a doctor nobody runs twice.
grep -q '_doc_remote=$(cat "$_DOC_STATE/.update-cache"' "$_DOC" \
  && ! grep -qE 'curl|wget|urlopen' "$_DOC" && pass \
  || fail "the doctor makes a network call"

begin_test "doctor: prints ONE pasteable verdict line"
# The deliverable for a colleague who cannot read the report.
grep -q 'Paste this if you are asking for help' "$_DOC" && pass \
  || fail "no verdict line — a report nobody can act on is a report nobody runs"

begin_test "doctor: the verdict uses colours this script actually defines"
# DIM is a statusline variable; using it here died on `unbound variable` under
# set -u, AFTER three checks had already printed. Caught by running it, not by
# reading it.
! grep -q '\${DIM}' "$_DOC" && pass || fail "\$DIM is not defined in claude-check.sh"

begin_test "/sc-doctor exists in BOTH the source and the generated plugin copy"
# commands/ is generated from configs/commands/; editing one and not the other
# is a standing trap in this repo.
[ -f "$REPO_DIR/configs/commands/sc-doctor.md" ] && [ -f "$REPO_DIR/commands/doctor.md" ] \
  && pass || fail "command missing from source or generated copy"

# --- v4.0.38: the install stamp and the check must be the SAME metric ---------
# install.sh grepped the WHOLE settings.json for '#supercharger'; the check counts
# tags inside .hooks. A standard install tags the statusLine (1) and each MCP
# server (2), so the stamp read 162 against 159 real registrations and the check
# reported "3 registration(s) MISSING" on a healthy machine — permanently.
# v4.0.37 then made every red mark increment ERRORS, promoting that standing false
# alarm to a hard error and a non-zero exit.
#
# install.sh's comment claimed it used "the same expression the check uses". It
# did not, and nothing compared them, so the claim survived being false. This test
# is that comparison. [[guard-fails-open-oracle-fails-loud]] in reverse: an oracle
# crying wolf is how people learn to ignore it.

begin_test "the install stamp counts hook registrations, not every tag in the file"
grep -q "d.get('hooks', {})).count('#supercharger')" "$REPO_DIR/install.sh" && pass \
  || fail "stamp is not scoped to the hooks subtree"

begin_test "install.sh no longer greps the whole settings.json for the tag"
grep -qE "grep -o -- '#supercharger' \"\\\$HOME/.claude/settings.json\"" "$REPO_DIR/install.sh" \
  && fail "whole-file grep is back — statusLine and MCP tags will inflate the stamp" || pass

begin_test "on a file with statusLine and MCP tags, the two metrics AGREE"
# The behavioural half: extract the expression install.sh actually ships and run
# it against a fixture that contains exactly the non-hook tags which caused this.
_STM_D=$(mktemp -d)
cat > "$_STM_D/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/h/a.sh #supercharger"}]},
      {"matcher": "Write", "hooks": [{"type": "command", "command": "/h/b.sh #supercharger"}]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "/h/c.sh #supercharger"}]}
    ]
  },
  "statusLine": {"type": "command", "command": "/h/statusline.sh #supercharger"},
  "mcpServers": {"one": {"command": "x #supercharger"}, "two": {"command": "y #supercharger"}}
}
JSON
_STM_STAMP=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps(d.get('hooks', {})).count('#supercharger'))
" "$_STM_D/settings.json")
_STM_CHECK=$(python3 -c "
import json, sys
s = json.load(open(sys.argv[1]))
hooks = s.get('hooks', {})
count = 0
for event in hooks.values():
    for entry in event:
        for h in entry.get('hooks', []):
            if 'supercharger' in h.get('command', ''):
                count += 1
        if 'supercharger' in entry.get('command', ''):
            count += 1
print(count)
" "$_STM_D/settings.json")
_STM_WHOLE=$(grep -o -- '#supercharger' "$_STM_D/settings.json" | wc -l | tr -d ' ')
rm -rf "$_STM_D"
# The fixture must actually exercise the bug, or this test proves nothing:
# whole-file must DIFFER from the hooks-only count.
if [ "$_STM_WHOLE" = "$_STM_STAMP" ]; then
  fail "fixture has no non-hook tags — it cannot detect the defect"
elif [ "$_STM_STAMP" = "$_STM_CHECK" ]; then
  pass
else
  fail "stamp=$_STM_STAMP check=$_STM_CHECK (whole-file would be $_STM_WHOLE)"
fi

# --- v4.0.39: the diagnostic must REACH its verdict ---------------------------
# Reported 2026-09-08 from a repo detecting as JavaScript/pnpm/Vite with no
# framework: claude-check.sh died at "Detected Stack:". Under `set -euo pipefail`
# a no-match `grep` exits 1, and `FW=$(... | grep '^framework=' ...)` therefore
# aborted the whole script — so the session summaries, the Delivery & Integrity
# block and the paste-back verdict line never printed.
#
# A diagnostic that stops early is worse than one reporting a gap: the reader
# cannot tell "clean" from "never got there". Six substitutions had this shape.
_ABT_mkhome() {  # fake HOME whose detect-stack emits NO framework= line
  local h; h=$(mktemp -d)
  mkdir -p "$h/.claude/supercharger/hooks" "$h/.claude/supercharger/scope" "$h/.claude/rules"
  cp -R "$REPO_DIR/hooks/." "$h/.claude/supercharger/hooks/" 2>/dev/null
  cp -R "$REPO_DIR/lib" "$h/.claude/supercharger/lib" 2>/dev/null
  printf '9.9.9\n' > "$h/.claude/supercharger/.version"
  printf '{"hooks":{}}\n' > "$h/.claude/settings.json"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "detected=true"\n'
    printf 'echo "language=JavaScript"\n'
    printf 'echo "package_manager=pnpm"\n'
  } > "$h/.claude/supercharger/hooks/detect-stack.sh"
  chmod +x "$h/.claude/supercharger/hooks/detect-stack.sh"
  printf '%s' "$h"
}

begin_test "claude-check reaches its verdict when the stack has no framework"
_ABT_H=$(_ABT_mkhome)
_ABT_OUT=$(cd /tmp && HOME="$_ABT_H" bash "$REPO_DIR/tools/claude-check.sh" 2>&1)
rm -rf "$_ABT_H"
case "$_ABT_OUT" in
  *"Paste this if you are asking for help"*) pass ;;
  *) fail "aborted before the verdict; last line: $(printf '%s' "$_ABT_OUT" | tail -1 | cut -c1-60)" ;;
esac

begin_test "no substitution in claude-check can abort it on a no-match grep"
# Guard the class, not the one line the report named.
_ABT_BAD=$(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(.*grep' "$REPO_DIR/tools/claude-check.sh" \
  | grep -v '||' | wc -l | tr -d ' ')
[ "$_ABT_BAD" = "0" ] && pass || fail "$_ABT_BAD unguarded grep substitution(s) under set -e"

# --- the verdict must not contradict the score it just printed ----------------
# "All checks passed ✓" beside 87/100 and Team 0/10 leaves the reader unable to
# separate a FAULT from an UNCONFIGURED optional feature. ERRORS counts broken
# things; the score also counts things merely not set up.
begin_test "a non-perfect score with no errors says 'No faults found', not 'All checks passed'"
grep -q 'No faults found' "$REPO_DIR/tools/claude-check.sh" \
  && grep -q 'ERRORS" -eq 0 \] && \[ "$TOTAL_SCORE" -ge 100' "$REPO_DIR/tools/claude-check.sh" \
  && pass || fail "the verdict does not distinguish faults from unconfigured features"

begin_test "the pasteable line carries the score, not just the error count"
# errors 0 alone hides a 40/100 install from whoever is helping remotely.
grep -q 'score ${TOTAL_SCORE:-?}/100' "$REPO_DIR/tools/claude-check.sh" \
  && pass || fail "score missing from the verdict line"

# --- v4.0.41: two same-day fixes collided on the update status ----------------
# v4.0.40 made install.sh clear .update-cache — correct, it is fetched BEFORE an
# install and answers for the old version afterwards. But the doctor reads only
# that cache, so immediately after an update it said "update unknown" while
# /sc-update had said "up to date" a minute earlier. Cosmetic, and precisely the
# small wrongness that teaches a reader to skim the verdict line.
#
# The doctor still makes NO network call: one that hangs on a slow connection is
# one nobody runs twice. It just reports what is known rather than "unknown".

begin_test "doctor: a freshly installed tree is not reported as 'unknown'"
grep -q 'Freshly installed' "$REPO_DIR/tools/claude-check.sh" && pass \
  || fail "post-update state still reads as unknown"

begin_test "doctor: the never-checked case says WHEN it will be checked"
grep -q 'Not checked yet today — the next session start will check' "$REPO_DIR/tools/claude-check.sh" \
  && pass || fail "a bare 'unknown' tells the reader nothing actionable"

begin_test "doctor: still makes no network call"
# The property that keeps it fast enough to run twice.
grep -qE 'curl|wget|urlopen|nc ' "$REPO_DIR/tools/claude-check.sh" \
  && fail "the doctor now touches the network" || pass

# --- v4.0.42: the report is meant to be pasted, so it must not carry $HOME ----
# jacksonanstee/agent-harness-JA ADR-0027: their 25 credential rules matched no
# filesystem path, so every retained row kept the operator's home directory —
# and on a work machine the client directory name with it. Our verdict line was
# already clean; the deep-scan advisory printed the expanded path.
#
# Scope is deliberate: only the SHAREABLE surface. That ADR killed three designs
# for normalising every retained sink, because `~` is a legal directory name at
# any depth so the substitution is not injective. The local ledger keeps real
# paths and is 0700.
begin_test "doctor: the shareable report prints ~ , not an expanded \$HOME"
_PL_OUT=$(cd /tmp && bash "$REPO_DIR/tools/claude-check.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
_PL_LEAK=$(printf '%s' "$_PL_OUT" | grep -E '/(Users|home)/[a-zA-Z0-9._-]+/' || true)
[ -z "$_PL_LEAK" ] && pass || fail "leaked: $(printf '%s' "$_PL_LEAK" | tr '\n' '|')"

# v4.0.43: the run above uses the author's OWN $HOME, so it only ever exercises
# the branches a fully-populated install takes. The leak that shipped was in the
# `else` arm of the analytics block — reached only when ~/.claude/projects does
# not exist, i.e. on a pristine $HOME. Same shape as the fresh-install crash the
# previous test found: the untaken branch is where the defects live. $HOME here
# must LOOK like a home path, or the assertion cannot fail.
begin_test "doctor: and on a pristine \$HOME too (the branch that leaked)"
_PL_H="${TMPDIR:-/tmp}/sc-doctor-pristine-$$/Users/probe"
mkdir -p "$_PL_H"
_PL_OUT2=$(cd /tmp && HOME="$_PL_H" bash "$REPO_DIR/tools/claude-check.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
_PL_LEAK2=$(printf '%s' "$_PL_OUT2" | grep -F "$_PL_H" || true)
rm -rf "${TMPDIR:-/tmp}/sc-doctor-pristine-$$"
[ -z "$_PL_LEAK2" ] && pass || fail "leaked: $(printf '%s' "$_PL_LEAK2" | tr '\n' '|')"

begin_test "doctor: and the pasteable verdict line specifically is clean"
# The control: this is the line people actually send, so it must never regress.
printf '%s' "$_PL_OUT" | grep -A2 'Paste this if you are asking for help' \
  | grep -qE '/(Users|home)/[a-zA-Z0-9._-]+/' && fail "verdict line leaks a home path" || pass

report
