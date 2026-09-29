# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-09-28, session `3d213381`.*

- **v4.1.19 RELEASED** 2026-09-29 (#59-#66). Includes a SECURITY fix (#64):
  a `VAR=` prefix holding `[brackets]` hung normalize_cmd forever (unquoted glob in
  `${cmd#${BASH_REMATCH[0]}}`), Claude Code killed the hook and ran the command, so
  `P=[x] <destructive>` bypassed every normalizing guard. Anyone on <= v4.1.18 is
  exposed: update.
- Also in v4.1.19: env-dump + agent self-kill guards (#61), multi-line/clustered
  commit messages no longer scanned (#60), injection scanner decodes base64/hex/
  percent + bidi/hidden-html (#62), Vault/OpenBao ask (#63), CLAUDE.md blank-line
  growth (#59).
- **v4.1.18 RELEASED** (#57 grep patterns are data). v4.1.15-17 earlier.
- CI: Windows on master pushes only; promote needs master's Windows run at the
  release base. GitHub skipped the push run for #64's merge once (0 runs for the
  SHA) - if promote waits forever, check `gh api .../actions/runs?head_sha=`.
- **Machine A (this box): INSTALLED v4.1.19** (verified: `P=[x] rm -rf ~` denies in <2s).
- **Machine B**: unknown. Update straight to the latest release.
- **Open**: heredoc code tripping the credential/DNS rules; command-string mutation
  (heredoc unescape, Windows backslash halving, >8KB truncation) needs probes.

### Per-machine / per-account facts
- **`claude-supercharger` is PUBLIC — its Actions are free and unmetered.**
  Sept usage: Windows 10,678 min, macOS 1,977, Linux 3,652, **all netting $0.00**.
  Windows is trending hard: Jul 166 → Aug 7,744 → Sep 10,678.
- **`smrafiz/radius-apps` Actions were DISABLED 2026-09-22** over a quota email —
  but it does **not appear in the billing usage at all**. Re-enable when
  convenient; with Actions off, its PRs merge with no CI. Billing cycle is
  calendar-month, resets **2026-10-01**.
- `radiustheme/radius-bundles` is an ORG repo, billed separately, already tuned.

### Decisions parked, not blocked
- **Install the tag rather than master?** Merging to master currently IS
  shipping. Against: users lose immediate fixes. Mitigating: PRs run all 8 jobs.
- **Never seize the output-style slot.** One global field; `force-for-plugin`
  overrides the user's own choice.

### Open, not started
- **What is actually at 90%?** Every billing line nets $0.00 yet the email fired.
  The included-minutes counter is not exposed by the API — read the Billing page.
- **An unexplained deny.** A `sensitive file access` block fired on a commit
  command, unreproduced in five attempts. If it recurs, capture the command first.
- **Stacked PRs**: merging a parent and deleting its branch CLOSES the child.
---

## Log

#### 2026-09-28 — 3d213381
Research sweep (web, GitHub, upstream tracker) became six fixes (#59-#64). A history
replay that timed out led to a SECURITY bug: a bracketed `VAR=` prefix hung every
Bash guard, which fails open. Every guard change was replayed against ~48k real
commands first; three first drafts regressed and were caught that way.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-27 (late) — 3d213381
Released **v4.1.17** (cron rule prose FP). Swept every real deny that depended only on
quoted or heredoc text: the real ones were search patterns scanned as shell, fixed in
#57 (unreleased). Wrote the five-fix lesson into `docs/HOOK_AUTHORING.md`.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-27 (later) — 3d213381
Released **v4.1.16**: a dotenv block on a real grep traced to quoted-`|` truncation in
the sensitive-read rule, an FP and an FN in one line (#53). Moved Windows CI to master
only (~80 min per PR saved) and fixed the promote gate that change broke (#54).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-27 — 3d213381
Traced /sc-status's "recent blocks" to their transcripts and found two shipped defects:
lesson-record saved dashboards/tables as lessons and fed itself (#48), and the claim
gate read `failed=0` as a failure — nearly all its blocks were false (#49). Both caught
a regression in their first draft only by replaying real transcripts. Staged v4.1.15.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-24 — 3d213381
Released **v4.1.14**. Audited all 33 commands, research first: /learn rules never
resurfaced (Jaccard 0.00), /reflect lessons never reached the next session (loader
reads 4 lines), /why's filter was inverted, /profile ignored per-project config.
Fixed the rm bypass (#44) after a 21k-command replay caught a false positive, and
the mtime-ranked handoff loader (#45). New /design-review.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

