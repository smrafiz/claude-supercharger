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

# ---- must NOT false-positive on plain text ----
begin_test "secret: plain prose does not fire"
catches "the quick brown fox jumps over the lazy dog" && fail "FP on prose" || pass

begin_test "secret: plain github URL (no creds) does not fire"
catches "https""://github.com/user/repo.git" && fail "FP on plain url" || pass

report
