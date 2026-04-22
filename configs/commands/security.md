Run a structured security review of: $ARGUMENTS

Anchor to OWASP Top 10. Be specific — file paths, line numbers, evidence. No generic advice.

**Before starting:** read the files in scope. Do not review code you haven't read.

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
SECURITY REVIEW: [scope]
Date: [date]
Files reviewed: [count]

FINDINGS:
[findings grouped by severity, highest first]

SUMMARY: [X critical, Y high, Z medium, W low]
RECOMMENDATION: [one-line — safe to ship / needs fixes / stop and remediate]
```
