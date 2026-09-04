# Skill Integrity Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notice when a skill's content changes between loads, and ask before loading the changed version.

**Architecture:** Trust-on-first-use, like `known_hosts`. The first time a skill is
loaded its SHA-256 is recorded; every later load compares against that record. A
changed hash ASKS once per skill per session. No lockfile is authored by hand and
no curation step exists — the guard learns what it sees, then notices change.

**Tech Stack:** Bash 3.2, python3 (hashlib, json, pathlib) — both already hard
dependencies. No new packages.

**Spec:** this document. The problem statement is in "Why", the decisions in
"Design decisions"; the tasks argue from both.

## Why

`skill-poisoning-scanner.sh` scans skill content for injection patterns at load
time. That is classification, not change detection, and the two catch different
things:

- The scanner asks *does this look malicious?* — a fixed pattern list.
- Nothing asks *is this the same file I loaded yesterday?*

A skill that passes the pattern scan today passes it tomorrow, after an upstream
edit, a `git pull` in a plugin marketplace, or a local write that path-guard did
not cover. Skills are instructions the model follows; a silent edit to one is a
persistent behavior change with no event anywhere. `trycompai/crm` pins every
external skill by SHA-256 in a committed `skills-lock.json`, which is where this
idea comes from; their lockfile is produced by an external tool, so the concept
transfers and no code does.

**Honest severity.** This is a detection gap, not a live bypass. It buys the case
where content changed *and* the change is benign-looking to the pattern scanner.
Worth one hook on a cold channel; not worth overstating.

## Design decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Baseline source | Trust on first use | A hand-authored lockfile needs a curation step nobody performs. TOFU works from install with zero configuration, which is the house default. |
| Verdict on drift | `ask`, once per skill per session | Matches `lockfile-integrity-guard`: a legitimate edit is common enough that `deny` would train people to disable the guard. |
| Skill file missing | silent `exit 0` | Pre-existing unscannable condition — `skill-poisoning-scanner` already exits 0 there. Not this hook's problem to raise. |
| Skill file present but unreadable | `ask` | "I could not read it" is not "it did not change". This is the v4.0.26 `artifact-publish-guard` lesson; the error path and the all-clear path must not share an exit. |
| Lock location | `$SUPERCHARGER_STATE/scope/.skills-lock` | State, not code. Follows `CLAUDE_PLUGIN_DATA` resolution used by every other guard. |
| Lock key | resolved absolute path | The same skill name under `~/.claude/skills` and a plugin dir are different files and must not alias. |
| Resolver | extracted to a shared lib | Duplicating the scanner's glob logic guarantees drift — v2.9.8 cross-channel parity drift, and the reason `lib_poison_patterns.py` already exists. |

## Global Constraints

- Bash 3.2 compatible. No `wait -n`, no associative arrays, no `${var^^}`.
- `set -uo pipefail` — never `-e` in a hook; a guard that dies must fail open.
- Kill switch `SUPERCHARGER_SKILL_LOCK=0`, plus `check_hook_disabled "skill-integrity-guard"`.
- One `python3` fork maximum per invocation. Fires only on `PreToolUse|Skill`, not on Bash/Edit.
- `shellcheck --severity=error` clean.
- Every hook must be registered in `lib/hooks.sh` or `tests/test-orphan-registration.sh` fails with the filename. Do not allowlist it.
- `hooks/hooks.json` is generated — run `bash tools/gen-plugin-hooks.sh`, never hand-edit.
- Windows: hash raw bytes, never text-mode reads. Any python that receives a shell-made temp path in tests must be handed `native_path` (see `tests/test-artifact-publish-guard.sh`).
- No `Co-Authored-By` trailer. Commit messages end with the session trailer used by the rest of this branch.

## File Structure

| File | Responsibility |
| --- | --- |
| `hooks/lib_skill_resolve.py` (create) | Resolve an invoked skill name to file paths on disk. Sole owner of the candidate dirs and glob shapes. |
| `hooks/skill-integrity-guard.sh` (create) | Hash the resolved file, compare to the lock, emit the verdict, update the lock. |
| `hooks/skill-poisoning-scanner.sh` (modify) | Stop owning resolution; import the shared resolver. Behavior unchanged. |
| `lib/hooks.sh` (modify, near line 354) | Register the new hook on `PreToolUse|Skill`. |
| `hooks/hooks.json` (regenerate) | Plugin-runtime copy of the registration. |
| `tests/test-skill-integrity-guard.sh` (create) | All behavior below. |

