# Windows Support — Plan

Status: **systemic Windows work complete; ~10 items gated on a real Windows box** — on branch `feat/windows-support`. A full-suite Git Bash sweep found 23 failing suites across 5+ root-cause families; all inspection-resolvable ones fixed (**23 → 10**), incl. a security fail-open (see decision log 2026-07-08). All CI green (mac/Linux 1337 + the `windows-latest` Git Bash subset verifying every fixed class). The remaining ~10 (harness artifacts, NTFS exec-bit, a few residual root-causes) + a full Windows security pass are the **3.0 exit criteria needing the maintainer's Windows machine**. · Target: **merge → 3.0 after the Windows pass** · Last updated: 2026-07-08

This plan is the output of a research spike (two subagents: one on Claude Code's Windows
hook-execution model, one auditing the codebase for platform-specific bash). It scopes what
it takes for Supercharger to run on Windows, and phases the work so value ships early.

---

## 1. Goal & scope

**Goal:** Supercharger works for Windows users — first via WSL and Git Bash (bash preserved),
not a native PowerShell rewrite.

**Explicitly out of scope — a native PowerShell port.** Porting 94 hooks + libs to PowerShell
would recreate the *cross-channel parity-drift* bug class (a guard in bash **and** PowerShell whose
lists inevitably diverge) at 2× the maintenance surface — the exact class we spent v2.8.x closing.
Rejected.

---

## 2. Key finding — Claude Code does the hard part

From the Claude Code docs (hooks / settings / setup / statusline):

- **Windows hook interpreter:** **Git Bash if installed → PowerShell fallback.** CC *auto-selects*
  Git Bash; it is not `cmd`. macOS/Linux use `sh -c`.
