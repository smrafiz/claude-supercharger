Resolve an in-progress merge or rebase conflict. Context: $ARGUMENTS

**Step 1 — See the actual state**
Run `git status` and `git diff --name-only --diff-filter=U` for the conflicted files.
Identify whether this is a merge, a rebase, or a cherry-pick — the finish step differs.

**Step 2 — Recover the intent behind each side**
For every conflicted file, find out *why* each side changed. `git log --merge -p <file>`
shows the commits that touched it on both branches; read their messages, and the PR or
issue if the message points at one.

Resolving without this is guessing. A conflict is two intentions colliding, and you
cannot preserve an intention you never read.

**Step 3 — Resolve each hunk**
- Preserve **both** intents wherever they compose.
- Where they genuinely conflict, keep the one matching the stated goal of this merge
  and say which trade-off you made and why.
- Do **not** invent behaviour that was on neither side. A conflict is not a licence to
  redesign — that change belongs in its own commit where it can be reviewed.
- Never `git merge --abort` to escape a hard conflict unless the user asks. Aborting
  discards the resolution work and the next attempt starts from the same place.
- Delete every marker. Grep for `<<<<<<<`, `=======`, `>>>>>>>` before continuing —
  a committed marker is a broken build that git will not warn you about.

**Step 4 — Verify against the project's own checks**
Discover them rather than assuming: look at `package.json` scripts, `Makefile`,
`.github/workflows/`, `justfile`. Run typecheck, then tests, then formatter — in that
order, since a type error makes test failures unreadable.

A conflict resolution that compiles is not correct. It is the minimum bar for finding
out whether it is correct.

**Step 5 — Finish**
Stage the resolved files and complete the operation: `git commit` for a merge,
`git rebase --continue` for a rebase (repeating until every commit is replayed),
`git cherry-pick --continue` for a cherry-pick.

**Step 6 — Report**
State which files conflicted, what you kept from each side, and every trade-off made.
If any resolution was a judgement call rather than a clear merge, say so explicitly —
that is the part the user needs to check.