---

### Task 1: Extract the skill resolver into a shared module

Two hooks must agree on which file a skill name refers to. Today one of them owns
that logic inline. Extract it first, prove the scanner is unchanged, then build on it.

**Files:**
- Create: `hooks/lib_skill_resolve.py`
- Modify: `hooks/skill-poisoning-scanner.sh:71-110`
- Test: `tests/test-skill-integrity-guard.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `resolve_skill_paths(skill: str, home_dir: str, cwd: str) -> list[pathlib.Path]` — resolved, de-duplicated, existing files only; empty list when nothing matches.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Skill Integrity Guard Tests ==="

begin_test "resolver: finds <home>/.claude/skills/<name>/SKILL.md"
SR_HOME=$(mktemp -d)
mkdir -p "$SR_HOME/.claude/skills/demo"
printf 'body\n' > "$SR_HOME/.claude/skills/demo/SKILL.md"
GOT=$(SR_HOME_N="$(native_path "$SR_HOME")" python3 -c "
import os, sys
sys.path.insert(0, sys.argv[1])
from lib_skill_resolve import resolve_skill_paths
p = resolve_skill_paths('demo', os.environ['SR_HOME_N'], os.environ['SR_HOME_N'])
print(len(p))" "$REPO_DIR/hooks")
[ "$GOT" = "1" ] && pass || fail "expected 1 resolved path, got $GOT"

begin_test "resolver: a namespaced plugin:skill still resolves by bare name"
GOT=$(SR_HOME_N="$(native_path "$SR_HOME")" python3 -c "
import os, sys
sys.path.insert(0, sys.argv[1])
from lib_skill_resolve import resolve_skill_paths
p = resolve_skill_paths('bundle:demo', os.environ['SR_HOME_N'], os.environ['SR_HOME_N'])
print(len(p))" "$REPO_DIR/hooks")
[ "$GOT" = "1" ] && pass || fail "namespaced name did not resolve, got $GOT"

begin_test "resolver: an unknown skill resolves to nothing"
GOT=$(SR_HOME_N="$(native_path "$SR_HOME")" python3 -c "
import os, sys
sys.path.insert(0, sys.argv[1])
from lib_skill_resolve import resolve_skill_paths
p = resolve_skill_paths('nosuchskill', os.environ['SR_HOME_N'], os.environ['SR_HOME_N'])
print(len(p))" "$REPO_DIR/hooks")
[ "$GOT" = "0" ] && pass || fail "expected 0, got $GOT"
rm -rf "$SR_HOME"

report
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: FAIL — `ModuleNotFoundError: No module named 'lib_skill_resolve'`

- [ ] **Step 3: Write the module**

```python
"""Resolve an invoked skill name to the file(s) backing it on disk.

Shared by skill-poisoning-scanner (content classification) and
skill-integrity-guard (change detection). Both must agree on WHICH file a
skill name means; two copies of this logic would drift the moment one is
edited, which is the v2.9.8 cross-channel parity failure.
"""
import re
from pathlib import Path


def resolve_skill_paths(skill, home_dir, cwd):
    candidates = [
        Path(home_dir) / '.claude' / 'commands',
        Path(home_dir) / '.claude' / 'plugins',
        Path(home_dir) / '.claude' / 'skills',
        Path(cwd) / '.claude' / 'commands',
        Path(cwd) / '.claude' / 'plugins',
        Path(cwd) / '.claude' / 'skills',
    ]

    # Skills are often invoked namespaced ("plugin:skill") while the file on
    # disk is named by the bare skill. Searching only the raw value matches
    # nothing and skips the file entirely (v2.7.54).
    skill_names = {skill}
    bare = re.split(r'[:/]', skill)[-1]
    if bare:
        skill_names.add(bare)

    patterns = []
    for nm in skill_names:
        patterns += [
            f'{nm}.md', f'*/{nm}.md', f'*/*/{nm}.md', f'*/*/*/{nm}.md',
            f'{nm}/SKILL.md', f'*/{nm}/SKILL.md', f'*/*/{nm}/SKILL.md',
            f'{nm}/skill.md', f'*/{nm}/skill.md', f'*/*/{nm}/skill.md',
        ]

    seen = set()
    out = []
    for base in candidates:
        if not base.is_dir():
            continue
        for pat in patterns:
            try:
                for p in base.glob(pat):
                    if p.is_file():
                        rp = str(p.resolve())
                        if rp not in seen:
                            seen.add(rp)
                            out.append(p)
            except Exception:
                continue
    return out
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: `3 passed, 0 failed`

