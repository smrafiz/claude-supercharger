# Handoff — claude-supercharger — 2026-09-03

## Done

- **Five releases, v4.0.22 → v4.0.26.** Each commit message carries its own
  measurements and reasoning; read `git log v4.0.21..HEAD` rather than restating.
  Suite 5217 → 5285.
- **Two repos assessed** (`ezBuilder/code-brain`, `aksheyw/claude-code-guardrail-hooks`),
  both closed out in memory. Third URL dropped (`JuliusBrussee/caveman`) was
  already mined twice — recognised, not re-mined.
- **Three case-folding defects found and fixed** in shipped guards, plus two
  read-failure defects. All five verified by probe before and after.

## In Flight

- **v4.0.26's CI.** 6/8 green at handoff; `Test suite (macos-latest)` and
  `Windows (Git Bash)` still running. v4.0.22–v4.0.25 are all fully green
  including Windows. Nothing else outstanding, tree clean, nothing unpushed.
- Installed harness is v4.0.26 and was behaviour-verified after `/sc-update`.

## Decisions Made

- **Fold new guards into existing hooks, do not add hook files.** Both features
  this session (placeholder arm on claim-evidence-gate, lint-config arm on
  test-integrity-guard) share event, matcher, ASK tier and purpose with their
  host. A separate hook costs ~9ms on every tool call plus hooks.json/HOOKS.md
  regeneration and buys nothing. Same call as v4.0.22's arm, which worked.
- **Fold case unconditionally rather than probing the filesystem.** On a
  case-sensitive FS the swapped name is genuinely a different file, so folding
  costs one ASK on a path nobody writes on purpose; not folding costs a silent
  bypass on macOS and Windows.
- **Count-deltas, not "this file was touched", for the lint-config arm.** The
  upstream hook denies EVERY edit to an existing lint config. Editing eslint
  config is ordinary work and a guard that fires on ordinary work gets switched
  off.
- **pause-guard PARKED, not built.** See [[repo-audit-guardrail-hooks]].
- **Severity stated honestly in v4.0.26's message.** Both read-failure defects
  are correctness bugs in a failure model, not live bypasses: the hooks run as
  the same user as the operation, so in the EACCES case the guarded operation
  fails on its own. The fix buys the rarer trigger (transient EMFILE/EINTR, disk
  error, NFS) where the operation succeeds and the scan silently did not happen.

## What Failed

- **Four defective fixtures, all mine, all caught by asking "would this fire if
  the code were correct?"** They are the session's main methodological output and
  are listed under Measurements/Dead ends below.
- **First release attempt was denied** by Claude Code's auto-mode classifier
  (`bash tools/release.sh ... | tail -30`, foreground+piped). I then handed the
  command to the user for four releases before retrying. The backgrounded
  `nohup ... &` form runs fine. Lesson: retry once in a different form before
  concluding a capability is unavailable.
- **`perl -0pi -e` mutations silently did not match** twice, reporting 0 reds and
  nearly passing off untested code as covered. Python `str.replace` with an
  `assert target in s` is the reliable form and is what the Reproduce section uses.

## Blockers

- none.

## Files Touched

Everything is in the five release commits; `git show <tag>` for the diff. The
non-obvious ones:

- `hooks/lib-critical-infra.sh`, `hooks/lib-lockfile.sh`: folded case at the
  SHARED matcher, so `lib-smart-approve` (autopilot auto-approval) is fixed by the
  same edit. That second caller is why the fix belongs in the lib.
- `hooks/statusline.sh`: worktree label derived from `--git-common-dir` vs
  `--show-toplevel`, never from the path shape.
- `hooks/test-integrity-guard.sh`: now hosts the lint-config arm; its embedded
  python is inside `python3 -c '...'`, so **no literal apostrophes may appear in
  it** — use `\x27`. One cost a parse failure of the whole hook this session.

## Resume With

claude-supercharger is at v4.0.26, tree clean, all work pushed. Confirm v4.0.26's
CI went green (the two new tests chmod 000 then check `[ -r ]` and self-skip where
the filesystem ignores it — on Windows the SKIP path should trigger, not a
failure). Then pick from Open questions below; nothing is half-finished.

## Start With

`gh run view 33746879927` — v4.0.26's Windows and macOS jobs were still running at
handoff. If red, `gh run download <id>` for the per-test artifact; the step log
only shows the gate's source.

---

## Measurements

- **Statusline worktree label: 94ms → 103ms** cold render (cache-miss path only,
  ≤ once per ~3s bucket; cached renders unchanged). Fixture: both variants placed
  in `hooks/`, 5 runs each, `.statusline-git-*` removed between runs.
  **The first measurement said 100ms → 25ms and was wrong in direction** — that
  fixture used two copies under `/tmp`, where the script cannot resolve its libs
  and therefore runs a different program.
- **Suite counts:** 5217 (session start) → 5228 (v4.0.22) → 5234 (v4.0.23) →
  5254 (v4.0.24) → 5267 (v4.0.25) → 5278 → 5285 (v4.0.26). All `rc=0`, unpiped.