- **Shebang:** `#!/bin/bash` is honored by Git Bash. (Ignored by PowerShell.)
- **Paths:** Git Bash **auto-converts** `C:\Users\…` → `/c/Users/…` (POSIX) before the hook sees them.
- **`.sh` hooks must use shell form** (a `command` string, **no `args` field**); exec form can't run `.sh` on Windows.
- **Config location:** `%USERPROFILE%\.claude\`. **statusLine runs the same way** as hooks.
- **Gotcha — line endings:** `core.autocrlf=true` can give `.sh` files CRLF, which breaks Git Bash. Enforce LF.

**Consequence:** with Git for Windows present, our bash hooks **run largely as-is** — the runtime handles
interpreter selection and path conversion. The remaining work is a bounded set of missing-tool fallbacks,
notifications, and install/test plumbing — **not a rewrite**.

References:
- https://code.claude.com/docs/en/hooks.md
- https://code.claude.com/docs/en/settings.md
- https://code.claude.com/docs/en/setup.md
- https://code.claude.com/docs/en/statusline.md

---

## 3. Feasibility verdict

| Environment | State | Effort |
|---|---|---|
| **WSL 2** (CC running inside WSL) | Basically works today — it's Linux. Only real gap: notifications. | Small (docs + notify) |
| **Native Windows + Git for Windows** | Hooks run via Git Bash; gaps are missing tools + notifications + LF. | ~2–3 days, mostly mechanical |
| **Native Windows, PowerShell only (no Git Bash)** | Not supported (can't run `.sh`). Document "install Git for Windows." | N/A (out of scope) |

**Bottom line: viable, not a rewrite.** Estimate ~2–3 focused days for Git Bash/WSL support.

---

## 4. Gap inventory (audit, with corrections)

### 4.1 Genuine gaps — must fix

| # | Gap | Sites | File:line (representative) | Fix |
|---|---|---|---|---|
| G1 | **Desktop notifications** — only macOS (`osascript`) + Linux (`notify-send`); no Windows branch → silent (bell only) | 8 | `hooks/notify-helper.sh:67-101` (89,92 osascript; 94,97 notify-send) | Add a Windows branch: PowerShell toast (`New-BurntToastNotification`) or `msg`; graceful no-op if absent |
| G2 | **`md5sum`/`md5`** — neither exists on Git Bash; fallback chain ends empty | 8 | `repetition-detector.sh:52`, `failure-tracker.sh:54`, `quality-gate.sh:40,145`, `agent-router.sh:165`, `session-memory-write.sh:38`, `learn-from-prompts.sh:25`, `lib-suppress.sh:185` | Add `python3 hashlib.md5` as the final fallback — one helper in `lib/utils.sh`, call everywhere |
| G3 | **`flock` shell utility** — absent on Git Bash; shell use has no fallback | 1 | `tool-history-tracker.sh:66` (`flock -w 2 9`) | Fall back to python `fcntl.flock`, or skip locking on Windows (best-effort append) |
| G4 | **`jq` + `python3` not on Git Bash by default** | prereqs | `install.sh:8-24` (jq gate), `:25-28` (python) | Installer: detect on Windows, guide `choco install jq` / python; keep the hard `jq` gate but with a Windows-specific message |
| G5 | **CRLF line endings** break Git Bash execution | repo | — | Add `.gitattributes`: `*.sh text eol=lf` (also `*.py`, `*.md` as appropriate) |
| G6 | **Symlink `! -L` tests** — reliability on Windows/Git Bash unclear | 8 | `enforce-pkg-manager.sh:62,69,76,85` | Validate on Windows; worst case the check is advisory, so degrade safely |

### 4.2 Already handled — no work

- **`stat`/`date`** — every site is GNU-first with BSD fallback (`stat -c … || stat -f …`); Git Bash has GNU stat. Date uses portable format strings. (`repetition-detector.sh:95`, `update-check.sh:28`, `scope-cleanup.sh:98`, …)
- **`timeout`/`gtimeout`** — guarded with `command -v`; Git Bash ships `timeout`.
- **`iconv`** — used with `|| true` fallback (`notify-helper.sh:83-85`); missing → skips transliteration, notification still fires.
- **`realpath`** — only via Python `os.path.realpath()` (cross-platform).
- **`grep`/`awk`/`sed -E`** — POSIX/portable; no `grep -P`.
- **`chmod`** — emulated on NTFS under Git Bash; succeeds harmlessly.

### 4.3 Audit "blockers" DOWNGRADED (verified against current behavior)

- **`sed -i.bak` / `sed -i.tmp`** (install.sh:376,384; uninstall.sh:62,65; tools/bump-version.sh, tools/release.sh) — the audit flagged this as a BSD/GNU blocker. **False alarm:** we run these on **macOS (BSD sed) in green CI today**, and GNU sed (Git Bash) also accepts the attached-suffix form. Portable. No change. *(One item to eyeball: the multi-line trailing-blank-strip `sed -e :a …` in uninstall.sh:65 — confirm it runs on Git Bash GNU sed; if flaky, replace with the awk trailing-blank trim already used in `sc-toggle.sh`.)*
- **Installer hook-path backslashes** — the audit assumed Windows-native path expansion. But `install.sh` runs **under Git Bash**, where `$HOME` is already `/c/Users/…` (POSIX), so `${hooks_dir}/safety.sh` emits forward-slash commands CC can run. **Likely fine** — needs a Windows smoke test to confirm, not a code change up front.

---

## 5. Phased plan

### Phase 1 — cross-platform hardening (a 2.x minor, ships value now)

Everything here **also improves mac/Linux robustness** and needs **no Windows machine to land**. It
directly fixes the already-reported "no notifications" bug.

1. **`notify-helper.sh` Windows branch (G1)** — add a `powershell.exe`/`pwsh` toast path (BurntToast if
   present, else `msg` / balloon), gated on OSTYPE/`uname` detecting `msys`/`cygwin`/WSL. Keep the bell as
   the final fallback. *Works for WSL (via `powershell.exe` interop) and Git Bash.*
2. **`md5` python fallback helper (G2)** — one function in `lib/utils.sh` (`sc_md5`), swap the 8 call sites
   to it. Chain: `md5sum` → `md5 -q` → `python3 hashlib.md5`.
3. **`flock` fallback (G3)** — `tool-history-tracker.sh`: if `command -v flock` absent, best-effort append
   (or a python `fcntl.flock` wrapper).
4. **`.gitattributes` LF (G5)** — `*.sh text eol=lf`.
5. **Tests** — extend the suite: `sc_md5` returns 8 hex on all fallback tiers; notify-helper picks the right
   backend per simulated platform; flock-absent path still writes.

Exit criteria: full suite green on both CI OSes; notifications documented as working on WSL.

### Phase 2 — native Windows support + verification (3.0)

1. **`install.sh` Windows detection (G4)** — ✅ DONE. Platform detection (`$OSTYPE` msys/cygwin + `uname`
   MINGW/MSYS/CYGWIN); jq-missing and python3-missing gates now print `winget install jqlang.jq` /
   `winget install Python.Python.3.12` (with choco/scoop alternates) on the Git-Bash family. WSL is not
   flagged (it's Linux). Test: `test-install.sh` "Windows prereq guidance when jq absent (G4)".
2. **Windows smoke test of hook registration** — PENDING (needs the CI job / a real box). Path form is
   forward-slash under Git Bash (`$HOME`=`/c/Users/…`), so the generated settings.json commands should run;
   the CI job exercises the hooks directly with crafted stdin, which is the meaningful unit-level check.
3. **Symlink test validation (G6)** — ✅ VERIFIED-SAFE, no code change. `enforce-pkg-manager.sh`'s
   `[ -f X ] && [ ! -L X ]` is a workflow nudge (npm→pnpm), not a security guard. MSYS `test -L` returns
   false for regular files, so the worst case is *over*-enforcing on a rare symlinked lockfile — advisory
   and non-destructive. Adding Windows branches would be complexity for no safety gain.
4. **Windows CI job** — ✅ DONE (linchpin). `.github/workflows/ci.yml` `test-windows` job: `windows-latest`
   with `shell: bash` (GitHub's bash on Windows IS Git Bash / MSYS2 — our target runtime). Ensures jq on
   PATH, then runs the Phase 1 fallback suites (`test-notify-helper`, `test-md5-fallback`,
   `test-tool-history-tracker`). The `.gitattributes` LF rule (G5) is exercised implicitly — a CRLF `.sh`
   wouldn't execute. Self-verifies on push; **watch this job green before merging to 3.0.**
5. **Docs** — ✅ DONE. README "Windows?" section expanded (WSL recommended; Git for Windows + winget/choco
   prereqs; toast/LF notes; PowerShell-only unsupported) and Requirements updated.

Exit criteria: **Windows CI green** (the one remaining gate) → optional real Windows/WSL manual pass → merge
to master as 3.0. README already replaced the bare "use WSL or Git Bash" line with a real setup guide.

---

## 6. Testing strategy

- **Phase 1** is verifiable on existing mac/Linux CI (the fallbacks are platform-agnostic logic).
- **Phase 2** needs the `windows-latest` CI job — without it, Windows support is unverifiable and will rot.
  Scope it to the hooks/tests that don't need a full Claude Code session (unit-level hook invocation with
  crafted stdin payloads, exactly like the current suite).
- **Manual pass** on a real Windows box (Git Bash) and a WSL 2 instance before announcing.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Windows behavior drifts silently (no coverage) | Phase 2 Windows CI job is mandatory, not optional |
| Path form in settings.json fails on native Windows | Verified by the Phase 2 smoke test before claiming support |
| Notification backend (BurntToast) not installed | Layered fallback: BurntToast → `msg` → bell → silent; never errors |
| Scope creep toward a PowerShell port | Explicitly ruled out here; bash-only, Git Bash/WSL is the contract |
| CRLF corruption of `.sh` on clone | `.gitattributes` LF enforcement (Phase 1) |

---

## 8. Decision log

- **2026-07-07** — Rejected native PowerShell port (parity-drift surface). Chose Git Bash/WSL.
- **2026-07-07** — Downgraded two audit "blockers" (`sed -i.bak`, installer backslash paths) after verifying
  against current green CI and the Git-Bash-runs-install fact.
- **2026-07-07** — Sequenced Phase 1 (platform hardening, ships on 2.x) before Phase 2 (native Windows + CI, 3.0),
  so the notification fix and robustness land immediately and de-risk the harder native work.
- **2026-07-08** — The `windows-latest` Git Bash CI job **paid for itself immediately**: it caught a real bug the
  mac/Linux suite structurally could not. `tool-history-tracker.sh` is always python-parsed (v2.7.58), and
  **Windows Python's `print()` emits CRLF** — so `SESSION_ID=${RESULT%%$'\n'*}` kept a trailing `\r`, the hook
  wrote `.tool-history-<sid>\r`, and `confidence-gate`'s python-derived (clean) reader looked for the CR-less
  name → session history silently never found on Windows, degrading confidence scoring. Fixed with `tr -d '\r'`
  on the python capture + a regression guard. Lesson: **any hook that turns Python `print()` output into a
  filename/key is CRLF-exposed on Windows**; jq-primary and md5sum-primary paths are safe (Git Bash ships both),
  so tool-history was the only always-python offender — but this is the pattern to watch in future hooks.
- **2026-07-08** — Ran the FULL suite on `windows-latest` Git Bash (temporary CI sweep) to find *every* Windows
  failure, not just the CRLF class. Surfaced **23 failing suites across 5+ root-cause families**, diagnosed by
  4 parallel subagents + a decisive CI probe. Fixed all the ones resolvable by inspection, driving **23 → 10**:
  - **cp1252 encoding** (`PYTHONUTF8=1` in both shared libs + 39 lib-less hooks/tools) — Windows Python's locale
    codec crashes on UTF-8 content.
  - **Fact B — `expanduser('~')` ≠ `$HOME`**: a CI probe proved MSYS auto-converts the `HOME` env var to a
    native path that Python can open, so `os.environ.get('HOME') or os.path.expanduser('~')` is correct on every
    platform (10 hooks). Cleared rate-limit, mcp-guards/elicitation, hook-overrides/project-config, install statusLine.
  - **Fact A — interpolated POSIX paths in `python3 -c`** (not MSYS-converted): hook-doctor (env var), stop-verify (jq).
  - **`fcntl` absent** (budget-cap, subagent-cost) → guarded import, best-effort no-lock.
  - **`os.rename` not atomic-overwrite on Windows** (F4) → `os.replace` ×4; this was the real circuit-breaker
    fail-open (counter froze → never tripped), beyond the earlier `\r` fix.
  - **POSIX paths into native git/compound-env** (session-checkpoint `git -C`, session-analytics) → `cygpath -w`.
  - **Security fail-safe**: `safety.sh`'s python realpath layer fails open on Git Bash (realpath of a POSIX
    system literal → C-drive path, never matches). Added a **Windows-gated** bash string-match net (provably no
    mac/Linux change; validated by `OSTYPE=msys` simulation). safety-detect.py confirmed string/regex-based
    (no realpath fail-open) + reachable via MSYS-converted argv.
  The permanent Windows CI subset was expanded to regression-guard these path/security fixes on real Git Bash;
  the temporary probe/sweep were removed.
- **2026-07-08 — REMAINING (needs a real Windows box; the macOS-inspection limit).** ~10 suites still fail on Git
  Bash and could not be responsibly closed from macOS: `standards-inject` + `session-checkpoint` (cygpath fixes
  were correct-in-principle/no-op on mac but did not fully land — root cause unobservable without Windows);
  `budget-cap`/`subagent-cost` residual cost-logic; `hook-doctor` (NTFS has no exec bits — `[ -x ]` is meaningless
  where CC runs hooks via `bash`); and **harness artifacts** confirmed by the subagents to leave the guards intact
  or fail-*closed* (`path-guard`, `scope-guard`, `hook-new`, the 2 fork-latency "hangs"). These + a full Windows
  security pass are the **3.0 exit criteria** requiring the maintainer's Windows machine. mac/Linux stayed green
  (1337) throughout; no regressions.
- **2026-07-08** — Post-fix, a 3-subagent audit swept **every always-python hook** for the same CRLF-into-key
  pattern and found **6 more** genuine exposures beyond tool-history (all `${VAR//$'\r'/}`-fixed): the HIGH ones
  were `enforce-pkg-manager.sh` (pkg-manager enforcement no-op'd) and `subagent-circuit-breaker.sh` (breaker
  failed open) — two guards silently disabled on Windows. `test-windows-crlf.sh` now guards all 7 strips and
  functionally proves the pkg-manager block on the `windows-latest` CI subset. Rule of thumb recorded in
  [[windows-python-crlf-keys]]: jq-primary and md5sum-primary paths are safe; *always-python* captures that
  become a filename/key/control-flow value are the exposure.
- **2026-07-08** — The PATH-mirror tool-hiding test technique (symlink all of `$PATH` minus one tool to force a
  fallback branch) is **mac/Linux-only**: on MSYS `ln -s` copies files, so it clones `C:\Windows\System32` and
  hangs the runner. Skip such tests on msys/cygwin — the fallback tools' native presence/absence on Git Bash
  already exercises the branches. Also corrected a plan assumption: **modern Git for Windows DOES ship `md5sum`**
  (MSYS2 coreutils), so the G2 python md5 tier is a rare-edge fallback there, not the primary path.

---

## 9. Recommended first action

Build **Phase 1, item 1** — the `notify-helper.sh` Windows branch. Smallest, highest-value, independently
useful (fixes the reported "no notifications" issue on WSL today), and it proves the platform-detection
pattern the rest of Phase 1 reuses.
