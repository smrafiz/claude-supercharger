#!/usr/bin/env bash
# Claude Supercharger — Shared Secret-Detection Patterns
# Single source of truth for the SECRET_PATTERNS regex array. Sourcing this
# sets SECRET_PATTERNS in the caller's scope. Sourced by:
#   - output-secrets-scanner.sh  (scans tool OUTPUT — Bash/Read)
#   - commit-guard.sh     (scans the STAGED git diff at commit)
#   - sendmessage-guard.sh (scans a cross-session message body — SendMessage)
# ONE list prevents cross-channel parity drift — a secret caught in output but
# not at commit (or vice-versa) is exactly the divergence this file exists to
# prevent. Add a pattern here and BOTH channels gain it.
# Not executable on its own — it only defines an array.

# shellcheck disable=SC2034  # consumed by the sourcing hook, not this file
SECRET_PATTERNS=(
  # AWS access-key IDs
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  # AWS SECRET access-key VALUE — label + exact 40-char base64 value.
  # v2.22.0: case-insensitive label — the canonical ~/.aws/credentials + boto form
  # is lowercase `aws_secret_access_key`, which the upper-only pattern missed.
  '[Aa][Ww][Ss]_[Ss][Ee][Cc][Rr][Ee][Tt]_[Aa][Cc][Cc][Ee][Ss][Ss]_[Kk][Ee][Yy].{0,6}[A-Za-z0-9/+]{40}'
  # GitHub — classic ghp_/gho_/ghs_/ghu_ + refresh ghr_ (v2.22.0)
  'gh[oprsu]_[A-Za-z0-9_]{36,}'
  # GitHub fine-grained PAT (v2.22.0) — github_pat_<...>, 60+ tail
  'github_pat_[A-Za-z0-9_]{60,}'
  # Generic key/secret/token — anchor on <keyword><:|=><16+ char value>
  '([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Pp][Ii][_-]?[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn]|[Cc][Ll][Ii][Ee][Nn][Tt][_-]?[Ss][Ee][Cc][Rr][Ee][Tt]|[Ss][Ee][Cc][Rr][Ee][Tt][_-]?[Kk][Ee][Yy]|[Aa][Uu][Tt][Hh][_-]?[Tt][Oo][Kk][Ee][Nn]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee][_-]?[Tt][Oo][Kk][Ee][Nn])["[:space:]]{0,3}[:=][^A-Za-z0-9]{0,3}[A-Za-z0-9_/+.-]{16,}'
  # v2.10.9: require a token-length value ({20,}) so conversational "Bearer
  # authentication" / "Bearer token" don't false-positive (real bearer tokens are
  # long). Matters most for the prompt channel (prompt-secret-guard).
  'Bearer [A-Za-z0-9._-]{20,}'
  # Private keys
  'BEGIN.{0,10}PRIVATE KEY'
  # URLs with embedded credentials. v2.22.0: use [[:space:]], not \s — inside a
  # bracket \s is the literal chars \ and s (POSIX/BSD/GNU alike), which excluded
  # the letter 's' from userinfo, so `postgres://user:pass@` (any 's' in the
  # creds) evaded detection entirely.
  '://[^:@/[:space:]]+:[^@/[:space:]]+@'
  # Stripe
  'sk_live_[0-9a-zA-Z]{24}'
  'rk_live_[0-9a-zA-Z]{24}'
  'pk_live_[0-9a-zA-Z]{24}'
  # npm
  'npm_[A-Za-z0-9]{36}'
  # JWTs
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  # OpenAI — legacy sk-<alnum> + modern hyphenated project/service/admin keys
  # (v2.22.0: the {20,} run broke on the hyphen after sk-proj-/sk-svcacct-).
  'sk-[A-Za-z0-9]{20,}'
  'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}'
  # Anthropic API keys (v2.22.0) — sk-ant-...
  'sk-ant-[A-Za-z0-9_-]{20,}'
  # Slack — bot/user/legacy xox* + app-level xapp- (v2.22.0)
  'x(ox[baprs]|app)-[0-9A-Za-z-]{10,}'
  # HuggingFace
  'hf_[A-Za-z0-9]{30,}'
  # Secrets-manager service account token (v2.29.21) — `ops_` + a long base64
  # run. A credential that reads OTHER credentials, so a leak here is a master
  # key rather than one service's access. Distinct fixed prefix, so no ambiguity
  # and no false-positive surface. From the dwarvesf/claude-guardrails overlap
  # audit: 11 of its 13 patterns were already covered, this was genuinely
  # missing, and its 64-hex "private key" pattern was deliberately NOT taken —
  # that one matches any SHA-256 digest, which v2.26.29 already resolved here as
  # a block-on-output / warn-on-prompt split (tests/test-prompt-secret-ambiguous.sh).
  'ops_[A-Za-z0-9+/=]{40,}'
  # GCP service account JSON
  '"private_key":[[:space:]]*"-----BEGIN'
  # GCP API key (Maps, Firebase, Translate, YouTube)
  'AIza[0-9A-Za-z_-]{35}'
  # Azure storage
  'AccountKey=[A-Za-z0-9+/]{60,}='
  # Twilio
  'SK[0-9a-f]{32}'
  # SendGrid
  'SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,}'
  # v2.9.8: crypto wallet — Ethereum/EVM private key (0x + 64 hex). The 0x prefix
  # keeps it distinct from a bare 64-hex SHA-256 checksum (lockfiles), so low FP.
  '0x[a-fA-F0-9]{64}'
  # v2.9.10: more wallet-key formats (from dwarvesf/claude-guardrails v0.4.0).
  # BIP-32 extended private key — xprv/yprv/zprv (mainnet) + tprv/uprv/vprv
  # (testnet), Base58, 107-108 chars. Prefix makes FP essentially nil.
  '([xyz]prv|[tuv]prv)[1-9A-HJ-NP-Za-km-z]{107,108}'
  # Bitcoin WIF private key (Base58, mainnet) — starts 5/K/L, 51-52 chars total.
  #
  # v2.26.44: BOUNDARY-ANCHORED. Unanchored, this was the highest-FP pattern in
  # the file by a wide margin: it is pure Base58 with no prefix to disambiguate,
  # and base64 payloads are full of Base58-safe runs. A browser screenshot (image
  # bytes as base64) tripped the secret scanner on nearly every call — measured
  # at 42 false positives across 20 screenshots, 1 after anchoring.
  #
  # The boundary class is the Base58 alphabet's COMPLEMENT, deliberately not the
  # base64 alphabet: `key=5Hue…` is a real-world shape, and excluding '=' from
  # the boundary would stop matching it. That leaves the rare base64 run bounded
  # by 0/O/I/l/+// — hence 1 residual rather than 0. output-secrets-scanner also
  # strips image payloads before scanning, which closes the screenshot case.
  #
  # All four consumers use `grep -qE` (quiet), so widening the match to include
  # the boundary characters changes no reported output.
  #
  # v4.0.14: the boundary classes are NON-ALPHANUMERIC, not merely non-base58.
  # Base58 excludes only 0, O, I and l, so hex digits are a SUBSET of it and a
  # sha256 digest can satisfy this pattern outright: a `0` inside the digest acts
  # as the opening boundary, a `5` follows it, 50-51 hex characters without a zero
  # follow that, and a second `0` closes it. Observed live — reading a project's
  # `checksums.sha256` tripped output-secrets-scanner and interrupted the turn:
  #
  #   8005a3491db7d92f36ac66369861589f9c47123d3a7c71e643fc2c06168cd45a  package.json
  #
  # That is `sha256sum` output, and the same shape covers lockfile integrity
  # hashes, docker digests and git object listings — ordinary developer output on
  # a guard that stops work. The Ethereum rule above already carries this warning
  # ("the 0x prefix keeps it distinct from a bare 64-hex SHA-256 checksum"); this
  # pattern arrived later and reopened the hole by a different route.
  #
  # A real WIF key is delimited by whitespace, a quote, `=` or a line end — never
  # by an alphanumeric. Inside a hex digest the only available delimiter IS an
  # alphanumeric (`0`). Requiring non-alphanumeric boundaries separates them with
  # no loss: verified against public WIF test vectors bare, quoted, and as an env
  # assignment — all three still match, the digest line no longer does.
  '(^|[^0-9A-Za-z])[5KL][1-9A-HJ-NP-Za-km-z]{50,51}([^0-9A-Za-z]|$)'
)
