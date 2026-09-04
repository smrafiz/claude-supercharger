#!/usr/bin/env bash
# Skill Integrity Guard — change detection for skills.
#
# skill-poisoning-scanner asks whether a skill LOOKS malicious. This asks whether
# it is the SAME FILE as last time. A skill is instructions Claude follows, so a
# silent edit is a persistent behaviour change with no event anywhere.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Skill Integrity Guard Tests ==="

# --- Task 1: the shared resolver -----------------------------------------------
# Two hooks must agree on which file a skill name means. One resolver, two
# consumers; two copies would drift the moment one is edited (v2.9.8).
SR_HOME=$(mktemp -d)
mkdir -p "$SR_HOME/.claude/skills/demo"
printf 'body\n' > "$SR_HOME/.claude/skills/demo/SKILL.md"

# native_path for the WRITER side of the boundary: on Git Bash python3 is native
# Windows Python and resolves an MSYS path against the current drive.
SR_HOME_N=$(native_path "$SR_HOME")

_resolve_count() {
  SR_SKILL="$1" SR_HOME_N="$SR_HOME_N" python3 -c "
import os, sys
sys.path.insert(0, sys.argv[1])
from lib_skill_resolve import resolve_skill_paths
print(len(resolve_skill_paths(os.environ['SR_SKILL'],
                              os.environ['SR_HOME_N'],
                              os.environ['SR_HOME_N'])))" "$REPO_DIR/hooks" 2>/dev/null || echo ERR
}

begin_test "resolver: finds <home>/.claude/skills/<name>/SKILL.md"
GOT=$(_resolve_count demo)
[ "$GOT" = "1" ] && pass || fail "expected 1 resolved path, got $GOT"

begin_test "resolver: a namespaced plugin:skill still resolves by bare name"
GOT=$(_resolve_count 'bundle:demo')
[ "$GOT" = "1" ] && pass || fail "namespaced name did not resolve, got $GOT"

begin_test "resolver: an unknown skill resolves to nothing"
GOT=$(_resolve_count nosuchskill)
[ "$GOT" = "0" ] && pass || fail "expected 0, got $GOT"

rm -rf "$SR_HOME"

# --- Task 2: trust on first use ------------------------------------------------
GUARD="$REPO_DIR/hooks/skill-integrity-guard.sh"
SIG_HOME=$(mktemp -d)
SIG_STATE=$(mktemp -d)
mkdir -p "$SIG_HOME/.claude/skills/demo"
printf 'original body\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"

# The guard reads HOME and cwd from the payload/env, so both sides of the MSYS
# boundary must agree: bash writes the fixture, python inside the hook resolves
# it. native_path is the writer-side normalisation; the hook does the reader side.
SIG_HOME_N=$(native_path "$SIG_HOME")

sig() {
  printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"cwd":"%s"}' "$1" "$SIG_HOME_N" \
    | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" bash "$GUARD" 2>/dev/null \
    | grep -o '"permissionDecision":"[a-z]*"' || echo none
}

begin_test "skill-lock: the first load is silent and records a baseline"
[ "$(sig demo)" = "none" ] && pass || fail "first load should be silent, got $(sig demo)"

begin_test "skill-lock: the baseline is on disk with a sha256"
grep -q '"sha256"' "$SIG_STATE/scope/.skills-lock" 2>/dev/null && pass \
  || fail "no baseline written to $SIG_STATE/scope/.skills-lock"

begin_test "skill-lock: an unchanged skill stays silent on reload"
[ "$(sig demo)" = "none" ] && pass || fail "unchanged skill should be silent"


# --- Task 3: drift asks --------------------------------------------------------
begin_test "skill-lock: an edited skill ASKS"
printf 'MALICIOUS body\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"
[ "$(sig demo)" = '"permissionDecision":"ask"' ] && pass || fail "edit not caught, got $(sig demo)"

