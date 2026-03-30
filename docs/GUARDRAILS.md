# Guardrails System

Project-specific constraints that ensure code quality, security, accessibility, performance, and ethical standards.

---

## What Are Guardrails?

**Guardrails** are domain-specific rules that Claude Supercharger enforces during code generation. They prevent common mistakes, ensure compliance, and maintain project standards.

**Benefits:**
- ✅ Security vulnerabilities caught before commit
- ✅ Accessibility compliance automated
- ✅ Performance budgets enforced
- ✅ Ethical standards maintained
- ✅ Domain regulations respected (HIPAA, GDPR, PCI DSS)

---

## Quick Start

### 1. Copy Template

```bash
cp shared/guardrails-template.yml docs/AGENT_GUARDRAILS.md
```

### 2. Customize for Your Domain

Edit `docs/AGENT_GUARDRAILS.md` with your project's constraints.

### 3. Reference in Project CLAUDE.md

```markdown
## Guardrails
@docs/AGENT_GUARDRAILS.md

Critical constraints MUST be enforced.
High constraints strongly encouraged.
Medium constraints apply when practical.
```

### 4. Test Guardrails

```
You: "Create a login form"

Claude checks guardrails:
✓ Accessibility: Form inputs have labels (CRITICAL)
✓ Security: Password not stored in localStorage (CRITICAL)
✓ UX: Error messages are clear (HIGH)
```

---

## Severity Levels

| Level | Meaning | Enforcement |
|-------|---------|-------------|
| **CRITICAL** | Must never violate | BLOCK - Code generation stops |
| **HIGH** | Strong preference | WARN - Highlight violation, require acknowledgment |
| **MEDIUM** | Apply when practical | SUGGEST - Offer improvement, allow override |

---

## Guardrail Categories

### Security
Prevents vulnerabilities (OWASP Top 10, authentication, data protection)

**Examples:**
- NEVER expose API keys in client code
- ALWAYS validate and sanitize user input
- Use parameterized queries (prevent SQL injection)

### Performance
Ensures fast, responsive applications

**Examples:**
- Bundle size <500KB initial load
- Core Web Vitals: LCP <2.5s, FID <100ms
- Database queries <100ms

### Accessibility
WCAG 2.2+ compliance for inclusive design

**Examples:**
- ALL interactive elements keyboard accessible
- Color contrast ≥4.5:1 (WCAG AA)
- Semantic HTML structure

### Code Quality
Maintainability and best practices

**Examples:**
- Functions <50 lines
- Test coverage >80% for critical paths
- No console.log in production

### Ethics
User-respectful design

**Examples:**
- NEVER implement dark patterns
- User consent before data collection
- Clear unsubscribe mechanisms

### Compliance
Regulatory requirements (HIPAA, GDPR, PCI DSS)

**Examples:**
- PHI encrypted at rest and in transit
- GDPR: User data deletion within 30 days
- PCI DSS: No plaintext credit card storage

---

## Domain Examples

Pre-configured guardrails for common project types:

| Domain | File | Focus |
|--------|------|-------|
| Web App | `examples/guardrails/web-app.yml` | WCAG, OWASP, Core Web Vitals |
| API Service | `examples/guardrails/api-service.yml` | Security, rate limiting, monitoring |
| Game Dev | `examples/guardrails/game-dev.yml` | FPS budgets, comfort-first, no dark patterns |
| Mobile App | `examples/guardrails/mobile-app.yml` | Battery, offline-first, platform guidelines |
| Agent Safety | `examples/guardrails/agent-safety.yml` | Four Laws, halt conditions, scope boundaries |

### Agent Safety Guardrails

Beyond domain constraints, Claude Supercharger provides **agent safety guardrails** — rules that govern how AI agents behave when operating on your codebase.

**Full template:** `shared/agent-guardrails-template.md`

**Key features:**
- **Four Laws** — Read before editing, stay in scope, verify before committing, halt when uncertain
- **Halt Conditions** — 15 triggers that force immediate stop
- **Forbidden Actions** — Hard prohibitions on file, code, git, system, and data operations
- **Scope Boundaries** — Clear IN/OUT scope definitions per task
- **Test/Production Separation** — Prevent cross-contamination
- **Escalation Matrix** — When agents must defer to humans

**Setup:**
```bash
cp shared/agent-guardrails-template.md docs/AGENT_GUARDRAILS.md
# Customize the PROJECT-SPECIFIC RULES section
# Reference in CLAUDE.md: @docs/AGENT_GUARDRAILS.md
```

---

## Creating Custom Guardrails

### Step 1: Identify Constraints

List your project's critical requirements:

**Security:**
- What data needs protection?
- What authentication is required?
- What attacks must be prevented?

**Performance:**
- What are your speed requirements?
- What are your resource limits?
- What metrics matter most?

**Compliance:**
- What regulations apply (HIPAA, GDPR, PCI DSS)?
- What industry standards must be met?
- What audit requirements exist?

### Step 2: Categorize by Severity

**CRITICAL** - Violation causes:
- Security breach
- Legal liability
- System failure
- User harm

**HIGH** - Violation causes:
- Poor user experience
- Maintainability issues
- Performance degradation
- Accessibility barriers

**MEDIUM** - Violation causes:
- Suboptimal implementation
- Technical debt
- Minor UX friction

### Step 3: Write Clear Rules

**Good guardrail:**
```yaml
critical:
  - "NEVER store passwords in plaintext - use bcrypt with 12+ rounds"
```

**Bad guardrail:**
```yaml
critical:
  - "Make passwords secure"  # Too vague
```

**Format:**
- Start with action: NEVER, ALWAYS, MUST, AVOID
- Be specific: What exactly is required/forbidden?
- Include rationale when not obvious

