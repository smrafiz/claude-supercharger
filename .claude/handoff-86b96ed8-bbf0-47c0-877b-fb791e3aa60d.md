## Handoff — claude-supercharger — 2026-08-09

### Done
- **Nine releases shipped to master, v2.26.74 → v2.26.82 (@`fc6e1a0`), every one CI-green
  on all 8 jobs.** Detail is in `CHANGELOG.md` / `git log v2.26.73..fc6e1a0`. Suite
  3452 → 3540. Local install deployed and behaviour-verified at `.82`.
- Four arcs on master: loosening-mode confirms (`.74`); a fresh coverage-diff sweep
  researched and shipped complete, all four ranks (`.76`–`.78`, memory
  `candidate-features-2026-08-09`); tooling + perf Tier 1 (`.75`, `.79`, `.80`); and
  **red-teaming the same-day guards** (`.81`, `.82`), which found six real bypasses in
  an hour and was the highest-yield activity of the day.

### In Flight
**A Windows arc on branch `windows-suite-subset` (draft PR #2). NOTHING is on master.**
Branch @`57b1437`, tree clean, 5 commits ahead. Local suite 3552/0.

- **The finding that opened this:** Phase 2 item 4 of `docs/WINDOWS-SUPPORT-PLAN.md` — run
  the suite on `windows-latest` — was never done. 3540 assertions ran on ubuntu+macOS and
  **zero** on Windows. G1–G6 being "closed" only ever meant targeted probes passed; hook
  LOGIC had never been exercised there. First recon: **3077 passed, 463 failed.**
- **Bug #1 FIXED (`da8fe4e`)** — per-project scope keys were illegal NTFS filenames.
- **Bug #2 OPEN, HIGH severity, still unpatched — and my diagnosis was WRONG.** path-guard
  refuses nothing on Windows (`$HOME accepted as a root: rc=0`, making the whole home
  directory in-project and writable). I suspected a POSIX-vs-Windows path FORM mismatch.
  **The runner disproved it** (run `31311636929`):
  ```
  bash HOME                 = /c/Users/runneradmin
  python expanduser         = C:\Users\runneradmin
  python realpath(HOME env) = C:\Users\runneradmin   <- MSYS conversion WORKS
  REFUSAL WOULD FIRE (rp == home)? True
  ```
  So `hooks/path-guard.sh:217-222` is SOUND on Windows and must not be "fixed" on the form
  theory. The cause is elsewhere — suspect the test HARNESS (run.sh gives each file a
  `mktemp -d` HOME; on Windows that is `C:\Users\RUNNER~1\AppData\Local\Temp\...`, an
  8.3-style path that may not compare equal to its realpath). **Verify before touching the
  hook.**
- **466 failures still untriaged** (suite is 3552 there; 3086 passed). Many show EMPTY
  results (`expected ASK, got `), which smells like a handful of systemic causes, not 466
  independent bugs. A strong candidate given the finding below: any test that writes to
  `/tmp` and reads it back through python is a HARNESS artifact, not a product bug.
- **Latest run `31312xxxxx` (@`b790c73`) re-runs the recon with the log path fixed.** Until
  it lands there is still no grouped list and no artifact.

### Decisions Made
- **Branch + draft PR, never master.** CI only triggers on master pushes or PRs to master,
  and 463 untriaged failures must not touch master.
- **Recon runs the FULL suite report-only rather than a hand-picked subset.** Guessing which
  files are Windows-safe is how harness breakage gets reported as product failure — Git
  Bash's `ln -s` silently COPIES (plan §11.1), so the POSIX PATH-building test files would
  have copied `bash`/`python3` and lied. The curated `TEST_GLOB` subset follows the evidence.
- **`TEST_GLOB` added to `tests/run.sh`**, default unchanged; a subset run no longer judges
  the README badge (it would report false drift and fail the job on a correct number).
- **Bug #2 NOT patched on a hypothesis.** It is a security hook; a diagnostic step was added
  to make the runner answer it first. Nothing Windows is answerable from macOS.
- **Bug #1 fixed in BOTH key functions** (`sc_project_key` in `hooks/lib-paths.sh`,
  `_project_key` in `hooks/project-config.sh`) because they must produce byte-identical
  keys — one channel writing a file the other never reads is the actual failure mode. The
  change is a no-op on POSIX, so no installed scope file is orphaned.

