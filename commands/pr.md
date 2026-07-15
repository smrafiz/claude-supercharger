Prepare a pull request for the current branch. Context: $ARGUMENTS

**Step 1 — Verify branch state**
Run `git status` and `git diff --stat`. If there are uncommitted changes, ask whether to commit them first.

**Step 2 — Gather context**
- Run `git log main..HEAD --oneline` (or appropriate base branch) to see all commits
- Run `git diff main...HEAD --stat` for the full diff summary
- Read any modified test files to confirm tests exist

**Step 3 — Write commit message (if uncommitted changes)**
Follow conventional commits. Keep subject under 72 chars. Body explains why, not what.

**Step 4 — Write PR description**
Generate using `gh pr create` format:

```
## Summary
[2-3 bullet points: what changed and why]

## Changes
[file-level summary grouped by intent]

## Test plan
- [ ] [specific test to run]
- [ ] [edge case to verify]
- [ ] [regression to check]

## Breaking changes
[none, or specific breakage + migration path]
```

**Step 5 — Create PR**
Use `gh pr create --title "..." --body "..."`. If `gh` is not available, output the PR body for manual creation.

**Step 6 — Report**
Print the PR URL when done.