### Step 4: Add Enforcement

Specify how violations are caught:

```yaml
enforcement:
  pre_commit:
    - "ESLint: no-console rule"
    - "TypeScript: strict mode enabled"

  pre_deploy:
    - "Lighthouse CI: Accessibility score ≥95"
    - "npm audit: Zero high/critical vulnerabilities"

  continuous:
    - "Sentry: Error rate alert if >1%"
    - "DataDog: API latency p95 <200ms"
```

---

## Usage Examples

### Example 1: Web App Guardrails

```yaml
security:
  critical:
    - "NEVER use dangerouslySetInnerHTML without sanitization"
    - "ALWAYS validate forms server-side (client validation is UX only)"

accessibility:
  critical:
    - "ALL images must have alt text (or role='presentation' if decorative)"
    - "Keyboard navigation must work for all interactive elements"

performance:
  high:
    - "Initial bundle size <300KB gzipped"
    - "Lighthouse Performance score ≥90"
```

**Claude applies these:**
```
You: "Add an image carousel"

Claude generates:
✓ Images have alt text (CRITICAL)
✓ Keyboard arrows navigate slides (CRITICAL)
✓ Lazy loading for off-screen images (HIGH)
✓ Swipe gestures for mobile (MEDIUM)
```

### Example 2: API Service Guardrails

```yaml
security:
  critical:
    - "NEVER trust user input - validate all request bodies"
    - "Rate limiting REQUIRED on all public endpoints"

performance:
  critical:
    - "Database queries MUST use indexes - no table scans"
    - "API response time p95 <200ms"

monitoring:
  high:
    - "ALL errors logged with context (user ID, request ID, stack trace)"
    - "Alert on error rate >1% over 5min window"
```

### Example 3: Mobile App Guardrails

```yaml
performance:
  critical:
    - "App launch time <2s on mid-range devices"
    - "Battery drain <5% per hour during normal use"

accessibility:
  critical:
    - "Support Dynamic Type (iOS) / Font scaling (Android)"
    - "VoiceOver / TalkBack navigation fully functional"

offline:
  high:
    - "Core features work offline with graceful degradation"
    - "Queue failed requests for retry when online"
```

---

## Testing Guardrails

### Manual Testing

```
You: "Create a user registration form"

Expected guardrails check:
- Password field type="password" (security)
- Labels associated with inputs (accessibility)
- Email validation on submit (quality)
- Loading state during submission (UX)
```

### Automated Testing

**Pre-commit hooks:**
```bash
# .husky/pre-commit
npm run lint          # Code quality
npm run type-check    # TypeScript
npm run test          # Unit tests
```

**CI/CD pipeline:**
```yaml
# .github/workflows/ci.yml
- name: Security Audit
  run: npm audit --audit-level=high

- name: Accessibility Test
  run: npm run test:a11y  # axe, pa11y

- name: Performance Budget
  run: npm run build && bundlesize
```

---

## Troubleshooting

### Guardrail Violation Ignored

**Problem:** Claude generated code violating guardrails

**Solutions:**
1. Check CLAUDE.md references guardrails file correctly
2. Verify guardrail severity (CRITICAL blocks, HIGH warns, MEDIUM suggests)
3. Make rule more specific (vague rules are hard to enforce)
4. Test with explicit request: "Check this against our guardrails"

### Overly Restrictive Guardrails

**Problem:** Guardrails block legitimate code

**Solutions:**
1. Lower severity (CRITICAL → HIGH → MEDIUM)
2. Add exceptions: "NEVER use eval() except in sandboxed runtime"
3. Provide escape hatch: "Acknowledge risk if intentional"

### Guardrails Not Loading

**Problem:** Claude doesn't apply project guardrails

**Solutions:**
1. Verify file location (`docs/AGENT_GUARDRAILS.md` or custom path)
2. Check CLAUDE.md has `@docs/AGENT_GUARDRAILS.md` reference
3. Restart Claude Code after adding guardrails

---

## Best Practices

1. **Start Simple** - Begin with 5-10 critical constraints, expand over time
2. **Be Specific** - "NEVER use eval()" > "Avoid dangerous code"
3. **Document Why** - Explain rationale for non-obvious rules
4. **Test Early** - Validate guardrails on small tasks before large features
5. **Iterate** - Refine based on false positives/negatives
6. **Team Alignment** - Ensure team agrees on constraints before enforcing
7. **Automate** - Use linters, tests, CI to catch violations automatically

---

## Integration with Other Tools

### ESLint

```js
// .eslintrc.js - Enforce guardrails at lint time
module.exports = {
  rules: {
    'no-console': 'error',              // Quality guardrail
    'no-eval': 'error',                 // Security guardrail
    '@typescript-any': 'error',         // Quality guardrail
  }
}
```

### Pre-commit Hooks

```bash
# .husky/pre-commit - Enforce before commit
npm run lint          # Code quality guardrails
npm run type-check    # TypeScript strictness
npm run test:security # Security guardrails (audit, Snyk)
```

### CI/CD

```yaml
# Lighthouse CI - Performance/accessibility guardrails
assertions:
  performance: ['>=90']
  accessibility: ['>=95']
  best-practices: ['>=90']
```

---

## Resources

- **Domain Template:** `shared/guardrails-template.yml`
- **Agent Safety Template:** `shared/agent-guardrails-template.md`
- **Examples:** `examples/guardrails/`
- **WCAG Guidelines:** https://www.w3.org/WAI/WCAG22/quickref/
- **OWASP Top 10:** https://owasp.org/www-project-top-ten/
- **Core Web Vitals:** https://web.dev/vitals/

---

*Claude Supercharger v1.0.0 | Domain-specific constraint enforcement*