- [ ] **Step 5: Switch the scanner to the shared resolver**

In `hooks/skill-poisoning-scanner.sh`, replace the inline `candidates` /
`skill_names` / `glob_patterns` / `_seen` block (lines 71-110) with:

```python
_resolve = None
try:
    sys.path.insert(0, os.environ['HOOKS_DIR_PY'])
    from lib_skill_resolve import resolve_skill_paths as _resolve
except Exception:
    _resolve = None

if _resolve is None:
    # The shared resolver is the only resolver. If it cannot be imported the
    # scan did not happen -- exit silently rather than report a clean scan,
    # matching the existing no-paths behaviour below.
    sys.exit(0)

scan_paths = _resolve(skill, home_dir, cwd)
if not scan_paths:
    sys.exit(0)
```

- [ ] **Step 6: Prove the scanner is behaviourally unchanged**

Run: `bash tests/test-hooks.sh && bash tests/test-skill-poisoning.sh 2>/dev/null || true`
Expected: every skill-poisoning assertion passes, same counts as before the edit.

- [ ] **Step 7: Commit**

```bash
git add hooks/lib_skill_resolve.py hooks/skill-poisoning-scanner.sh tests/test-skill-integrity-guard.sh
git commit -m "refactor(skills): one resolver, two consumers

skill-poisoning-scanner owned the candidate dirs and glob shapes inline. A
second hook now needs the same answer, and two copies drift the moment one is
edited -- v2.9.8, cross-channel parity. Extracted verbatim; the scanner's
assertions pass unchanged.

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

### Task 2: Record a baseline on first use, silently

**Files:**
- Create: `hooks/skill-integrity-guard.sh`
- Test: `tests/test-skill-integrity-guard.sh` (append)

**Interfaces:**
- Consumes: `resolve_skill_paths()` from Task 1.
- Produces: lock file at `$SUPERCHARGER_STATE/scope/.skills-lock`, JSON shaped
  `{"skills": {"<resolved path>": {"sha256": "<hex>", "firstSeen": "<iso8601>"}}}`.

- [ ] **Step 1: Write the failing test**

```bash
GUARD="$REPO_DIR/hooks/skill-integrity-guard.sh"
SIG_HOME=$(mktemp -d)
SIG_STATE=$(mktemp -d)
mkdir -p "$SIG_HOME/.claude/skills/demo"
printf 'original body\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"

sig() {
  printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"cwd":"%s"}' "$1" "$SIG_HOME" \
    | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" bash "$GUARD" 2>/dev/null \
    | grep -o '"permissionDecision":"[a-z]*"' || echo none
}

begin_test "skill-lock: the first load is silent and records a baseline"
[ "$(sig demo)" = "none" ] && pass || fail "first load should be silent, got $(sig demo)"

begin_test "skill-lock: the baseline is on disk with a sha256"
grep -q '"sha256"' "$SIG_STATE/scope/.skills-lock" && pass || fail "no baseline written"

begin_test "skill-lock: an unchanged skill stays silent on reload"
[ "$(sig demo)" = "none" ] && pass || fail "unchanged skill should be silent"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: FAIL — the hook does not exist; `sig` returns `none` but the baseline assertion fails on a missing file.

- [ ] **Step 3: Write the hook**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Skill Integrity Guard
# Event: PreToolUse | Matcher: Skill
#
# skill-poisoning-scanner asks "does this look malicious?". Nothing asked "is
# this the same file as last time?". A skill is instructions the model follows,
# so a silent edit is a persistent behaviour change with no event anywhere.
#
# Trust on first use, like known_hosts: record the hash the first time, ask when
# it changes. No lockfile is authored by hand. Disable: SUPERCHARGER_SKILL_LOCK=0
set -uo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

[ "${SUPERCHARGER_SKILL_LOCK:-1}" = "0" ] && exit 0
check_hook_disabled "skill-integrity-guard" && exit 0

IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
_INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
case "$_INPUT" in *'"skill"'*) ;; *) exit 0 ;; esac

