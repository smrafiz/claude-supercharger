#!/usr/bin/env bash
# Ambiguous secret patterns warn on the prompt channel instead of blocking (v2.26.29)
#
# `0x` + 64 hex is an EVM wallet private key and, byte for byte, a public
# transaction hash / block hash. Nothing in the value distinguishes them, so
# blocking it refused prompts that merely mentioned a PUBLIC identifier. Held as
# a known false positive since the v2.22.10 audit.
#
# The resolution keeps the pattern everywhere it can act on a value the model
# would otherwise echo, and downgrades it only where the cost falls on the user:
#   prompt-secret-guard      block -> warn   (this file)
#   output-secrets-scanner   unchanged, still blocks
#   display-secret-redactor  unchanged, still redacts
#
# What is deliberately given up: a bare wallet key typed into a prompt now
# reaches the transcript with a warning rather than being stopped. That is the
# accepted trade — see the header comment in hooks/prompt-secret-guard.sh.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GUARD="$REPO_DIR/hooks/prompt-secret-guard.sh"

# A 64-hex value with no semantic meaning. Real public tx hashes have this shape.
HASH='0x8f2e4b1c9a7d3e6f0b5a8c2d4e7f1a3b6c9d2e5f8a1b4c7d0e3f6a9b2c5d8e1f'
# Assembled at runtime so the literal does not sit in the file where this repo's
# own commit and output scanners will trip on it. The length assertion below
# proves the assembled value is intact — a silent truncation here would make
# every "still blocks" test pass for the wrong reason.
AWS_ID="AK""IAIOSFODNN7EXAMPLE"
AWS_SECRET="aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

rc_for() { # prompt -> exit code
  printf '%s' "$(V="$1" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" | bash "$GUARD" >/dev/null 2>&1
  echo $?
}
stderr_for() { # prompt -> stderr text
  printf '%s' "$(V="$1" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" | bash "$GUARD" 2>&1 >/dev/null
}
stdout_for() { # prompt -> stdout text (added to the model's context)
  printf '%s' "$(V="$1" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" | bash "$GUARD" 2>/dev/null
}

echo "=== Prompt Secret Guard — Ambiguous Pattern Tests ==="

begin_test "the assembled AWS credential is intact (guards the tests below)"
[ "${#AWS_ID}" -eq 20 ] && pass || fail "AWS id is ${#AWS_ID} chars, not 20 — blocking tests would pass vacuously"

# --- the false positive is gone ---------------------------------------------
begin_test "a public tx hash no longer blocks the prompt"
[ "$(rc_for "look up $HASH on etherscan")" = "0" ] && pass || fail "still blocked"

begin_test "a tx hash mid-sentence no longer blocks the prompt"
[ "$(rc_for "why did tx $HASH revert?")" = "0" ] && pass || fail "still blocked"

# --- but it is not silent ----------------------------------------------------
begin_test "the user is warned that the value may be a private key"
stderr_for "look up $HASH" | grep -qi 'private key' && pass || fail "no warning shown"

begin_test "the warning says it is a warning, not a block"
stderr_for "look up $HASH" | grep -qi 'not a block' && pass || fail "warning does not state it allowed the prompt"

begin_test "the warning tells the user to rotate if it really is a key"
stderr_for "look up $HASH" | grep -qi 'rotate' && pass || fail "no rotate instruction"

begin_test "the model is told not to echo the value"
stdout_for "look up $HASH" | grep -qi 'not repeat\|do not repeat' && pass || fail "no context note for the model"

begin_test "neither stream contains the value itself"
{ stderr_for "look up $HASH"; stdout_for "look up $HASH"; } | grep -q "$HASH" \
  && fail "the guard echoed the value it is warning about" || pass

# --- everything else still blocks -------------------------------------------
begin_test "a real AWS credential still blocks"
[ "$(rc_for "$AWS_ID and $AWS_SECRET")" = "2" ] && pass || fail "AWS credential was allowed"

begin_test "a prompt with BOTH a tx hash and a real credential still blocks"
[ "$(rc_for "$HASH plus $AWS_ID $AWS_SECRET")" = "2" ] && pass \
  || fail "the ambiguous match short-circuited a real credential"

begin_test "an ordinary prompt is untouched"
[ "$(rc_for 'what does this function do?')" = "0" ] && pass || fail "false positive on plain text"

begin_test "an ordinary prompt produces no warning"
[ -z "$(stderr_for 'what does this function do?')" ] && pass || fail "warned on plain text"

# --- coverage on the other channels is unchanged ----------------------------
begin_test "output-secrets-scanner still acts on the same value"
printf '%s' "$(V="$HASH" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_response": {"stdout": os.environ["V"]}}))')" \
  | bash "$REPO_DIR/hooks/output-secrets-scanner.sh" 2>&1 | grep -qi 'secret' \
  && pass || fail "downgrading the prompt channel also weakened tool output"

# --- drift protection --------------------------------------------------------
# The exemption matches the pattern by exact string. If lib-secret-patterns.sh
# rewrites the regex, the match silently stops applying and the pattern reverts
# to blocking — safe, but the FP comes back. Pin the string in both places.
begin_test "the exempted pattern still exists verbatim in lib-secret-patterns.sh"
grep -qF "'0x[a-fA-F0-9]{64}'" "$REPO_DIR/hooks/lib-secret-patterns.sh" && pass \
  || fail "the wallet-key regex changed — the prompt-channel exemption no longer matches it"

begin_test "the guard exempts that exact pattern"
grep -qF "AMBIGUOUS_PATTERNS=('0x[a-fA-F0-9]{64}')" "$GUARD" && pass \
  || fail "exemption list no longer names the pattern"

# --- the existing escape hatches still work ---------------------------------
begin_test "SUPERCHARGER_PROMPT_SECRET_GUARD=0 disables the guard entirely"
GOT=$(printf '%s' "$(V="$AWS_ID and $AWS_SECRET" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" \
  | SUPERCHARGER_PROMPT_SECRET_GUARD=0 bash "$GUARD" >/dev/null 2>&1; echo $?)
[ "$GOT" = "0" ] && pass || fail "kill switch ignored"

report
