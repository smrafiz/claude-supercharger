## Handoff — claude-supercharger — 2026-09-05

Baseline for this session: `62f2010` (v4.0.26). 16 commits on top, all pushed, tree clean.
Commit messages carry the reasoning — this brief covers only what they cannot.

### Done
- Repo hygiene: removed tracked empty file `y`, plus untracked empty dirs `=/` and `nonexistent/`.
- Test-suite leak fixed (`a1ebe5e`) — the suite no longer writes stray dirs into the repo root.
- Hook-event valid set fixed (`743cee2`) — three working hooks were being reported as inert.
- `/security` self-grading rubric, 13 checks (`a190322`, `9cc2a4e`) — `configs/commands/security.md`.
- Skill Integrity Guard shipped end to end, all 6 plan tasks (`22c0bca`..`323d303`).
- Windows CI root cause identified and narrowed twice (`d9f6df6`, `a7cac83`, `8eef875`).

### In Flight
- **CI run `33906311017`** — running at handoff (Windows takes ~70min). First run carrying
  the skill-integrity guard AND the round-2 stdout instrumentation. A background watch was
  set in the previous session and does NOT survive it; re-check manually.
- **Windows failure, still open.** One assertion, `test-artifact-publish-guard.sh`.
  Not a regression from this session's work — it has been red since v4.0.26.

### Decisions Made
- **Skill lock uses trust-on-first-use, not a committed lockfile**: `trycompai/crm` pins
  skills by hash in a hand-authored `skills-lock.json`. A curation step nobody performs is
  a guard nobody has, so the guard records what it sees on first load instead. Cost: it
  trusts a skill already poisoned at install (poisoning-scanner remains the control there).
- **`ask`, not `deny`, on skill drift**: matches `lockfile-integrity-guard`. A legitimate
  skill edit is common; denying trains people to disable the guard.
- **Rubric inlined in the command, not a separate `eval.md`**: a slash command has no bundle
  dir, so a second file needs install plumbing plus plugin packaging across two runtimes to
  deliver prose the command can already carry.
- **Resolver identity is `(st_dev, st_ino)`, not a resolved path string** — see Measurements.
- **`_msys` normalisation moved INSIDE `resolve_skill_paths`** so a second consumer cannot
  forget it. Idempotent, no-op off Windows; the scanner's existing call-site call still works.

### What Failed
- **Windows theory 1 — "python wrote fixtures to the wrong side of the MSYS boundary"**
  (`d9f6df6`). Plausible, wrong. The `native_path` fix landed and the precondition assertion
  added in the same commit PASSED on Windows while the deny assertion still failed.
- **Windows theory 2 — "fixtures exist but are empty"** (`a7cac83`). Also wrong. Round-1
  instrumentation returned `bytes=121`, correct content.
- **My own precondition assertion was too weak** — it checked the fixtures *existed*, not that
  they had bytes. An empty file would have passed it while sending the guard down its
  `[ -z "$CONTENT" ]` branch. Same collapse the guard was fixed for in v4.0.26; I reintroduced
  it in the test. Now asserts bytes and content.
- **First sibling scan for the MSYS bug returned 60+ false positives** — the grep matched reads
  as well as writes. A tightened scan found exactly one real sibling. Do not trust the loose form.

### Blockers
- **Windows fix is blocked on CI evidence, not on analysis.** No Git Bash available locally;
  each hypothesis costs a ~70min CI round trip. Round 2 instrumentation is already pushed and
  will answer it. Do not attempt a fix before reading `stdout_bytes` from the artifact.

### Files Touched
- `hooks/lib_skill_resolve.py` (new): shared skill resolver. Sole owner of candidate dirs + globs.
- `hooks/skill-integrity-guard.sh` (new): TOFU hash comparison, `PreToolUse|Skill`.
- `hooks/skill-poisoning-scanner.sh`: resolution logic removed, now imports the shared resolver.
- `lib/hooks.sh` (~line 355): registration. `hooks/hooks.json` regenerated.
- `tests/test-skill-integrity-guard.sh` (new): 16 assertions across the 6 tasks.
- `tests/test-artifact-publish-guard.sh`: fixture fix + two rounds of Windows instrumentation.
- `tests/test-hook-events.sh`: valid-event set now derived from the binary's event registry.
- `tests/helpers.sh`: `PYTHONDONTWRITEBYTECODE=1`.
- `tests/test-install.sh`: hook count 158 → 159.
- `configs/commands/security.md` + generated `commands/security.md`: the 13-check rubric.
- `docs/SKILLS-LOCK-PLAN.md` (new), `docs/HOOKS.md` (regenerated), `README.md` (badge 5305 + bullet).

### Resume With
Check CI run `33906311017` on smrafiz/claude-supercharger. Download its artifact
(`gh run download`, never the step log) and read the `stdout_bytes=` / `stdout=` fields in the
`test-artifact-publish-guard` FAIL line — that decides the last open Windows bug. Also confirm
the new skill-integrity guard passed on Git Bash, since this is its first Windows run.

### Start With
`/why` is not needed — nothing fired locally. Run the CI check above first; if the artifact
shows a new failure in `skill-lock:` assertions, use `/stuck` rather than iterating, because
each Windows hypothesis costs ~70 minutes.

---

