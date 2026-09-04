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

**Before reporting anything, confirm reachability.** A pattern match is not a finding —
the most common failure mode in an automated security pass is reporting unreachable or
already-mitigated code, which buries the real issues. Before writing up a finding, confirm:

1. **Is the input actually attacker-controlled?** Trace it to a real entry point — a request
   parameter, header, cookie, upload, webhook, queue message, or third-party API response. A
   value that only ever comes from a constant, an enum, or trusted internal config is not an
   injection source.
2. **Is the sink reachable with that input?** Check for validation, an allowlist, an ORM, or a
   framework control sitting between them — auth middleware, a base controller, a decorator —
   before flagging a route as unprotected; enforcement is often centralized rather than per-route.
3. **What is the blast radius?** Who can trigger it, what do they get, does it cross a trust
   boundary? SSRF reaching cloud metadata is not the same finding as one reaching localhost only.

State the concrete path — *this input reaches this sink* — for every finding. If reachability
can't be determined from the code in scope, say that explicitly rather than asserting either way.

**Dimensions to check (in order):**

1. **Injection** — SQL, command, LDAP, XPath, template injection. Check string concatenation in queries, shell commands, eval/exec.
2. **Authentication** — hardcoded credentials, weak password rules, missing rate limits, session fixation.
3. **Sensitive data exposure** — secrets in code/config/logs, missing encryption at rest or in transit, PII in error messages.
4. **Access control** — missing authorization checks, IDOR, privilege escalation, default-allow patterns.
5. **Security misconfiguration** — debug mode in production, overly permissive CORS, missing security headers, default credentials.
6. **Supply chain** — run `npm audit` / `pip-audit` / `cargo audit` if applicable and flag known CVEs, but also check beyond known-CVE matching: unpinned/floating dependency versions, missing lockfile commit, unsigned or unverified packages, `curl | sh` install scripts in the build pipeline.
7. **Cryptography** — MD5/SHA1 for security, hardcoded IVs/keys, custom crypto implementations.
8. **Insecure design** — missing rate limiting or abuse controls, security decisions left to the client, no threat model for a sensitive flow (payments, auth, data export).
9. **Integrity failures** — insecure deserialization of untrusted data, missing Subresource Integrity on CDN-loaded scripts, auto-update or plugin mechanisms that don't verify signatures.
10. **Logging & alerting** — security-relevant events (auth failures, access-control denials, admin actions) that aren't logged at all, or logged without enough context to investigate later.

**For each finding:**

```
[CRITICAL/HIGH/MEDIUM/LOW] [Category]
  File: [path:line]
  Issue: [what's wrong]
  Evidence: [the code]
  Fix: [specific remediation]
```

**Before returning the report, grade it against these checks.** Answer each one pass or
fail. Fix every failure and re-run the checks. Do not include the checklist or its results
in your output — the reader gets the corrected report, not the grading.

A review is written finding by finding, but it fails as a whole: the usual damage is a
plausible-looking report that buries two real issues under six that were never reachable.
These checks are read against the finished report, which is the only point where that is
visible.

*Evidence*
1. Does every finding quote code that actually exists at the `file:line` given, in scope,
   read this session — not recalled, inferred, or reconstructed?
2. Is every CVE id, version number, and dependency name copied from real command output or
   a file in scope, rather than recalled?
3. Do supply-chain findings cite the audit command that produced them, and does the report
   say so plainly if no audit tool was available?

*Reachability*
4. Does every finding state a concrete path — this attacker-controlled input reaches this
   sink — or say explicitly that reachability could not be determined from the code in scope?
5. Was each flagged sink checked for a control sitting in front of it (middleware, ORM,
   allowlist, decorator, base class) before being reported?
6. Is any finding a bare pattern match — the shape of a vulnerability with no argument that
   it is one? Those are removed, not downgraded.

*Calibration*
7. Does each severity follow from blast radius — who triggers it, what they get, which trust
   boundary it crosses — rather than from the category name?
8. Are findings that share one root cause reported once, at the root, instead of once per
   call site?

*Usefulness*
9. Apply the portability test to every Fix: if the text could be pasted into an unrelated
   repository unchanged, it is generic advice. Replace it with the specific change to this
   code, or cut it.
10. Do the counts in SUMMARY match the findings listed, and does RECOMMENDATION follow from
    the highest severity present?

*Honesty*
11. If the scope was too small to answer a question the reader will have, does the report say
    what was not covered — rather than implying the absence of findings is a clean bill?
12. An empty FINDINGS section is a valid result. Is any finding present only to avoid
    returning nothing?

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