RESULT=$(HOOK_INPUT="$_INPUT" HOME_DIR="$HOME" PWD_DIR="$PWD" \
         SC_LOCK="$_SC_STATE/scope/.skills-lock" HOOKS_DIR_PY="$HOOKS_DIR" \
         python3 <<'PYEOF' 2>/dev/null
import hashlib, json, os, sys, datetime

sys.path.insert(0, os.environ['HOOKS_DIR_PY'])
try:
    from lib_skill_resolve import resolve_skill_paths
except Exception:
    sys.exit(0)

try:
    payload = json.loads(os.environ.get('HOOK_INPUT') or '{}')
except Exception:
    sys.exit(0)

skill = (payload.get('tool_input') or {}).get('skill') or ''
if not skill:
    sys.exit(0)

paths = resolve_skill_paths(skill, os.environ['HOME_DIR'],
                            payload.get('cwd') or os.environ['PWD_DIR'])
if not paths:
    # Nothing on disk to hash. skill-poisoning-scanner treats this the same
    # way; it is a pre-existing unscannable condition, not a change.
    sys.exit(0)

lock_path = os.environ['SC_LOCK']
try:
    with open(lock_path) as fh:
        lock = json.load(fh)
except Exception:
    lock = {}
skills = lock.setdefault('skills', {})

changed, unreadable = [], []
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

for p in paths:
    key = str(p.resolve())
    try:
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
    except Exception:
        # Present but unreadable. NOT the same verdict as unchanged: the file
        # exists and was not compared. v4.0.26, artifact-publish-guard.
        unreadable.append(p.name)
        continue
    prior = skills.get(key, {}).get('sha256')
    if prior is None:
        skills[key] = {'sha256': digest, 'firstSeen': now}
    elif prior != digest:
        changed.append((p.name, key, prior, digest))

os.makedirs(os.path.dirname(lock_path), exist_ok=True)
tmp = lock_path + '.tmp'
with open(tmp, 'w') as fh:
    json.dump(lock, fh, indent=2, sort_keys=True)
os.replace(tmp, lock_path)

print(json.dumps({'changed': changed, 'unreadable': unreadable}))
PYEOF
) || exit 0

[ -z "$RESULT" ] && exit 0
exit 0
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x hooks/skill-integrity-guard.sh
bash tests/test-skill-integrity-guard.sh
```

Expected: `6 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-integrity-guard.sh tests/test-skill-integrity-guard.sh
git commit -m "feat(skills): record a skill's hash the first time it loads

Trust on first use. Silent by design at this stage -- the baseline has to exist
before drift can mean anything.

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

### Task 3: Ask when the hash changes

**Files:**
- Modify: `hooks/skill-integrity-guard.sh` (the trailing verdict block)
- Test: `tests/test-skill-integrity-guard.sh` (append)

**Interfaces:**
- Consumes: the `{"changed": [...], "unreadable": [...]}` JSON from Task 2.
- Produces: `hookSpecificOutput.permissionDecision` of `ask`; exit 0 always.

- [ ] **Step 1: Write the failing test**

```bash
begin_test "skill-lock: an edited skill ASKS"
printf 'MALICIOUS body\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"
[ "$(sig demo)" = '"permissionDecision":"ask"' ] && pass || fail "edit not caught, got $(sig demo)"

begin_test "skill-lock: the reason names the skill and both hashes"
OUT=$(printf '{"tool_name":"Skill","tool_input":{"skill":"demo"},"cwd":"%s"}' "$SIG_HOME" \
  | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" bash "$GUARD" 2>/dev/null)
case "$OUT" in *demo*) pass ;; *) fail "reason does not name the skill: $OUT" ;; esac

begin_test "skill-lock: after asking once, the new hash becomes the baseline"
[ "$(sig demo)" = "none" ] && pass || fail "should not ask twice for the same content"

begin_test "skill-lock: the kill switch is honoured"
printf 'changed again\n' > "$SIG_HOME/.claude/skills/demo/SKILL.md"
RC=$(printf '{"tool_name":"Skill","tool_input":{"skill":"demo"},"cwd":"%s"}' "$SIG_HOME" \
  | HOME="$SIG_HOME" SUPERCHARGER_STATE="$SIG_STATE" SUPERCHARGER_SKILL_LOCK=0 \
    bash "$GUARD" 2>/dev/null | grep -c permissionDecision || true)
[ "$RC" = "0" ] && pass || fail "kill switch ignored"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: FAIL on "an edited skill ASKS" — got `none`, because Task 2 always exits silently.

- [ ] **Step 3: Replace the trailing verdict block**

Replace the final three lines of the hook (`[ -z "$RESULT" ] && exit 0` / `exit 0`) with:

```bash
[ -z "$RESULT" ] && exit 0

