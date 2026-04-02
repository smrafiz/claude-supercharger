# Security Audit Report — Claude Supercharger v1.5.0

**Date:** 2026-04-02
**Scope:** Full codebase security analysis (41 bash scripts, 16 config templates, 80+ files)
**Risk Level:** LOW-MEDIUM (no critical vulnerabilities found)

---

## Executive Summary

Claude Supercharger is a zero-dependency Bash toolkit that deploys safety guardrails into Claude Code. The codebase demonstrates strong security awareness — safety hooks, file permissions, umask usage, credential detection. However, several issues were identified across credential storage, input handling, and bypass vectors.

| Severity | Count |
|----------|-------|
| CRITICAL [10] | 0 |
| HIGH [7-9] | 3 |
| MEDIUM [4-6] | 5 |
| LOW [1-3] | 4 |

---

## Findings

### HIGH [9] — Webhook Credentials Stored in Plaintext JSON

**Files:** `lib/webhook.sh`, `tools/webhook-setup.sh`, `hooks/notify.sh`, `hooks/session-complete.sh`
**Description:** Webhook credentials (Slack URLs, Discord URLs, Telegram bot tokens, custom webhook URLs) are stored in `~/.claude/supercharger/webhook.json` as plaintext JSON. While `webhook-setup.sh` sets `chmod 600`, the `write_config()` function defined at line 128 is never actually called — the config is written directly via python3 redirection at lines 143-146, 154-157, 169-172, 179-182 without setting permissions. The `chmod 600` at line 191 runs after but only for the final path.

**Risk:** If file permissions are not properly set (race condition between write and chmod), or if backups include this file, credentials could be exposed. Backup directory copies (`~/.claude/backups/`) may not preserve the restrictive permissions.

**Remediation:**
1. Use `write_config()` function consistently (it sets chmod 600 atomically)
2. Write to a temp file with restrictive permissions, then `mv` into place
3. Consider using OS keychain (macOS Keychain, Linux Secret Service) instead of plaintext
4. Exclude `webhook.json` from backups, or encrypt it

---

### HIGH [8] — MCP API Keys Stored in settings.json Without Protection

**File:** `tools/mcp-setup.sh:164`
**Description:** When users configure advanced MCP servers (GitHub, Brave, Slack, Notion, Sentry, Figma), API keys/tokens are written directly into `~/.claude.json` and `~/.claude/settings.json` as plaintext environment variables in the `env` field. These files have no special permission restrictions set by the installer.

**Risk:** API keys in settings.json are readable by any process running as the user. The files may be backed up, synced, or read by other tools. Claude Code itself may expose these in logs or transcripts.

**Remediation:**
1. Set `chmod 600` on `~/.claude.json` and `~/.claude/settings.json` after writing
2. Document that users should use environment variables instead of embedding keys
3. Consider prompting users to set keys via shell env rather than storing in JSON

---

### HIGH [7] — Safety Hook Bypass via Command Chaining/Subshells

**File:** `hooks/safety.sh`
**Description:** The safety hook parses the `command` field from Claude's tool input and applies regex-based blocking. However, several bypass vectors exist:

1. **Subshell execution:** `bash -c "rm -rf /"` — the hook sees `bash -c "rm -rf /"` but only strips `sudo/command/env` prefixes, not `bash -c`
2. **Variable expansion:** `CMD="rm -rf /"; $CMD` — two separate commands, hook only sees the assignment
3. **Here-doc execution:** `bash <<< "rm -rf /"` — not matched by patterns
4. **Base64 encoding:** `echo cm0gLXJmIC8= | base64 -d | bash`
5. **File execution:** `echo "rm -rf /" > /tmp/x.sh && bash /tmp/x.sh`
6. **Newline in command:** Commands with embedded newlines may only have the first line checked

**Risk:** A determined agent could bypass safety hooks through indirect execution. However, this is defense-in-depth — Claude Code's own safety mechanisms are the primary barrier.