### What Failed
- **Queued FOUR Windows runs against a serialized runner and blocked my own feedback loop**
  — cost ~1h wall-clock. There is no `concurrency` block in `ci.yml`, so runs are NOT
  auto-cancelled; they queue. Cancel superseded runs manually, or add a concurrency group.
- **First recon produced no usable failure list**: the in-CI `awk` grouping did not match
  the ANSI-coloured FAIL lines and printed nothing, and my own `head -60` truncated the
  rest. Fixed by grouping in python and uploading the whole log as an artifact.
- **`gh run list --json databaseId --template '{{.databaseId}}'` renders the run ID in
  SCIENTIFIC NOTATION** (`3.13e+10`) and every follow-up API call 404s. Use `--jq`.
- **Two hypotheses killed before they cost anything:** encoding is NOT behind the
  zero-width failure (`PYTHONIOENCODING`/`PYTHONUTF8` are exported from `lib-paths`, which
  every hook reaches); and the ubuntu red on this branch was the README badge count, not a
  regression — the suite was 3552/0 with zero assertion-level failures.
- **My own guards blocked my own probes repeatedly** (literal AWS key in a command, a
  `curl|bash` string, `subprocess` inside `python -c`). Assemble such payloads from parts;
  it is the guards working, not a bug.
- **A POSIX `/tmp` path in the recon step cost TWO full runs.** `grep` read
  `/tmp/win-suite.log` fine while, on the same line of the same step, python raised
  `FileNotFoundError` on it and `upload-artifact` found nothing. **MSYS rewrites paths
  passed as ARGUMENTS, not strings inside a script or an action input.** Fixed by making
  the path workspace-relative (`b790c73`). This is the same bug class the job exists to
  find, in the job's own scaffolding — worth remembering when triaging the 466.
- **The path-form hypothesis for Bug #2 was wrong** (see In Flight). It cost one run to
  disprove and was worth every second: patching a security hook on that theory would have
  changed working logic while leaving the real cause in place.

### Blockers
- **The 466 failures need the `windows-suite-log` artifact to triage.** The first three
  runs produced no artifact (POSIX `/tmp` path); `b790c73` fixes it. Nothing else can
  proceed until that lands — and each Windows cycle is ~45 min.
- **Bug #2 needs a NEW hypothesis.** The form theory is dead (see In Flight). Next step is
  to print, on the runner, what the failing test actually passes as its project root and
  what `realpath` makes of a `mktemp -d` HOME there — not to edit `path-guard.sh`.

### Files Touched
All on branch `windows-suite-subset`; see `git log master..HEAD` for the diffs.
- `hooks/lib-paths.sh` + `hooks/project-config.sh` — Bug #1, the key fix (must stay in sync)
- `tests/test-project-key-windows.sh` — NEW, 12 tests; 2 fail pre-fix, which is the whole
  point. Only the illegal-character PROPERTY is assertable off-Windows: `:` and `\` are
  legal in macOS filenames, so the consequence cannot be reproduced locally.
- `tests/run.sh` — `TEST_GLOB`; badge check skipped for subset runs
- `.github/workflows/ci.yml` — diagnostic + recon + artifact upload (all TEMPORARY scaffolding)
- `README.md` — tests badge 3540 → 3552

### Resume With
Windows arc is mid-flight on branch `windows-suite-subset` (draft PR #2); master is clean at
v2.26.82. Read the `windows-suite-log` artifact from the newest CI run on that branch, plus
its `DIAGNOSTIC — POSIX vs Windows path forms` step output, then fix Bug #2 (path-guard
refuses nothing on Windows) and triage the ~450 remaining failures into real bugs vs harness
artifacts. The recon steps in `ci.yml` are scaffolding and must be replaced by a curated,
GATING `TEST_GLOB` subset before this merges.

### Start With
`gh run list --branch windows-suite-subset` then `gh run download <id> -n windows-suite-log`
— everything is blocked on that artifact, and use `--jq` not `--template` for run IDs.
Do NOT re-run the recon before reading it: each Windows cycle costs ~45 min and runs queue
rather than cancel.
