#!/usr/bin/env bash
# Browser-workflow false positives (v2.26.44)
#
# Reported from the field: browser E2E work was close to unusable. Two hooks were
# responsible, and both were matching the wrong thing rather than being merely
# over-tuned.
#
# 1. mcp-circuit-breaker matched its failure regex against the WHOLE response
#    body. For a content-returning server (browser, docs fetcher, file reader)
#    the body is arbitrary page text, so a page containing "unavailable", "503"
#    or "403" opened a 30s+ escalating cooldown on a healthy server. Roughly a
#    dozen cooldowns to finish one task — worse than no breaker, because the
#    enforced wait exceeded the server's own backoff. Also a denial-of-tool
#    vector: page content is attacker-controlled.
#
# 2. output-secrets-scanner fired on nearly every screenshot. Cause was the
#    Bitcoin WIF pattern — pure Base58, no prefix — matching Base58-safe runs
#    inside base64 image bytes. 42 false positives across 20 screenshots.
#
# The user had already worked around (1) with SUPERCHARGER_MCP_BREAKER=0, which
# removes the breaker for EVERY server. These tests exist so the fix holds and
# that workaround can be retired.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The reported workaround may be set in the user's settings.json, which would
# make every breaker assertion below pass vacuously by disabling the hook.
unset SUPERCHARGER_MCP_BREAKER

BREAKER="$REPO_DIR/hooks/mcp-circuit-breaker.sh"
SCANNER="$REPO_DIR/hooks/output-secrets-scanner.sh"

echo "=== Browser False-Positive Fixes ==="

# --- 1. circuit breaker vs page content --------------------------------------
tripped() { # response-json -> 0 if the breaker recorded a trip
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  printf '{"hook_event_name":"PostToolUse","tool_name":"mcp__claude-in-chrome__get_page_text","tool_response":%s}' "$1" \
    | SUPERCHARGER_STATE="$st" bash "$BREAKER" >/dev/null 2>&1 || true
  local found=1
  ls "$st/scope/.mcp-health/"* >/dev/null 2>&1 && found=0
  rm -rf "$st"
  return $found
}
jstr() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }

begin_test "page text containing 'unavailable' does NOT trip the breaker"
tripped "$(jstr 'Product page. This item is currently unavailable in your region.')" \
  && fail "healthy page opened a cooldown" || pass

begin_test "page text quoting '503' does NOT trip the breaker"
tripped "$(jstr 'Our docs explain what a 503 means for your integration.')" \
  && fail "page mentioning a status code opened a cooldown" || pass

begin_test "a dashboard metric '403' does NOT trip the breaker"
tripped "$(jstr 'Errors today: 403')" && fail "page metric opened a cooldown" || pass

begin_test "a long page discussing rate limits does NOT trip the breaker"
LONG=$(python3 -c "print('Our API rate limit policy is described here. ' * 60)")
tripped "$(jstr "$LONG")" && fail "long content tripped on a strong phrase" || pass

begin_test "a page cannot deny the tool to itself (injection shape)"
# Attacker-controlled text asking to be treated as a rate limit, at page length.
INJ=$(python3 -c "print('rate limit exceeded. ' + ('filler text here. ' * 200))")
tripped "$(jstr "$INJ")" && fail "page content could disable the browser tool" || pass

begin_test "a REAL error envelope (isError + 429) still trips"
tripped '{"isError":true,"content":"HTTP 429 Too Many Requests"}' && pass \
  || fail "genuine rate limit no longer trips — the breaker is now useless"

begin_test "a REAL error key (503 service unavailable) still trips"
tripped '{"error":{"code":503,"message":"service unavailable"}}' && pass \
  || fail "genuine error envelope no longer trips"

begin_test "a SHORT unambiguous phrase without an envelope still trips"
tripped "$(jstr 'rate limit exceeded')" && pass || fail "bare short rate-limit reply ignored"

begin_test "a clean success never trips"
tripped '{"content":"Hello world"}' && fail "clean response tripped" || pass

begin_test "bare status numbers alone are not enough in plain content"
tripped "$(jstr 'status 429')" && fail "bare number in content still trips" || pass

# --- 2. secret scanner vs screenshots ----------------------------------------
scan() { # response-json -> RC (2 = flagged)
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s' "$1" | SUPERCHARGER_STATE="$st" bash "$SCANNER" >/dev/null 2>&1
  local rc=$?
  rm -rf "$st"
  return $rc
}

begin_test "screenshots are not flagged as secrets (20 samples)"
N=$(python3 - "$REPO_DIR" <<'PY'
import base64, json, os, subprocess, sys, tempfile
repo = sys.argv[1]; fp = 0
for _ in range(20):
    blob = base64.b64encode(os.urandom(8192)).decode()
    payload = {"tool_name": "mcp__claude-in-chrome__computer",
               "tool_response": {"content": [{"type": "image", "source": {
                   "type": "base64", "media_type": "image/png", "data": blob}}]}}
    with tempfile.TemporaryDirectory() as st:
        os.makedirs(os.path.join(st, 'scope'), exist_ok=True)
        r = subprocess.run(['bash', os.path.join(repo, 'hooks/output-secrets-scanner.sh')],
                           input=json.dumps(payload), capture_output=True, text=True,
                           env=dict(os.environ, SUPERCHARGER_STATE=st))
    if r.returncode == 2:
        fp += 1
print(fp)
PY
)
[ "$N" = "0" ] && pass || fail "$N of 20 screenshots flagged as secrets"

# Build the payload from the ENVIRONMENT. Nested double quotes inside
# "$(python3 -c "...")" terminate the outer string early and silently mangle the
# dict literal — that produced three SyntaxErrors and three bogus failures.
mcp_payload() { # content -> JSON on stdout
  SC_CONTENT="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "mcp__x__y",
                  "tool_response": {"content": os.environ["SC_CONTENT"]}}))'
}

begin_test "a real AWS key in an MCP text response is still caught"
AWSK="AKIA$(printf 'IOSFODNN7EXAMPLE')"
scan "$(mcp_payload "aws_key $AWSK")"
[ $? -eq 2 ] && pass || fail "real AWS key no longer detected"

begin_test "a real WIF key in text is still caught (boundary anchoring kept it)"
WIF="5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
scan "$(mcp_payload "privkey = $WIF")"
[ $? -eq 2 ] && pass || fail "real WIF key no longer detected"

begin_test "a WIF key in key=value form is still caught (why '=' stays a boundary)"
scan "$(mcp_payload "privkey=$WIF")"
[ $? -eq 2 ] && pass || fail "key=VALUE shape lost — boundary class is too strict"

begin_test "the WIF pattern is boundary-anchored in the shared library"
grep -q "(\^|\[^1-9A-HJ-NP-Za-km-z\])\[5KL\]" "$REPO_DIR/hooks/lib-secret-patterns.sh" && pass \
  || fail "WIF pattern is unanchored again — screenshots will flag as secrets"

begin_test "image stripping is scoped to image payloads, not all base64"
# A base64 blob NOT tied to an image must still be scanned.
grep -q 'image/' "$SCANNER" && pass || fail "strip rule is not image-scoped"

report