**Remediation:**
1. Also block `bash -c`, `sh -c`, `zsh -c`, `eval` patterns
2. Block `| bash`, `| sh` (partially done for curl/wget but not generalized)
3. Block `base64.*|.*bash` patterns
4. Document that safety hooks are a secondary defense layer, not a sandbox

---

### MEDIUM [6] — Credential Pattern Detection Gaps

**File:** `hooks/safety.sh:77-84`
**Description:** The credential detection patterns miss several common formats:

- **Azure:** No detection for Azure connection strings or SAS tokens
- **Google Cloud:** No `AIza` (Google API key) pattern
- **Stripe:** No `sk_live_` or `pk_live_` patterns
- **npm:** No `npm_` token pattern
- **PyPI:** No `pypi-` token pattern
- **Generic passwords:** No `PASSWORD=`, `DB_PASSWORD=`, `MYSQL_ROOT_PASSWORD=` patterns
- **JWT tokens:** No `eyJ` (base64 JWT header) detection
- **Private keys:** No `-----BEGIN.*PRIVATE KEY-----` detection

**Remediation:** Expand `CRED_PATTERNS` array with additional patterns. Consider using a dedicated secrets scanner (e.g., truffleHog patterns) as reference.

---

### MEDIUM [6] — Duplicated Webhook Code (DRY Violation with Security Implications)

**Files:** `hooks/notify.sh:24-67`, `hooks/session-complete.sh:35-78`, `lib/webhook.sh:42-86`
**Description:** The webhook sending logic is duplicated across 3 files with near-identical Python code. `lib/webhook.sh` exists as a shared library, but `notify.sh` and `session-complete.sh` embed their own copies instead of sourcing it. This means security fixes to webhook handling must be applied in 3 places.

**Risk:** A fix applied to one copy but not others creates inconsistent security posture. For example, adding URL validation or TLS verification would need to be done 3 times.

**Remediation:** Have `notify.sh` and `session-complete.sh` source `lib/webhook.sh` and call `send_webhook()` instead of embedding duplicate Python code.

---

### MEDIUM [5] — No URL Validation for Webhook Endpoints

**Files:** `tools/webhook-setup.sh`, `lib/webhook.sh`
**Description:** Webhook URLs are accepted without validation. Users could accidentally configure:
- HTTP (not HTTPS) endpoints, sending notifications in cleartext
- Internal network URLs (SSRF-adjacent, though user-initiated)
- Malformed URLs causing silent failures

**Remediation:**
1. Validate that URLs start with `https://` (warn on `http://`)
2. Basic URL format validation before storing
3. Verify the URL responds before saving config

---

### MEDIUM [5] — Audit Trail Not Protected Against Tampering

**File:** `hooks/audit-trail.sh`
**Description:** Audit logs are written to `~/.claude/supercharger/audit/*.jsonl` as plain JSONL files. There is no integrity protection (no checksums, no append-only enforcement). Any process running as the user can modify or delete audit entries.

**Risk:** If audit trails are relied upon for compliance or forensics, they can be trivially tampered with.

**Remediation:**
1. Set audit files to append-only (`chattr +a` on Linux, not available on macOS)
2. Add a running hash/checksum for tamper detection
3. Or document that audit trail is informational only, not forensic-grade

---

### MEDIUM [5] — project-config.sh Trusts Arbitrary JSON from Project Root

**File:** `hooks/project-config.sh`
**Description:** The hook walks up 5 directory levels looking for `.supercharger.json` and loads it, outputting its contents as a `systemMessage` to Claude. If a user clones a malicious repo containing a crafted `.supercharger.json`, it could inject arbitrary instructions into Claude's system prompt via the `hints` field.

**Risk:** Prompt injection via a committed `.supercharger.json` file in a third-party repo. The `hints` field is passed directly into the system message without sanitization.

**Remediation:**
1. Sanitize the `hints` field — strip control characters, limit length
2. Add a warning when loading project config from a repo not owned by the user
3. Consider requiring explicit user confirmation before loading project-level configs
4. Limit `hints` to alphanumeric + basic punctuation

