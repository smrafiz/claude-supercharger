## Handoff — claude-supercharger — 2026-11-16 (deep)

### Done
- **PR A merged, #315 → d957a449.** cc-safety-net delta: shell/-c/trap/git/xargs spellings. Added this
  session: a linear quote walk (`hooks/cmd-normalize.sh`, skips masking over 4 KB), a backslash in a
  bracket class fixed in the `-c` body rule (`hooks/safety.sh`), and single-quoted `$( )` in a `-c`
  body now ASKS, emitted last so any deny wins (`_SHC_ASK`).
- **PR B merged, #316 → bc85c97b.** git/interpreter/env spellings. Added this session: the quoted-path
  gate glob, which was quadratic, became two one-class globs; the timing test now uses 12,000 spans.
- **PR C opened, #317 (376e92b3).** Dropper, cloud metadata, interpreter fetch, unshare. N2 was
  removed at the user's call.
- All three sn worktrees removed at the user's request; branches kept (see Worktrees).
- Engineering notes: `docs/HOOK_AUTHORING.md` § "Notes from 2026-11-16" (uncommitted, on master).
- Memory: see the memory pass in the session reply.

### In Flight
- **#317 (C):** full CI run 43864806536 in progress at handoff; PR checks so far 8 success, 2 skipped.
  Merge: `gh pr merge 317 --squash --delete-branch --match-head-commit 376e92b3…` (full sha:
  `git rev-parse origin/feat/sn-dropper-metadata-classes`).
- **`fix/sc-security-scanner-fp`** c7103a5d, LOCAL ONLY, 2 commits on old master dd9a77d9. The
  `/sc-security` skill-poisoning FP: a command file byte-identical to a shipped one (hash in
  `configs/commands-shipped.txt`) keeps only CRITICAL findings; CRLF folded; the installer deploys
  the manifest (`lib/hooks.sh`). New test `tests/test-shipped-command-scan.sh` (5/5, fails with the
  fix removed). Still needs: rebase, full suite, push, PR, CI.
- **`perf/normalize-c-locale`** 95346e9a, LOCAL ONLY, 1 commit: `local LC_ALL=C` at the top of
  `normalize_cmd`. Still needs: rebase, re-measure on its own payload, full suite, PR, CI.
- Uncommitted on master: `docs/HOOK_AUTHORING.md`, this brief, `.claude/handoff.md`.

### Decisions Made
- **N2 dropped** (user, 2026-11-16): it scanned a heredoc-written script run in the same command.
  Memory `n2-heredoc-run-dropped.md` has the evidence.
- **Single-quoted `$( )` in a `-c` body asks, not denies**: the code is visible and runs in the inner
  shell. Master used to allow most of these, because it read only the first quoted piece.
- **Over 4 KB the quote walk masks nothing**: this scans more text, never less (a `shortcut:` comment
  in the code). Upgrade to a linear awk walk if the FP log shows over-blocking on huge commands.
- Release **4.4.7 held**: release only on the user's word.

### What Failed
- Replacing `'` with a space to speed up the walk: it broke matching (`r'm'` became `r m`). The walk
  is skipped over 4 KB instead.
- The first CRLF test for the scanner could not fail (`read_text` already folds CRLF); rewritten to
  call `scan_text` directly.
- The 6000-span timing test with a 10 s ceiling passed locally with a 4 s quadratic glob present;
  CI's runner (14 s) caught it. Fixed by growing the payload to 12,000.
- `pkill -f "until grep -q '\^fpexit='"` did not match the waiter loops (escaped `^`), so two
  duplicate notifications fired.
- The commit guard rejected a multi-line `git commit -m`; `-F <file>` passes.