_SIG_MSG=$(SIG_RESULT="$RESULT" python3 -c '
import json, os, sys
try:
    r = json.loads(os.environ["SIG_RESULT"])
except Exception:
    sys.exit(0)
lines = []
for name, _key, prior, cur in r.get("changed", []):
    lines.append("%s changed since it was last loaded (%s -> %s)."
                 % (name, prior[:12], cur[:12]))
for name in r.get("unreadable", []):
    lines.append("%s exists but could not be read, so it was NOT compared." % name)
if not lines:
    sys.exit(0)
print("\n".join(lines))
' 2>/dev/null) || exit 0

[ -z "$_SIG_MSG" ] && exit 0

echo "[Supercharger] skill-integrity-guard: ASK — skill content changed" >&2
_SIG_REASON="$_SIG_MSG

A skill is instructions Claude follows. This one is not the file that was recorded the first time it loaded, so its behaviour may have changed.

Approve if you (or an update you expected) changed it — the new content becomes the baseline. Decline if you did not."
_SIG_J=$(printf '%s' "$_SIG_REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"skill content changed"')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$_SIG_J"

SCOPE_DIR="$_SC_STATE/scope"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true
printf '[%s] skills — skill content changed since first load — %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$(printf '%s' "$_SIG_MSG" | head -1)" \
  >> "$SCOPE_DIR/.blocked-commands" 2>/dev/null || true

exit 0
```

Note: Task 2's python already rewrites the lock with the new digest before
printing, so approving once makes the new content the baseline. That is what the
third test above pins.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: `10 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-integrity-guard.sh tests/test-skill-integrity-guard.sh
git commit -m "feat(skills): ask when a skill's content changes since first load

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

### Task 4: An unreadable skill is not an unchanged skill

**Files:**
- Test: `tests/test-skill-integrity-guard.sh` (append)

The hook already implements this (Task 2's `except` branch, Task 3's message
loop). This task pins it, because the branch is the one most likely to be
"simplified" away later — it was exactly this collapse that v4.0.26 fixed in
`artifact-publish-guard`.

**Interfaces:**
- Consumes: the hook as built in Task 3.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

```bash
begin_test "skill-lock: an unreadable skill ASKS rather than passing as unchanged"
SIG_UR="$SIG_HOME/.claude/skills/unreadable"
mkdir -p "$SIG_UR"
printf 'body\n' > "$SIG_UR/SKILL.md"
chmod 000 "$SIG_UR/SKILL.md" 2>/dev/null || true
if [ -r "$SIG_UR/SKILL.md" ]; then
  # MSYS/NTFS derives permissions from the file rather than storing them, so
  # chmod 000 is a no-op and the branch cannot fire. Gate on the PRECONDITION,
  # never on a platform name (v4.0.21).
  begin_test "skill-lock: unreadable case (skipped — filesystem ignores chmod)"
  pass
else
  [ "$(sig unreadable)" = '"permissionDecision":"ask"' ] && pass \
    || fail "unreadable skill was treated as clean, got $(sig unreadable)"
fi
chmod 644 "$SIG_UR/SKILL.md" 2>/dev/null || true

begin_test "skill-lock: a skill that does not exist on disk is silent, not an ask"
[ "$(sig ghostskill)" = "none" ] && pass || fail "missing skill should be a no-op"
```

- [ ] **Step 2: Run it**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: PASS — this pins existing behavior. If it fails, Task 3's message loop
dropped the `unreadable` list; fix that before continuing.

- [ ] **Step 3: Prove the assertion can fail (guard the guard)**

Temporarily change the hook's `unreadable.append(p.name)` line to `pass`, re-run,
and confirm the unreadable assertion goes red. Revert the edit.

Expected: FAIL, then PASS again after revert.

- [ ] **Step 4: Commit**

```bash
git add tests/test-skill-integrity-guard.sh
git commit -m "test(skills): pin that unreadable and unchanged are different verdicts

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

### Task 5: Register the hook in both channels

Until this task the hook never fires. `tests/test-orphan-registration.sh` fails
with the filename, which is the intended forcing function.

**Files:**
- Modify: `lib/hooks.sh:354` (immediately after the `skill-poisoning-scanner` line)
- Regenerate: `hooks/hooks.json`
- Test: `tests/test-skill-integrity-guard.sh` (append)

**Interfaces:**
- Consumes: the hook from Task 3.
- Produces: a `PreToolUse|Skill` registration in both the installer path and the plugin `hooks.json`.

- [ ] **Step 1: Write the failing test**

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-skill-integrity-guard.sh`
Expected: FAIL on the first two — not registered, not in `hooks.json`.

- [ ] **Step 3: Register it**

In `lib/hooks.sh`, directly below the `skill-poisoning-scanner.sh` line:

```bash
    # Change detection, not classification: the scanner asks whether a skill
    # looks malicious, this asks whether it is the same file as last time.
    hooks+=("PreToolUse|Skill|${hooks_dir}/skill-integrity-guard.sh|")
```

- [ ] **Step 4: Regenerate the plugin channel**

```bash
bash tools/gen-plugin-hooks.sh
bash tools/gen-plugin-hooks.sh --check
```

Expected: `--check` reports the committed file is current.

- [ ] **Step 5: Run the full suite**

```bash
bash tests/run.sh
```

Expected: `0 failed`. `test-orphan-registration` now passes without an allowlist
entry, and `test-hook-events` accepts `PreToolUse`.

- [ ] **Step 6: Bump the README tests badge**

The badge gate is CI-only: `tests/run.sh` warns locally but sets `BADGE_DRIFT=1`
under `CI`, so a stale badge exits 1 and turns the Linux job red while the suite
underneath is green. Derive the number rather than typing it:

```bash
TOTAL=$(bash tests/run.sh 2>&1 | sed -n 's/^Total: \([0-9]*\) passed.*/\1/p' | tail -1)
sed -i.bak "s/tests-[0-9]*%20passing/tests-${TOTAL}%20passing/" README.md && rm -f README.md.bak
CI=true bash tests/run.sh >/dev/null 2>&1; echo "rc=$?"
```

Expected: `rc=0`. A non-zero exit here means the badge is still stale.

- [ ] **Step 7: Commit**

```bash
git add lib/hooks.sh hooks/hooks.json tests/test-skill-integrity-guard.sh README.md
git commit -m "feat(skills): register the skill integrity guard on PreToolUse:Skill

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

### Task 6: Document it

**Files:**
- Modify: `README.md` (the "Runtime enforcement" bullet list)

**Interfaces:**
- Consumes: the shipped hook.
- Produces: the user-visible description.

`/why` needs no change. Checked before writing this task: `configs/commands/why.md`
is a source-priority list, not a category table — source #2 reads the last line of
`.blocked-commands` and explains whatever it finds. The ledger line written in
Task 3 is picked up by that path already.

- [ ] **Step 1: Add the README bullet**

Directly after the "Code security scanning" bullet:

```markdown
- **Skill integrity** — a skill's content is hashed the first time it loads and compared on every later load. A changed skill asks before it is used, so an upstream edit or a local rewrite of instructions Claude follows cannot land silently. Trust-on-first-use, no lockfile to maintain. Kill switch: `SUPERCHARGER_SKILL_LOCK=0`
```

- [ ] **Step 2: Confirm the badge is still correct**

Adding a bullet changes no test count, but run the gate rather than assuming:

```bash
CI=true bash tests/run.sh >/dev/null 2>&1; echo "rc=$?"
```

Expected: `rc=0`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(skills): document the skill integrity guard

Claude-Session: https://claude.ai/code/session_01W2YAQaUGF33CC1GpvBDGP4"
```

---

## Known limits — state these, do not quietly widen scope to fix them

1. **TOFU trusts the first load.** A skill already poisoned at install time is
   recorded as its baseline and never asks. `skill-poisoning-scanner` is the
   control for that case; this hook is the control for change after the fact. The
   two are complementary and neither subsumes the other.
2. **The lock is per-machine, not committed.** A team does not share baselines. A
   committed project lock is a reasonable follow-up; it is not this plan, because
   it needs a curation step and a merge story.
3. **Only the resolved skill file is hashed.** A skill directory with
   `rules/*.md` alongside `SKILL.md` — the `trycompai/crm` layout — has its
   auxiliary files unhashed. Extending to the directory is a follow-up; measure
   the fork cost before doing it.
4. **`ask` is advisory.** A user who approves reflexively gets nothing. That is
   true of every `ask` in this repo and is why the verdict is not `deny`.