begin_test "skill-lock: the reason names the skill and both hashes"
printf 'MALICIOUS again\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"
SIG_OUT=$(printf '{"tool_name":"Skill","tool_input":{"skill":"demo"},"cwd":"%s"}' "$SIG_HOME_N" \
  | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" bash "$GUARD" 2>/dev/null)
case "$SIG_OUT" in *SKILL.md*changed*) pass ;; *) fail "reason does not describe the change: $SIG_OUT" ;; esac

begin_test "skill-lock: after asking once, the new hash becomes the baseline"
[ "$(sig demo)" = "none" ] && pass || fail "should not ask twice for the same content"

begin_test "skill-lock: the block is recorded in the ledger for /why"
grep -q 'skills —' "$SIG_STATE/scope/.blocked-commands" 2>/dev/null && pass \
  || fail "nothing written to the ledger"

begin_test "skill-lock: the kill switch is honoured"
printf 'changed once more\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"
SIG_N=$(printf '{"tool_name":"Skill","tool_input":{"skill":"demo"},"cwd":"%s"}' "$SIG_HOME_N" \
  | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" SUPERCHARGER_SKILL_LOCK=0 \
    bash "$GUARD" 2>/dev/null | grep -c permissionDecision || true)
[ "$SIG_N" = "0" ] && pass || fail "kill switch ignored"

# --- Task 4: unreadable is not unchanged ---------------------------------------
# This branch is the one most likely to be "simplified" away later. v4.0.26 fixed
# exactly this collapse inside artifact-publish-guard: "nothing to scan" and
# "could not scan" shared an exit, so an unreadable page published unscanned.
mkdir -p "$SIG_HOME/.claude/skills/unreadable"
printf 'body\n' > "$SIG_HOME/.claude/skills/unreadable/SKILL.md"
sig unreadable >/dev/null   # establish a baseline while it is still readable
chmod 000 "$SIG_HOME/.claude/skills/unreadable/SKILL.md" 2>/dev/null || true
if [ -r "$SIG_HOME/.claude/skills/unreadable/SKILL.md" ]; then
  # MSYS/NTFS derives permissions from the file rather than storing them, so
  # chmod 000 is a no-op and the branch CANNOT fire. Gate on the precondition,
  # never on a platform name — v4.0.21, where the same assertion was gated on
  # "is this Windows" and was wrong about why.
  begin_test "skill-lock: unreadable case (skipped — filesystem ignores chmod)"
  pass
else
  begin_test "skill-lock: an unreadable skill ASKS rather than passing as unchanged"
  [ "$(sig unreadable)" = '"permissionDecision":"ask"' ] && pass \
    || fail "unreadable skill treated as clean, got $(sig unreadable)"
fi
chmod 644 "$SIG_HOME/.claude/skills/unreadable/SKILL.md" 2>/dev/null || true

begin_test "skill-lock: a skill that does not exist on disk is silent, not an ask"
[ "$(sig ghostskill)" = "none" ] && pass || fail "missing skill should be a no-op"

rm -rf "$SIG_HOME" "$SIG_STATE"

# --- Task 5: registration ------------------------------------------------------
# Nothing in this repo may silently not run. A hook that is written but not
# registered is indistinguishable from one that passes.
begin_test "skill-lock: registered on PreToolUse:Skill"
. "$REPO_DIR/lib/hooks.sh"
SUPERCHARGER_EMIT_ALL=1 get_hooks_for_mode "full" "true" '/h' 2>/dev/null \
  | grep -q 'PreToolUse|Skill|.*skill-integrity-guard.sh' && pass \
  || fail "not registered — the hook never fires"

begin_test "skill-lock: the generated plugin hooks.json carries it"
grep -q 'skill-integrity-guard' "$REPO_DIR/hooks/hooks.json" && pass \
  || fail "run tools/gen-plugin-hooks.sh — the two channels have drifted"

begin_test "skill-lock: hook is executable"
[ -x "$REPO_DIR/hooks/skill-integrity-guard.sh" ] && pass || fail "not executable"

report
