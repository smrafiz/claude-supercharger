#!/usr/bin/env bash
# Suite for hooks/lib-secret-patterns.sh (the shared SECRET_PATTERNS set used by
# output-secrets-scanner, prompt-secret-guard, commit-guard). v2.22.0 added
# modern key formats that previously evaded. Literals are assembled from parts so
# this file never contains a complete secret string.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

. "$REPO_DIR/hooks/lib-secret-patterns.sh"
CP=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")
catches() { printf '%s' "$1" | LC_ALL=C grep -qE "$CP"; }

AWS40="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"   # canonical 40-char AWS secret
GHPAT_TAIL=$(printf 'A%.0s' $(seq 1 82))

# ---- v2.22.0: modern formats that used to EVADE ----
begin_test "secret: Anthropic sk-ant- key is caught"
catches "sk-""ant-api03-AbCdEf0123456789AbCdEf0123456789xyz" && pass || fail "sk-ant evades"

begin_test "secret: OpenAI sk-proj- key is caught"
catches "sk-""proj-AbCdEf0123456789AbCdEfGh0123" && pass || fail "sk-proj evades"

begin_test "secret: OpenAI sk-svcacct- key is caught"
catches "sk-""svcacct-AbCdEf0123456789AbCdEfGh" && pass || fail "sk-svcacct evades"

begin_test "secret: GitHub fine-grained github_pat_ is caught"
catches "github""_pat_${GHPAT_TAIL}" && pass || fail "github_pat evades"

begin_test "secret: GitHub refresh ghr_ is caught"
catches "ghr""_AbCdEf0123456789AbCdEf0123456789ABCD" && pass || fail "ghr_ evades"

begin_test "secret: lowercase aws_secret_access_key is caught"
catches "aws""_secret_access_key = ${AWS40}" && pass || fail "lowercase aws secret evades"

begin_test "secret: postgres:// URL with 's' in creds is caught"
catches "postgres""://admin:sup3rpass@db.host/x" && pass || fail "url creds with s evade"

begin_test "secret: client_secret= is caught"
catches "client""_secret=AbCdEf0123456789AbCdEf" && pass || fail "client_secret evades"

begin_test "secret: Slack app-level xapp- is caught"
catches "xapp""-1-A0-abcdef-0123456789" && pass || fail "xapp evades"

# ---- regression: existing formats still caught ----
begin_test "secret: AWS access-key id AKIA still caught"
catches "AKIA""IOSFODNN7EXAMPLE" && pass || fail "AKIA regressed"

begin_test "secret: legacy OpenAI sk- still caught"
catches "sk-""AbCdEf0123456789AbCdEfGh" && pass || fail "legacy sk- regressed"

begin_test "secret: classic GitHub ghp_ still caught"
catches "ghp""_AbCdEf0123456789AbCdEf0123456789ABCD" && pass || fail "ghp_ regressed"

begin_test "secret: uppercase AWS_SECRET_ACCESS_KEY still caught"
catches "AWS""_SECRET_ACCESS_KEY=${AWS40}" && pass || fail "uppercase aws regressed"

# ---- v2.29.21: secrets-manager service account token (dwarvesf overlap audit) ----
# A credential that reads OTHER credentials, so a leak is a master key rather
# than one service's access. 11 of that repo's 13 patterns were already covered;
# this was the only genuine gap.
begin_test "secret: ops_ service account token is caught"
catches "ops""_$(printf 'A%.0s' $(seq 1 45))" && pass || fail "ops_ token evades"

begin_test "secret: a short ops_ lookalike does NOT fire"
# The {40,} floor keeps ordinary words starting with the prefix out.
catches "ops""_notatoken" && fail "FP on a short ops_ string" || pass

# The 64-hex "private key" pattern from the same repo was deliberately NOT
# adopted: it matches any SHA-256 digest, and v2.26.29 already resolved that
# ambiguity here (block on output channels, warn on the prompt channel). This
# asserts the decision still holds rather than silently regressing to a block.
begin_test "secret: a bare SHA-256 digest is not treated as an ops_ token"
catches "ops""_$(printf 'b94d27b9934d3e08a52e52d7da7dabfa')" && fail "short hex matched ops_" || pass

# ---- must NOT false-positive on plain text ----
begin_test "secret: plain prose does not fire"
catches "the quick brown fox jumps over the lazy dog" && fail "FP on prose" || pass

begin_test "secret: plain github URL (no creds) does not fire"
catches "https""://github.com/user/repo.git" && fail "FP on plain url" || pass

# ---- v4.0.14: a checksum manifest is not a wallet key ------------------------
#
# Base58 excludes only 0, O, I and l, so hex digits are a SUBSET of it and the WIF
# pattern matched a sha256 line outright: a `0` in the digest opened the boundary,
# a `5` followed, then 50-51 hex characters without a zero, then a second `0`
# closed it. Observed live — reading a project's checksums.sha256 fired
# output-secrets-scanner and interrupted the turn. Same shape covers sha256sum
# output, lockfile integrity hashes, docker digests and git object listings.
#
# The Ethereum rule in the same file already warned about exactly this ("the 0x
# prefix keeps it distinct from a bare 64-hex SHA-256 checksum"); the WIF pattern
# landed later and reopened it by another route.
#
# Both halves are asserted. Loosening a SECRET pattern to clear a false positive
# is precisely where a real key slips through, so the WIF vectors below are public
# test values kept here to prove detection survived.
WIF_UNCOMPRESSED="5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ""1jvhTVqvbTLvyTJ"
WIF_COMPRESSED="L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8""TrisoyY1"
SHA256_LINE="8005a3491db7d92f36ac66369861589f9c47123d3a7c71e643fc2c06168cd45a  package.json"

begin_test "secret: a sha256sum manifest line does not fire"
catches "$SHA256_LINE" && fail "checksum line matched a wallet-key pattern" || pass

begin_test "secret: a second checksum line does not fire either"
catches "e82c0537607edb9f89b2ca1c42c6807581090baae96177cd66a21433cf6f8a96  config.js" \
  && fail "checksum line matched" || pass

begin_test "GAP CHECK: an uncompressed WIF key is still caught"
catches "key = $WIF_UNCOMPRESSED" && pass || fail "WIF key now EVADES — the narrowing went too far"

begin_test "GAP CHECK: a compressed WIF key is still caught"
catches "export WALLET=$WIF_COMPRESSED" && pass || fail "compressed WIF key now EVADES"

begin_test "GAP CHECK: a quoted WIF key is still caught"
# JSON and shell both deliver keys wrapped in quotes; the boundary class must
# accept them or the pattern only works on bare text.
catches "\"$WIF_UNCOMPRESSED\"" && pass || fail "quoted WIF key now EVADES"

report
