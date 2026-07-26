# Claude Supercharger — shared code-vulnerability patterns
# Single source of truth for the CONTENT-based code-vuln checks, imported by both
# code-security-scanner.sh (PreToolUse write-time, per file) and commit-guard.sh
# (PreToolUse:Bash commit-time, staged diff). Keeping them here means the two
# enforcement points can't drift — mirrors lib-secret-patterns.sh for secrets.
#
# Scope: content patterns only. Secret-value detection lives in
# lib-secret-patterns.sh; path-based checks (GH-Actions workflow, shell-metachar
# file paths) and zero-width-unicode stay in code-security-scanner.sh because they
# depend on the file path / are prompt-injection concerns, not committable code vulns.
import re

# (compiled-pattern, message) — case-sensitive content checks.
_CHECKS = [
    # --- JavaScript / TypeScript ---
    (re.compile(r'eval\('),                       'eval() — arbitrary code execution risk'),
    (re.compile(r'\.innerHTML[ \t]*='),           '.innerHTML = — XSS risk; use textContent or a sanitizer'),
    (re.compile(r'dangerouslySetInnerHTML'),      'dangerouslySetInnerHTML — React XSS risk; sanitize input before use'),
    (re.compile(r'document\.write\('),            'document.write() — XSS risk'),
    (re.compile(r'new Function\('),               'new Function() — code injection risk'),
    (re.compile(r'child_process\.exec\(|\.execSync\('), 'child_process.exec()/execSync() — command injection risk; use execFile/spawn with an args array'),
    (re.compile(r'shell[ \t]*:[ \t]*true'),       'shell: true in a child_process call — command injection risk; pass args as an array, no shell'),
    (re.compile(r'\.insertAdjacentHTML\('),       'insertAdjacentHTML — XSS risk; sanitize input or use textContent'),
    (re.compile(r'\.outerHTML[ \t]*='),           '.outerHTML = — XSS risk; use textContent or a sanitizer'),
    (re.compile(r'crypto\.createCipher\('),       'crypto.createCipher() — deprecated & insecure (no IV); use createCipheriv with a random IV'),
    # --- Python ---
    (re.compile(r'pickle\.loads?\('),             'pickle.load(s)() — unsafe deserialization; never unpickle untrusted data'),
    (re.compile(r'(?:^|[^a-zA-Z_])(?:exec|compile)\('), 'exec()/compile() — arbitrary code execution risk'),
    (re.compile(r'os\.system\('),                 'os.system() — shell injection risk; prefer subprocess with a list of args'),
    (re.compile(r'os\.popen\('),                  'os.popen() — shell injection risk; prefer subprocess with a list of args'),
    (re.compile(r'subprocess\.(?:call|run|Popen).*shell[ \t]*=[ \t]*True'), 'subprocess with shell=True — shell injection risk; pass args as a list instead'),
    (re.compile(r'yaml\.load\('),                 'yaml.load() — unsafe deserialization; use yaml.safe_load()'),
    (re.compile(r'__import__\('),                 '__import__() — dynamic import injection risk'),
    # --- Cross-language unsafe deserialization ---
    (re.compile(r'(?:^|[^a-zA-Z_])unserialize\('),'unserialize() — PHP object-injection risk; never unserialize untrusted data'),
    (re.compile(r'Marshal\.load\('),              'Marshal.load() — Ruby unsafe deserialization; never load untrusted data'),
    (re.compile(r'ObjectInputStream'),            'ObjectInputStream — Java unsafe deserialization; validate/avoid on untrusted data'),
    # --- SQL injection ---
    (re.compile(r'f"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*\{'), 'f-string SQL query — SQL injection risk; use parameterised queries'),
    (re.compile(r'"(?:SELECT|INSERT|UPDATE|DELETE)[^"]*"[ \t]*\+'), 'string-concatenated SQL query — SQL injection risk; use parameterised queries'),
    # --- Weak hashing ---
    (re.compile(r"crypto\.createHash\(['\"](?:md5|sha1)['\"]|hashlib\.(?:md5|sha1)\("), 'MD5/SHA-1 hashing — cryptographically broken; use SHA-256 or bcrypt for passwords'),
    # --- Obfuscated payload ---
    (re.compile(r'atob\(|btoa\(|base64[._-]?decode|b64decode'), 'base64 decode in code — check for obfuscated prompt injection or payload'),
]

# Insecure randomness is gated on a security-context word nearby — a blind
# Math.random()/random.* match would be far too noisy for ordinary jitter/shuffle.
_SECCTX = re.compile(r'token|secret|password|passwd|nonce|salt|otp|api[_-]?key|session[_-]?id|csrf|reset', re.I)
_MATH_RANDOM = re.compile(r'Math\.random\(')
_PY_RANDOM = re.compile(r'(?:^|[^a-zA-Z_])random\.(?:random|randint|choice|randrange|getrandbits)\(')


def scan_content(content):
    """Return an ordered, de-duplicated list of code-vuln warning messages for `content`."""
    if not content:
        return []
    hits = []
    for rx, msg in _CHECKS:
        if rx.search(content):
            hits.append(msg)
    if _MATH_RANDOM.search(content) and _SECCTX.search(content):
        hits.append('Math.random() used near a token/secret — not cryptographically secure; use crypto.getRandomValues() / crypto.randomBytes()')
    if _PY_RANDOM.search(content) and _SECCTX.search(content):
        hits.append('random module used near a token/secret — not cryptographically secure; use the secrets module')
    seen, out = set(), []
    for h in hits:
        if h not in seen:
            seen.add(h); out.append(h)
    return out
