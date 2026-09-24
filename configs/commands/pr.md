Prepare a pull request for the current branch. Context: $ARGUMENTS

Design sources: Google engineering practices (small changes; a description whose first line says what and whose body says why), the SmartBear / Cisco review study (defect detection drops sharply past ~400 changed lines), GitHub's docs on closing keywords, templates, CODEOWNERS and drafts, and the 2026 study of AI-agent PRs (arXiv 2601.04886) — descriptions claiming changes the diff doesn't contain were the most common inconsistency, and inconsistent PRs were accepted far less often and merged far more slowly.

**Step 1 — Pre-flight (stop on any failure)**
- **Base branch**: the repo's real default, not an assumed `main`: `git symbolic-ref --short refs/remotes/origin/HEAD` (fall back to `gh repo view --json defaultBranchRef`).
- **Not on the base branch.** If you are, stop — create a branch first.
- **Working tree**: `git status`. Uncommitted changes → ask whether to commit them first (conventional-commit subject under 72 chars; body says why, not what).
- **Up to date**: `git fetch`, then count commits the base has that this branch lacks. If behind, say so and ask whether to rebase or merge first.
- **Pushed**: the branch has an upstream and nothing unpushed; push if needed.
- **No secrets** in `git diff <base>...HEAD`. A PR publishes its diff.

**Step 2 — Gather**
- `git log <base>..HEAD --oneline` and `git diff <base>...HEAD --stat`, then read the diff itself.
- **PR template**: `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/`, a root or `docs/` template. If one exists, fill **its** structure instead of the default below.
- **CODEOWNERS**: who will be requested automatically.
- **Linked issues**: issue numbers in the branch name, commit messages or $ARGUMENTS.
- **Project conventions**: `CLAUDE.md` / `CONTRIBUTING.md` rules on titles, trailers and attribution win over defaults here.

**Step 3 — Size check**
Over ~400 changed lines (excluding lockfiles and generated files), say so and point out any clean split. Suggest splitting or stacking; do not restructure the branch unasked.

**Step 4 — Write the description from the diff**
- **Title**: imperative summary of the change — reuse the conventional-commit subject if the commits use them.
- **Why**: the problem this solves and why this approach.
- **What changed**: grouped by intent, each bullet traceable to a hunk.
- Then **re-read the diff against every bullet** and delete any claim the diff does not support. Name what reviewers should look at hardest — including anything the change affects that is NOT in the diff (callers of a changed function, a guard now bypassed).

**Step 5 — Test plan from evidence**
List the commands actually run and their results (`pytest -q → 214 passed`), discovered from `package.json`, `Makefile`, `justfile` or CI config. If tests were not run, say so plainly — never write "tested locally". Add screenshots for UI changes, and a breaking-change / migration section only when the diff changes a public API, schema or config format.

**Step 6 — Create**
Write the body to a file (the Write tool, in the scratchpad or `$TMPDIR`) and pass it with `--body-file`. **Never pass the body inline with `--body`**: backticks and `$(...)` in markdown are executed by the shell as command substitution, silently corrupting the description or running commands.

```bash
gh pr create --base <base> --title "<title>" --body-file <path> [--draft]
```

Use `--draft` when tests are failing or the work is exploratory — drafts do not notify code owners. If `gh` is unavailable, print the title and body for manual creation.

**Step 7 — Report**
The PR URL, the reviewers that will be requested, and any claim in the description you could not verify from the diff.

**Default description** (only when the repo has no template):
```
## Why
[the problem and why this approach]

## What changed
- [grouped by intent — each traceable to the diff]

## Test plan
- `[command]` → [result]

## Review focus
[riskiest part · anything affected outside the diff]

Closes #[N]
```
Add `## Breaking changes` (with migration steps) and `## Screenshots` only when they apply.
