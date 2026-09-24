Resolve an in-progress merge or rebase conflict. Context: $ARGUMENTS

Design sources: git's own merge machinery (`zdiff3`, stage blobs, `rerere`, `git log --merge`), Fowler on semantic conflicts (a clean text merge that breaks the build or behaviour), and the evidence on automated merging — purpose-built neural mergers (MergeBERT, DeepMerge) resolve only about 55–69% of conflicts correctly, so a hunk you had to judge is a guess until verified.

**Step 1 — See the actual state**
Run `git status` and `git diff --name-only --diff-filter=U` for the conflicted files.
Identify whether this is a merge, a rebase, or a cherry-pick — the finish step differs, and so does the meaning of "ours" and "theirs":

- **merge** — *ours* is your current branch, *theirs* is the branch coming in.
- **rebase** — *reversed*: *ours* is the branch you are rebasing ONTO, *theirs* is your own commit being replayed.
- **cherry-pick** — *ours* is your current branch, *theirs* is the picked commit.

Never pick a side by its label. Open the file and read the content.

Turn on `git config rerere.enabled true` for this repo if it is off: git then records each resolution and replays it when the same conflict reappears, which a long rebase will do.

**Step 2 — Recover the intent behind each side**
For every conflicted file, find out *why* each side changed. `git log --merge -p <file>`
shows the commits that touched it on both branches; read their messages, and the PR or
issue if the message points at one.

**See the common ancestor.** `git checkout --conflict=zdiff3 <file>` re-writes the markers with the base version in the middle, so you can see what each side changed *from*. Without it you cannot tell an addition from a revert. The raw versions are also available as `git show :1:<file>` (base), `:2:` (ours), `:3:` (theirs).

Resolving without this is guessing. A conflict is two intentions colliding, and you
cannot preserve an intention you never read.

**Step 3 — Resolve each file, by type**
- **Source** —
  - Preserve **both** intents wherever they compose.
  - Where they genuinely conflict, keep the one matching the stated goal of this merge and say which trade-off you made and why.
  - Do **not** invent behaviour that was on neither side. A conflict is not a licence to redesign — that change belongs in its own commit where it can be reviewed.
- **Lockfiles and generated files** (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `Cargo.lock`, `go.sum`, codegen output) — **never hand-merge.** Resolve the source (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, the schema), then regenerate with the project's own tool and stage the result. A hand-merged lockfile can be valid syntax and a broken dependency graph.
- **Deleted on one side, changed on the other** (`deleted by us` / `deleted by them`) — decide whether the change still matters where the code went (a rename or move) or the deletion wins. Don't blindly re-add the file.
- **Binary files** — can't be merged. Choose one version deliberately, after confirming which is intended.

Never `git merge --abort` to escape a hard conflict unless the user asks. Aborting
discards the resolution work and the next attempt starts from the same place. Abort
is right only when the operation itself was the mistake: wrong base, wrong branch, or
the wrong commits being replayed — and then say so.

**Step 4 — Look for conflicts git did not report**
Both sides can merge cleanly and still break together: a function renamed on one side and newly called on the other, a helper deleted while a new caller appears, a signature change with new call sites, a guard removed that a new code path relies on. For every symbol either side renamed, removed or re-signatured, search the **whole tree** for callers — not just the conflicted files.

**Step 5 — Verify against the project's own checks**
Discover them rather than assuming: look at `package.json` scripts, `Makefile`,
`.github/workflows/`, `justfile`. Run typecheck, then tests, then formatter — in that
order, since a type error makes test failures unreadable. Then `git diff --check`: it
reports leftover conflict markers and whitespace errors. A committed marker is a broken
build git will not otherwise warn you about.

A conflict resolution that compiles is not correct. It is the minimum bar for finding
out whether it is correct.

**Step 6 — Finish**
Stage the resolved files and complete the operation: `git commit` for a merge,
`git rebase --continue` for a rebase (repeating until every commit is replayed),
`git cherry-pick --continue` for a cherry-pick.

**Step 7 — Report**
```
OPERATION: [merge | rebase | cherry-pick] — ours = [...], theirs = [...]

| file | kept from each side | trade-off | confidence |
|---|---|---|---|
| [path] | [...] | [none | what was chosen and why] | [clear | judgement call] |

REGENERATED: [lockfiles / generated files — with the command used]
SEMANTIC CHECK: [symbols searched — callers found and fixed | none affected]
VERIFIED: [command → result, for typecheck / tests / formatter / git diff --check]
CHECK THESE: [every judgement-call hunk the user should read]
```