### Measurements
- **Windows round-1 diagnostic** (run `33896901822`, `test-artifact-publish-guard.sh:383`):
  `bytes=121  head='<html>sk-ant-api03-DDDDDDDDDDD'  rc=2`
  `stderr='[Supercharger] artifact-publish-guard: BLOCKED publish — secret in artifact'`
  Interpretation: the guard DENIES correctly on Git Bash. Only the stdout `permissionDecision`
  JSON fails to arrive. Publish is blocked either way, so the live impact is a degraded
  *reason*, not unguarded egress. **This is measured, not assumed.**
- **Claude Code hook events**: the binary's event registry holds **33** events
  (CC 2.1.260). Deriving from `execute<Event>Hooks` symbols yields only **25** — a proper
  subset. Supercharger registers 28 of the 33.
- **Skill resolver double-scan**: `resolve_skill_paths('demo', ...)` returned **2** paths for
  **1** file on macOS — `SKILL.md` and `skill.md` globs both match on a case-insensitive
  filesystem and `Path.resolve()` preserves the glob's casing. Every skill has been scanned
  twice by `skill-poisoning-scanner` on macOS/NTFS since those globs were written.
- **`/security` rubric on a seeded fixture** (3 real bugs, 4 planted noise items):
  7 findings → 3. Killed an allowlisted `ORDER BY`, an `eval()` over a module constant, and a
  rate-limiting line failing the portability test; merged two SQLi findings to one root cause.
  The completeness check then found a **4th real bug** (IDOR) that both earlier passes missed.
  Caveat: I knew where the plants were, so this measures that the checks FIRE, not a hit rate.
- **Suite**: 5287 → 5305 passing, 0 failed. Badge gate verified with `CI=true` → `rc=0`.

### Rejected — do not rebuild
- **Committed per-project skills lockfile** (the `trycompai/crm` shape): rejected for v1 because
  it needs a curation step and a merge story. Listed as a follow-up in `docs/SKILLS-LOCK-PLAN.md`.
- **Adding the three "invalid" events to a known-bad list** in `test-hook-events.sh`: they are
  valid; the test's extraction was the subset. Deriving from the registry is the fix.
- **Adding the Windows failure to `KNOWN` in `.github/workflows/ci.yml`**: `KNOWN = set()` and the
  list was driven to zero deliberately. Fix the failure, never exempt it.
- **Extending the `/security` rubric to `/audit` and `/multi-review` now**: piloted on
  `/security` only. Spreading an unproven pattern is how ceremony accumulates.
- **ASD-STE100 writing standard from `trycompai/crm`**: largely duplicates `economy.md`'s
  minimal tier. Cosmetic.

### Dead ends
- **Searching the tree for the `=` dir cause by grep** (`==` assignment typos, `${var#--flag}`
  prefix strips, `mkdir` with a stray `=`): all produced nothing. The cause was
  `$HOOK_DUMMY` — a variable defined NOWHERE, so no grep for a definition could find it.
  Empirical bisect (run each test file, check for the dir) found it in one pass. Prefer the
  bisect immediately next time.
- **Loose sibling scan for the MSYS write bug**: `grep "open(sys.argv"` matched 60+ files
  including pure reads. Useless. The tightened form (python3 `-c` opening for WRITE with a
  shell temp var as argv, no `native_path`) found exactly one.
- **`gh run view --log` mid-run**: GitHub withholds logs until a run completes. Only
  `gh run download` of the uploaded artifact works, and only after completion.

### Open questions
- **Why does this hook's stdout not reach the pipeline on Git Bash?** UNVERIFIED, two branches:
  (a) `stdout_bytes=0` → the `printf` never ran, so the shell left between the stderr echo
  (`artifact-publish-guard.sh:119`) and the JSON printf (`:125`) — suspect the `REASON_JSON`
  command substitution; (b) `stdout_bytes>0` → the bytes exist and the pipeline or `grep -o`
  is eating them, suspect CRLF or encoding. Round-2 instrumentation reports both. Different
  fixes; do not guess.
- **Does the skill-integrity guard work on Git Bash?** UNVERIFIED — never run there. Risk points:
  the `_msys(HOOKS_DIR_PY)` import path, and the `chmod 000` test, which self-skips where the
  filesystem ignores the bit.
- **Is the double-scan fix a behaviour change for the scanner on Windows?** VERIFIED FALSE as a
  regression on macOS/Linux (all 11 scanner assertions pass). Unverified on NTFS.

### Reproduce
```bash
# The Windows artifact — the ONLY reliable source. Never the step log.
gh run download <run-id> --repo smrafiz/claude-supercharger
grep "FAIL" */win-suite.log | grep -v PASS

# The real Claude Code event set (33, not the 25 the dispatcher symbols give)
strings "$(python3 -c 'import os;print(os.path.realpath("'"$(command -v claude)"'"))')" \
  | grep -oE '[A-Za-z]+:\{summary:"' | sed 's/:{summary:"//' | grep -E '^[A-Z]' | sort -u

# Reproduce the resolver double-scan (pre-fix behaviour, on a case-insensitive FS)
T=$(mktemp -d); mkdir -p "$T/.claude/skills/demo"; echo body > "$T/.claude/skills/demo/SKILL.md"
python3 -c "import sys;sys.path.insert(0,'hooks');from lib_skill_resolve import resolve_skill_paths as r;print(len(r('demo',sys.argv[1],sys.argv[1])))" "$T"

# The badge gate that is CI-only and silently red otherwise
CI=true bash tests/run.sh >/dev/null 2>&1; echo "rc=$?"
```
Kept probes: `/security` rubric fixture at
`<scratchpad>/evaltest/app.py` (3 real bugs + 4 planted noise items; scratchpad is
session-scoped and will be gone — recreate from the Measurements entry if needed).
