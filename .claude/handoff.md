# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-25, session `3d213381`.*

- **Released: v4.3.25** (#168 Trust Receipts, #169 audit-trail patterns). Installed v4.3.25 on Machine A.
- **Merged since:** #170 (`f7e5cc6`, installer deploys all python tools + notifier; receipts skip tab
  tools), #171 (`2818913`, reinstall/update no longer die on a staged directory).
- **In flight: 4.3.26** = #170 + #171. Machine A launchd `sc.finish.4326b`; result in
  `~/.cache/sc-finish-4.3.26.result`. Master after #170 alone broke every second install/update.
- **Docs PR `docs/handoff-1025`**: notes, this file, brief. Merge after 4.3.26.
- **/sc-update installs master, not a tag.** Check master CI after every merge.
- **Windows rule:** PR CI skips Windows; dispatch `gh workflow run ci.yml --ref <branch>`. The
  "update.sh actually deploys" step updates FROM MASTER, so an update-path fix fails it on its own branch.
- **Release recipe:** detached `launchctl submit` job, quote PATH, dies on reboot. Remove PR worktrees.
- **Open (user):** star-keeper `git config supercharger.commitTypes "words notes access handoff drafts"`.
- **Machine A:** 4 stashes (drop only on the user's say-so).
- **Machine B:** unknown. **Open (user):** radius-apps guard-push wrapper; rotate CRON_SECRET;
  re-enable radius-apps Actions.

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

#### 2026-10-25 (deep) — 3d213381
4.3.25 released. #170 (installer missed receipts.py/notifier) then broke reinstall on master (dir swap);
#171 fixed it. 4.3.26 job in flight. Three tests that could not fail, fixed.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-25 deep)

#### 2026-10-21 (deep) — 3d213381
4.3.24 released after a reboot killed the first job. #168 Trust Receipts merged (Windows green after an
argv-conversion fixture fix). #169 audit-trail on shared secret patterns open; 4.3.25 releases both.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-21 deep)

#### 2026-10-20 (deep) — 3d213381
Merged #164/#163/#165/#166 for one 4.3.24 (32 guards fail closed, drift alarm, CVE-class fixes).
Master went red twice on Windows (MSYS path inside a string, then CRLF); fixed, branch Windows run
green. Release job in flight.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-20 deep)

#### 2026-10-19 (deep) — 3d213381
Released 4.3.21–4.3.23; 4.3.24 in flight. Replayed 4,000 real calls through every PreToolUse hook:
core guards never exit outside 0/2 (so `onFailure:block` is safe), and 8 guards were dead on the plugin
(committed 644). Per-repo commit types; health catches IS_DEMO.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-19 deep)

#### 2026-10-18 (deep) — 3d213381
Released 4.3.18–4.3.20; 4.3.21 and 4.3.22 (STE mode, handoff --html) followed on 10-19. Found and fixed two cost errors (per-line usage 2.04x,
family pricing 1.57x), an inert screen redactor, a `$IFS` evasion and a credential fail-open under load.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-18 deep)