---

### LOW [3] — chmod 755 on Hook Scripts (Group/World Executable)

**File:** `lib/hooks.sh:43`
**Description:** `chmod +x "$target_dir/"*.sh` makes hooks executable by all users. While the parent directory `~/.claude/supercharger/` is `chmod 700`, the individual files inside are `chmod 755`. If directory permissions are changed, hooks become world-readable.

**Remediation:** Use `chmod 700` instead of `chmod +x` for hook scripts.

---

### LOW [3] — No TLS Certificate Verification in Webhook Calls

**Files:** `lib/webhook.sh`, `hooks/notify.sh`, `hooks/session-complete.sh`
**Description:** All `curl` calls use `-s` (silent) but don't explicitly verify TLS certificates. While curl verifies by default, there's no `--fail` flag to detect HTTP errors, and no `--proto =https` to enforce HTTPS-only.

**Remediation:** Add `--fail --proto =https` to curl invocations.

---

### LOW [2] — Silent Error Swallowing in Webhook Code

**Files:** `lib/webhook.sh:84`, `hooks/notify.sh:65`, `hooks/session-complete.sh:76`
**Description:** All webhook Python code has bare `except: pass` blocks, silently swallowing all errors. This makes debugging webhook issues extremely difficult and could mask security-relevant errors.

**Remediation:** Log errors to stderr or audit trail instead of silently passing.

---

### LOW [2] — git-safety.sh Does Not Block `git push --force-with-lease` to Protected Branches

**File:** `hooks/git-safety.sh:29`
**Description:** Only `--force` and `-f` are checked. `--force-with-lease` (which can still overwrite remote history) is not blocked for protected branches.

**Remediation:** Add `--force-with-lease` to the force-push detection pattern.

---

## Positive Security Findings

The following security practices are well-implemented:

1. **umask 077** — Set in `install.sh` and `uninstall.sh` for secure file creation
2. **set -euo pipefail** — Used in all critical scripts, preventing silent failures
3. **Sudo/env prefix stripping** — Safety hook strips `sudo`, `command`, `env` prefixes to prevent trivial bypasses
4. **Self-modification prevention** — Safety hook blocks writes to `.claude/settings.json` and `.claude/CLAUDE.md`
5. **Credential leak detection** — Detects AWS AKIA, GitHub ghp_, OpenAI sk- patterns in commands
6. **Backup on install** — Existing configs are backed up before modification
7. **30-day audit rotation** — Prevents unbounded disk usage
8. **No external dependencies** — Zero npm/pip/brew dependencies, reducing supply chain risk
9. **Production access warnings** — Warns when kubectl/docker exec targets prod containers
10. **Confirmation before uninstall** — Requires explicit y/N confirmation

---

## Compliance Status

| Check | Status |
|-------|--------|
| No hardcoded secrets in codebase | PASS |
| No .env files committed | PASS |
| Secrets detection in safety hook | PASS (with gaps noted) |
| File permissions on sensitive data | PARTIAL (webhook.json OK, settings.json not restricted) |
| Audit trail present | PASS (informational grade) |
| Backup security | PARTIAL (backup perms set, but may contain credentials) |
| Input validation | PARTIAL (project-config.sh trusts JSON hints) |
| Network security | PARTIAL (no HTTPS enforcement, no cert pinning) |

---

## Recommended Priority Actions

1. **[HIGH]** Add `bash -c`, `sh -c`, `eval` to safety hook bypass prevention
2. **[HIGH]** Set `chmod 600` on `~/.claude.json` and `~/.claude/settings.json` after MCP key setup
3. **[HIGH]** Sanitize `hints` field in `project-config.sh` to prevent prompt injection
4. **[MEDIUM]** Deduplicate webhook code — use `lib/webhook.sh` everywhere
5. **[MEDIUM]** Expand credential detection patterns
6. **[MEDIUM]** Add HTTPS URL validation for webhooks
