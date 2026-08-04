# Windows Support — Plan

Status: **Phase 1 in progress (G1 shipped v2.26.49)** · Target: **Phase 1 → a 2.x minor · Phase 2 → 3.0** · Last updated: 2026-08-04

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
| G1 | ~~**Desktop notifications**~~ — **BUILT v2.26.49** | 8 | `hooks/notify-helper.sh` (`_win_host` detector + PowerShell branch) | Git Bash/MSYS/Cygwin, and WSL when `notify-send` is absent, now route to a PowerShell toast: BurntToast if installed → native Win10+ WinRT toast → bell. Ordered *after* `notify-send` so WSLg keeps the native Linux path. Payload passes via `$env:` vars, never interpolated (PowerShell expands `$(…)`/backticks in double-quoted literals exactly as bash does — the v2.6.72 AppleScript RCE class). 10 tests in `test-notify-helper.sh`. **NOT verified on a real machine — see §11.** |
| G2 | ~~**`md5sum`/`md5`**~~ — **BUILT v2.26.50**. Worse than scoped: the existing `\|\|` fallback was **unreachable** (it binds to the pipeline, whose status is `cut`'s, and cut exits 0 on empty input), so an absent md5sum yielded an EMPTY key — every project sharing one state file, the audit-HIGH-#13 collision class. `hooks/lib-hash.sh` `sc_md5` guards each tier with `command -v`: md5sum → md5 → openssl → python3. 12 tests. | 8 | `repetition-detector.sh:52`, `failure-tracker.sh:54`, `quality-gate.sh:40,145`, `agent-router.sh:165`, `session-memory-write.sh:38`, `learn-from-prompts.sh:25`, `lib-suppress.sh:185` | Add `python3 hashlib.md5` as the final fallback — one helper in `lib/utils.sh`, call everywhere |
| G3 | ~~**`flock` shell utility**~~ — **CLOSED v2.26.51 by REMOVAL, not a port.** It never ran on macOS either (Darwin has no flock), it guarded the wrong window (the append is outside the lock), and the residual race is benign because `mv` is atomic — concurrent trims each write a valid 20-line file. A lock that runs on 1 of 3 platforms and protects advisory telemetry reads as a guarantee it never gave. | 1 | `tool-history-tracker.sh:66` (`flock -w 2 9`) | Fall back to python `fcntl.flock`, or skip locking on Windows (best-effort append) |
| G4 | **`jq` + `python3` not on Git Bash by default** | prereqs | `install.sh:8-24` (jq gate), `:25-28` (python) | Installer: detect on Windows, guide `choco install jq` / python; keep the hard `jq` gate but with a Windows-specific message |
| G5 | ~~**CRLF line endings**~~ — **BUILT v2.26.51.** `.gitattributes` pins `*.sh/py/json/jsonl/yml/yaml/md` to `eol=lf`, `*.ps1` to `crlf`, assets `binary`. Checkout-time policy, so it protects a Windows clone even though the repo has never held a CRLF file (verified 0). | repo | — | Add `.gitattributes`: `*.sh text eol=lf` (also `*.py`, `*.md` as appropriate) |
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
   **Verification caveat:** this branch is *writable and unit-testable here* — mock `powershell.exe` exactly
   as the existing tests mock `osascript`/`notify-send` — but whether a toast actually **appears** cannot be
   confirmed without a Windows box. It would ship written-and-unit-tested, not verified. Say so in the
   CHANGELOG entry rather than implying Windows notifications work.
2. **`md5` python fallback helper (G2)** — one function in `lib/utils.sh` (`sc_md5`), swap the 8 call sites
   to it. Chain: `md5sum` → `md5 -q` → `python3 hashlib.md5`.
3. **`flock` fallback (G3)** — `tool-history-tracker.sh`: if `command -v flock` absent, best-effort append
   (or a python `fcntl.flock` wrapper).
4. **`.gitattributes` LF (G5)** — `*.sh text eol=lf`.
5. **Tests** — extend the suite: `sc_md5` returns 8 hex on all fallback tiers; notify-helper picks the right
   backend per simulated platform; flock-absent path still writes.

Exit criteria: full suite green on both CI OSes; notifications documented as working on WSL.

### Phase 2 — native Windows support + verification (3.0)

1. **`install.sh` Windows detection (G4)** — detect Git Bash / MSYS, check `jq`/`python3`, print
   `choco install jq` guidance; confirm the generated settings.json hook commands run under Git Bash.
2. **Windows smoke test of hook registration** — verify `${hooks_dir}/*.sh` commands fire (path form OK).
3. **Symlink test validation (G6)** — confirm `! -L` behaves on Git Bash; degrade safely if not.
4. **Windows CI job** — GitHub Actions `windows-latest` + Git Bash running a Windows-relevant subset of the
   suite. **This is the linchpin** — turns "probably works" into "verified" and prevents regression.
5. **Docs** — a "Windows" section: Git for Windows requirement, `choco install jq`, LF note, WSL as the
   recommended sandboxed path.

Exit criteria: Windows CI green on the subset; a real Windows/WSL manual pass; README "Not supported: Windows"
line replaced with a real setup guide.

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
- **2026-08-03** — Evaluated two third-party Windows projects (§10). **Rejected both as dependencies**;
  kept one technical confirmation (protocol-activated toast is the Windows backend) and one corroboration
  (Git Bash is genuinely the Windows interpreter). **Plan unchanged** — G1 is still ~10 lines of our own bash.

---

## 9. Recommended first action

~~Build **Phase 1, item 1** — the `notify-helper.sh` Windows branch.~~ **DONE in v2.26.49** — see §11 for
exactly what that does and does not prove. It established the `_win_host` platform-detection pattern the
rest of Phase 1 reuses.

**Phase 1 is DONE** — G1 (v2.26.49), G2 (v2.26.50), G3+G5 (v2.26.51). What remains needs a machine: G4 (installer detection) and G6 (symlink tests) are Phase 2, and the linchpin is the `windows-latest` CI job. Nothing further can be verified from macOS. Eight call sites lose their hash entirely on Git Bash
(neither `md5sum` nor `md5` exists), and unlike G1 it is **fully verifiable here**: `sc_md5` returning 8 hex
chars through each fallback tier is testable on macOS and Linux CI. Prefer it over G3/G5 because the empty
hash silently breaks caching and dedup rather than failing loudly.

---

## 10. Prior art evaluated (2026-08-03)

Two community projects were checked against this plan. **Neither is adopted.** Recorded so they are not
re-evaluated, and so the reasoning survives if someone else proposes them.

### 10.1 `777genius/claude-notifications-go` — REJECTED as a dependency

Go binary, 772★/104 forks, GPL-3.0. Cross-platform notifier for Claude Code: Windows 10+ native toasts,
macOS AX-API window focus, Linux D-Bus with compositor detection, tmux/zellij/WezTerm targeting, webhooks
(Slack/Discord/Telegram/Teams/ntfy). Registers its own `PreToolUse` and `Stop`/`SubagentStop` hooks.
Installs via `curl -fsSL … | bash`, auto-downloading release binaries.

It genuinely solves notifications — far past what G1 needs — but is the wrong dependency here:

| # | Blocker | Detail |
|---|---|---|
| 1 | **License conflict** | GPL-3.0 vs our MIT (`LICENSE:1`). The code can't be vendored, and bundling the binary puts a GPL obligation on anyone redistributing Supercharger. Telling users to install it separately is license-clean but makes it a *prerequisite*, not something we ship. |
| 2 | **Competing hook layer, not a component** | It claims `Stop`/`SubagentStop`, where `claim-evidence-gate.sh` already runs. Two independent guard layers on one event, neither aware of the other. |
| 3 | **Binary + install pattern we ourselves block** | Supercharger is bash + `jq`/`python3` with no binary artifacts. Its installer is the `curl … \| bash` form `safety.sh` blocks — 28 hits in the live ledger. Shipping an install path our own guards reject is indefensible. |

**Kept from it — the technique, not the code:** it confirms the Windows backend is a **protocol-activated
toast** (clicking raises the originating terminal), and that **per-tab/pane targeting is impossible** on
Windows Terminal by architecture — so G1 should not attempt it. Its layered-fallback shape also matches the
one already in §7. Nothing here changes the ~10-line estimate for G1.

*Open question worth one check when Phase 1 starts:* it reaches Win10+ toast APIs **natively**, without
BurntToast. If a plain `powershell.exe` one-liner can do the same, the "BurntToast not installed" risk in §7
disappears and the fallback chain gets shorter. Unconfirmed — do not assume it.

### 10.2 `Ruanweiqiao/claude-code-windows-setup` — no technical content

127★/16 forks, single Chinese-language `README.md`, no code, no license. End-user install guide:
`irm https://claude.ai/install.ps1 | iex` in admin PowerShell, set `PATH`, fix execution policy, 32-bit
unsupported.

Touches none of G1–G6. Its one value is **independent corroboration of §2's central premise** — that Claude
Code on Windows relies on Git Bash — from a source outside the CC docs. That premise is what makes this plan
"not a rewrite", so a second source for it is worth the line. Nothing else to take.

---

## 11. What G1 does and does not prove (2026-08-04)

G1 shipped in **v2.26.49**. Be precise about its status, because "Windows notifications work" is not what was demonstrated.

**Verified here, by test:** the correct backend is *selected* for Git Bash (`msys`), Cygwin, and WSL; WSL **with** a working `notify-send` keeps the native Linux path (ordering, not just presence); plain Linux and macOS are unchanged; a host with no PowerShell and no `notify-send` still falls back to the bell; and the payload reaches PowerShell through `$env:` rather than the command line. Bisected — removing the branch fails 5 of them.

**NOT verified, and only a real machine can:** that a toast actually **appears**. The tests mock `powershell.exe`, so they prove invocation, not rendering. Specifically unproven: whether the native WinRT path raises a toast without an app-registered AUMID, whether BurntToast is commonly enough installed to matter, and whether the WSL interop path is reachable in a default WSL2 install.

**The §7 open question stands:** if the native WinRT layer works without BurntToast, that risk row disappears and the chain shortens to two layers. The code already tries native as the fallback, so the answer arrives with the first real test.

**Do not upgrade the claim** in the README or CHANGELOG beyond "written and unit-tested" until someone runs it on Windows or WSL.
