# Install/build gate — design (Step 4, not built)

Status 2026-11-21: the **log-only first release is built** (`hooks/install-surface-gate.sh`,
`tests/test-install-surface-gate.sh`), covering npm/pnpm/yarn/bun, pip and cargo. It never asks and
prints nothing; findings go to `$SUPERCHARGER_STATE/install-surface.jsonl`. `make`, `pytest`, gradle,
`$(shell)` and git hooks are not scanned yet. Turning it into an ASK waits on real findings.
Measured: a non-install Bash call exits at the shell `case` (0.00 s); the scan path costs 65-110 ms
(two git calls plus one python fork), on install/build commands only. The 20-40 ms estimate below
was wrong.

## The gap

`install-script-guard.sh` and `pth-persistence-guard.sh` fire on **Write/Edit** of a manifest. A
cloned repo's `package.json`, `setup.py`, `conftest.py` or `build.rs` is never written by the session,
so nothing reads it before `npm i`, `pip install .`, `make`, `cargo build` or `pytest` runs it. The
41 trap repos in the agent-white-hat corpus use exactly this: the dangerous code sits in a file the
session only reads, and the Bash call that triggers it looks ordinary.

## Proposal

One PreToolUse:Bash hook, `install-surface-gate.sh`.

1. **Trigger (shell `case`, no fork):** the command contains `npm i|install|ci`, `pnpm i|install`,
   `yarn`, `bun i|install`, `pip install`, `python setup.py|-m pip`, `make`, `cargo build|run|test`,
   `pytest`, `gradlew`, `mvn`. No match ⇒ exit 0 (this is the hot path; most Bash calls stop here).
2. **Scope (stat only):** run in the command's working directory. Only when the project is **not
   the user's own**: the repo's last commit is by someone else, or the directory has no `.git`, or
   it was cloned this session (reuse `committed_by_someone_else`-style check from
   `lib_config_checks.py`). The user's own project stays quiet.
3. **Surface scan (one python fork, only past 1 and 2):** read, size-capped (64 KB each):
   - npm lifecycle fields, `binding.gyp`, `.pnpmfile.cjs`, `.yarnrc*` `yarnPath`
   - `setup.py`, `pyproject.toml` build-backend, any `.pth`, `conftest.py`
   - `build.rs`, `.cargo/config*` `rustc-wrapper` / `runner`
   - Makefile `$(shell …)`, gradle `distributionUrl`, `.git/hooks/*` non-sample files
   Reuse the existing network/eval token list from `install-script-guard.sh` so the two never drift.
4. **Verdict:** ASK, naming file and line and the reason. Never DENY: a legitimate native build has
   `build.rs`. A clean scan is silent.

## Cost (measured and estimated)

- A hook that exits at the trigger test: 0.00 s per call (measured on `install-script-guard.sh`).
- Past the trigger: one `stat` batch plus one python fork, estimated 20-40 ms, on install/build
  commands only. Not yet measured for this hook; measure before merging.

## Risks

- **False positives:** `build.rs` and `conftest.py` are normal in real projects. ASK, not DENY, and
  only for a foreign repo, keeps this tolerable. Needs a replay over real transcripts before merge.
- **Coverage ceiling:** a script that fetches its payload at run time shows only a fetch. We flag
  the fetch, not the payload.
- **Two gates:** the trigger `case` and the rules must both change when a tool is added.

## Questions for the user

1. Build it at all? Existing guards cover writes; this covers cloned code.
2. ASK or silent-log for the first release (a month of receipts before asking)?
3. Include `make`/`pytest`? They have the most legitimate-use noise.
