Run a structured security review of: $ARGUMENTS

Anchor to OWASP Top 10. Be specific — file paths, line numbers, evidence. No generic advice.

**Step 0 — Resolve scope from $ARGUMENTS** (diff-scoped review, mirrors `/security-review`). Pick the first that matches:

| $ARGUMENTS | Scope | How to get the diff |
|---|---|---|
| *(empty)* | **uncommitted changes** (default) | `git diff HEAD` plus staged (`git diff --cached`); if the tree is clean, fall back to the last commit `git show HEAD` |
| `staged` | staged changes only | `git diff --cached` |
| `branch` / `main..` / a base ref | **branch diff** vs the base | `git merge-base` then `git diff <base>...HEAD` |
| `pr <N>` / `#<N>` | **pull-request diff** | `gh pr diff <N>` (read-only; if `gh` is absent, say so and stop) |
| `commit <sha>` / a 7–40 hex sha | **single commit** | `git show <sha>` |
| file/dir paths | those files (whole-file review) | read the files directly |

For a diff scope, review **only the changed/added lines and the functions that contain them** — not the whole repo. State the resolved scope in the output header. If `$ARGUMENTS` is ambiguous, ask once, then proceed.

**Before starting:** read the files (or diff hunks) in scope. Do not review code you haven't read. All git/`gh` commands here are read-only — never modify the tree, stage, or commit.

**Dimensions to check (in order):**

1. **Injection** — SQL, command, LDAP, XPath, template injection. Check string concatenation in queries, shell commands, eval/exec.
2. **Authentication** — hardcoded credentials, weak password rules, missing rate limits, session fixation.
3. **Sensitive data exposure** — secrets in code/config/logs, missing encryption at rest or in transit, PII in error messages.
4. **Access control** — missing authorization checks, IDOR, privilege escalation, default-allow patterns.
5. **Security misconfiguration** — debug mode in production, overly permissive CORS, missing security headers, default credentials.
6. **Vulnerable dependencies** — run `npm audit` / `pip-audit` / `cargo audit` if applicable. Flag known CVEs.
7. **Cryptography** — MD5/SHA1 for security, hardcoded IVs/keys, custom crypto implementations.

**For each finding:**

```
[CRITICAL/HIGH/MEDIUM/LOW] [Category]
  File: [path:line]
  Issue: [what's wrong]
  Evidence: [the code]
  Fix: [specific remediation]
```

**Output format:**
```
SECURITY REVIEW: [scope — e.g. "uncommitted changes", "branch feat/x vs main", "PR #42", "commit a1b2c3d", or file list]
Date: [date]
Reviewed: [N files / N changed hunks]

FINDINGS:
[findings grouped by severity, highest first]

SUMMARY: [X critical, Y high, Z medium, W low]
RECOMMENDATION: [one-line — safe to ship / needs fixes / stop and remediate]
```