### Blockers
- none. Next steps wait only on CI (#317).

### Worktrees
- none: only the main checkout (master bc85c97b). Removed on the user's request:
  `agent-ac13…` (A), `agent-af09…` (B), `agent-a473…` (C), `perf-c-locale`, `sc-security-fp`.
  None had uncommitted changes.

### Files Touched
- `hooks/cmd-normalize.sh`: quote walk over 4 KB skipped (A); quoted-path gate globs (B); C's N2 code
  reverted to master.
- `hooks/safety.sh`: `-c` body rule (bracket class, single-quote ask, `_SHC_ASK` emitted last) (A).
- `tests/test-shell-pipe-normalizer.sh`: `verdict()` reports ASK; replay-command allows; ask and deny
  cases; a 12,000-span timing test.
- `tests/test-dropper-metadata-classes.sh`: N2 rows and the 50 KB heredoc test removed (C).
- `hooks/lib_poison_patterns.py`, `lib/hooks.sh`, `tests/test-shipped-command-scan.sh`: the sc-security
  branch only.
- `docs/HOOK_AUTHORING.md`: 2026-11-16 notes.

### Resume With
Read `.claude/handoff.md`, then this brief. If #317's CI is green, merge it with
`--match-head-commit` and mark memory `project-sn-delta-prs-inflight` resolved. Then, in fresh
worktrees, rebase and finish `fix/sc-security-scanner-fp`, then `perf/normalize-c-locale` (suite,
replay, PR, dispatched CI). Do not release 4.4.7 without the user's word.

### Start With
- `gh pr checks 317`: C's merge is the first step.
- `/sc-health`: the install here is older than master (see Per-machine in the carry file).

### Measurements
- safety.sh on 6000 `'a'` spans after `echo $(rm -rf /)` (`$S/tools/span_time.sh`):
  - master's old walk: 344 s (previous session)
  - B before the glob fix: 4.06 s locally at load ≈6, 14 s on the macOS CI runner
  - after the glob fix: 0.35 s
  - git-safety.sh: 0.06–0.08 s
  - C (rebased): 0.74 s at load 45
- Same payload with `LC_ALL=C`: 5.54 s vs 4.18 s without, so the locale did not help this payload.
- Timing test at 12,000 spans (`$S/tools/span_test_both.sh`): fixed tree PASS; old glob 16 s, FAIL.
- C's 50 KB heredoc payload, written and run (`$S/tools/hd_prof.sh`): master 0 s, C+N2 2 s at load
  ≈85; 15 s inside the full suite.
- FP replay, 10,000 unique commands (seed 7, `$S/tools/fp_replay.py`, `SAMPLE=10000`):
  - A: 4 differences (3 deny, 1 ask; the ask was load noise, allowed when re-run alone). After the
    fix, the 3 denies allow and the single-quoted `$( )` one asks, as intended.
  - B: 0
  - C with N2: 5 (4 deny, 1 ask) → 0 after N2 was dropped
- Full suite (macOS, bash 3.2): A 8207/0, B 8249/0, C 8301/0.

### Rejected — do not rebuild
- **N2 as a deny**: 5 of 10k real commands denied or asked, plus about 2 s per 50 KB body. Only
  acceptable as a body-only ASK with a size cap.
- **Masking quotes with spaces** to linearize the walk: it broke token matching (`r'm'` became `r m`).

### Dead ends
- `LC_ALL=C` on the quote/glob payload: no gain (see Measurements). Its effect on the 57 KB,
  1600 `$( )` payload (6.8 s idle, earlier measurement) is still unmeasured on the perf branch.

### Open questions
- Does `perf/normalize-c-locale` actually speed up the `$( )`-heavy payload? Unverified. Measure
  it with `$S/tools/nc_time.sh` on that payload before opening its PR.
- `git-safety.sh` once failed with "onFailure block, No stderr output" at load ≈330. Cause unknown;
  not reproduced at normal load.
- The claim-evidence Stop gate may not count background test runs (it flagged a claim backed by a
  background run). Unverified candidate.

### Reproduce
- `$S` = `/private/tmp/claude-501/-Users-radiustheme-GithubRepos-claude-supercharger/c8c4db43-9e98-47e4-b1fc-0bcb9b1b8de6/scratchpad`
  (it may be gone after a reboot).
- Replay: `SAMPLE=10000 python3 $S/tools/fp_replay.py <branch-tree> <master-tree> out.tsv`. Each
  row is `verdict_new<TAB>verdict_base<TAB>json command`. Reasons: `python3 $S/tools/why.py <tree> out.tsv`.
- Hot-line finder: `bash $S/tools/nc_lines.sh <tree> [spans]` (PS4 `$SECONDS:$LINENO`, prints
  where the clock jumps).
- Per-hook timing: `bash $S/tools/span_time.sh <tree>`. Fail-without-fix: `bash $S/tools/span_test_both.sh <tree>`.
- Search for guard rule text from a script file; the installed guard denies it inline.