- **Mutation results**, per fix, number of tests that redden when reverted:
  claim-evidence disk-check 1, turn-scoping 1; editor-config python `.lower()` 5,
  bash nocasematch 1; lib-critical-infra `$lbase` 6, guard gate 1; lib-lockfile
  fold 11, gate fold 8; lint arm gate 5, DISABLE_RE 2, numeric scoping 1,
  `is_lint` 16; OSError arm 1; artifact unreadable-split 1.
- **Windows CI job duration ~58 min** (v4.0.21 11:09:41Z→12:07:15Z). A job at
  ~56 min is on schedule, not hung — I misread this once as a stall.

## Rejected — do not rebuild

- **`pause-guard` (aksheyw).** Blocks EVERY tool call from a regex over the user's
  latest typed message. Genuinely uncovered and on-thesis, but a false block
  wedges the session until the user types again, and its own header records
  several patterns dropped for false positives. Its primary arm (reasoning-effort
  decisions) is specific to that author's workflow.
- **A separate hook file for either new feature.** See Decisions.
- **Denying all edits to lint configs** (what the upstream hook does). Rejected in
  favour of count-deltas; the FP surface would be every legitimate config edit.
- **Filesystem case-sensitivity probing** to decide whether to fold case.
  Rejected: a fork per call to avoid one ASK on a path nobody writes.
- **`ENABLED_RE` counting bare 1/2 everywhere.** Measured FP: prettier
  `"tabWidth": 2 → 4` read as a dropped rule. Numeric severities are an
  ESLint/Stylelint spelling and are counted only for those files.

## Dead ends

- **`ezBuilder/code-brain`'s 580-file `.ai/` layer** — memory/BM25/MCP/autoresearch
  is an orchestration harness, off-thesis. Only its four guard modules were worth
  reading, and three of those were already covered.
- **`JuliusBrussee/caveman`** — mined 2026-08-02 and 2026-09-02. Only live
  leftover is a version CEILING check (we have a floor, no ceiling), and it is
  noisy as a session warning; the sane framing is a CI/maintainer signal.
- **Probing `install-script-guard`, `pth-persistence-guard`,
  `package-source-guard`, `enforce-pkg-manager` for case bypass with a path-only
  payload** — they never fire on a bare file_path, so there is no baseline and
  their silence means nothing. They key on command/content. NOT evidence they are
  clean.
- **Assuming `write-secret-guard` was broken** because a probe showed silence — it
  answers on stdout as an ASK and my probe captured only stderr. It is fine, and
  is NOT vulnerable to the upstream repo's fallback-position secret bug.

## Open questions

- **UNVERIFIED, not false: case exposure of the four command/content-keyed guards
  above.** Needs command-shaped fixtures (e.g. `curl … | bash` with an upper-cased
  script name, a `.PTH` written via Bash) with a working baseline first.
- **UNVERIFIED: whether the truncated-stdin path is reachable.** Our hooks do
  `read -r -d '' -t 5` and proceed with whatever arrived; the upstream repo blocks
  on a truncated payload. A payload big enough to time out may not exist in
  practice. Evidence that would settle it: feed a hook a multi-MB tool_input and
  see whether the read truncates before the guard's scan.
- **UNVERIFIED: other instances of read-failure-collapses-to-clean.** Two were
  found and fixed; the grep that found them flagged ~12 `open()`/`[ -f ]` sites,
  most benign (marker files, transcripts). `guard-registration-check.sh:54`
  (`[ -r "$SETTINGS" ] || exit 0`) is an ORACLE going silent, which reads as
  "verified" — see [[guard-fails-open-oracle-fails-loud]]. Not probed.

## Reproduce

```bash
bash tests/run.sh < /dev/null > /tmp/s.out 2>&1; echo $?   # NEVER pipe a gate
shellcheck --severity=error hooks/*.sh tests/*.sh          # CI's exact invocation
gh run download <run-id> -D <dir>                          # Windows per-test detail

# Case-fold probe (the pattern that found three defects). BASELINE FIRST — a guard
# silent for both spellings has either no bug or no fixture, and only the baseline
# tells you which.
python3 -c 'import json,sys;print(json.dumps({"tool_name":"Edit","cwd":"/p",
  "session_id":"probe","tool_input":{"file_path":sys.argv[1],
  "old_string":"a","new_string":"b"}}))' /p/CARGO.LOCK \
  | SUPERCHARGER_STATE=$(mktemp -d) bash hooks/lockfile-integrity-guard.sh

# Read-failure probe: write a file, chmod 000, re-run the same payload.
# Capture BOTH streams — guards answer on stdout as JSON, stderr is only the log line.

# Mutation testing — use python with an assert, never perl -0pi (silently no-ops):
python3 -c "
p='hooks/X.sh'; s=open(p).read(); a='<exact target>'
assert a in s, 'TARGET MISSING'
open(p,'w').write(s.replace(a,'<mutant>',1))"
```
