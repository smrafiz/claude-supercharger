#!/usr/bin/env bash
# Claude Supercharger — Playwright / Puppeteer MCP Guard
# Event: PreToolUse | Matcher: mcp__playwright__*,mcp__puppeteer__*
#
# Blocks browser-MCP shapes that exfiltrate or RCE. Real CVEs:
#   - CVE-2025-9611: Playwright MCP CSRF / DNS rebinding
#   - microsoft/playwright-mcp #1495: critical RCE via browser_run_code
#   - microsoft/playwright-mcp #1651: arbitrary file read via
#     browser_run_code_unsafe + file://
#
# Denies:
#   - browser_run_code_unsafe / puppeteer_evaluate unconditionally
#     (no legitimate agentic use case for arbitrary in-browser JS eval)
#   - browser_navigate / puppeteer_navigate to internal/file:// URLs
#     (SSRF, metadata endpoint, local file disclosure)

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "mcp-playwright-guard" && exit 0

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  # 2.22.13: cover other browser-automation MCPs with the same SSRF/eval surface.
  mcp__playwright__*|mcp__puppeteer__*|mcp__browserbase__*|mcp__browser-use__*|mcp__browsermcp__*|mcp__chrome-devtools__*|mcp__stagehand__*) ;;
  *) exit 0 ;;
esac

deny() {
  local reason="$1"
  echo "" >&2
  echo "Supercharger blocked browser-MCP call." >&2
  echo "  Tool   : $TOOL" >&2
  echo "  Reason : $reason" >&2
  echo "" >&2
  # 2.21.2: fail CLOSED on the deny path (see mcp-github-write-gate). A python
  # failure must not abort before the deny JSON + exit 2, or the browser call
  # would be allowed. Reason is already on stderr above.
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || RSN='"blocked (see stderr for detail)"'
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# Unsafe in-browser code eval — no legitimate agentic use.
# v2.8.1: match *browser_run_code* (was *browser_run_code_unsafe*), which missed
# the plain `browser_run_code` tool — the exact #1495 RCE this hook documents.
# The broader glob still catches the `_unsafe` variant (it contains the prefix).
case "$TOOL" in
  # 2.22.13: broadened for other browser MCPs (browserbase/browser-use/
  # chrome-devtools/stagehand) whose eval/navigate tools use different names.
  *run_code*|*evaluate*|*_eval*|*execute_script*|*execute_javascript*|*run_js*)
    deny "$TOOL blocked — arbitrary in-browser JS eval (CVE-2025-9611 / GH #1495 class)"
    ;;
esac

# Navigation — block SSRF / internal / file:// targets
case "$TOOL" in
  *navigate*|*goto*|*open_url*|*load_url*|*_open*url*)
    URL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.url // empty' 2>/dev/null || true)
    if [ -n "$URL" ]; then
      URL_LC=$(printf '%s' "$URL" | tr '[:upper:]' '[:lower:]')
      # v2.8.1: strip the scheme and match the HOST, so a target is caught
      # regardless of http:// vs https:// vs no-scheme. Previously the 172.x
      # RFC1918 entries were http-only (https://172.16.x bypassed), and
      # `172.2*.*` over-matched public 172.200-255. Bracket ranges fix both.
      HOST=${URL_LC#*://}
      # v2.21.3: match the AUTHORITY with userinfo stripped, closing the
      # `http://user@10.0.0.5/` SSRF bypass. The private/localhost host globs
      # below are start-anchored, so a leading `user@` made `user@10.0.0.5` miss
      # `10.*`. Isolate the authority first (everything up to the first `/`, so a
      # `/@x` in the PATH can't be mistaken for userinfo) then drop `user:pass@`.
      # Same userinfo-@ class lib-egress-patterns.sh was already hardened for.
      AUTH=${HOST%%/*}
      AUTH=${AUTH#*@}
      case "$URL_LC" in
        file:*)   # 2.22.5: any file scheme (single-slash `file:/etc/passwd` normalizes to file:///)
          deny "navigate to file: blocked (local file disclosure, GH #1651)"
          ;;
      esac
      case "$AUTH" in
        # 2.22.5: also numeric loopback (2130706433=127.0.0.1, bare 0=0.0.0.0),
        # the unspecified [::], and the fully-expanded IPv6 loopback.
        localhost*|127.*|0.0.0.0*|0|0:*|2130706433*|\[::1\]*|\[::\]*|\[0:0:0:0:0:0:0:1\]*|\[::ffff:127.*)
          deny "navigate to localhost blocked (SSRF to local services)"
          ;;
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
          deny "navigate to RFC1918 private network blocked (SSRF)"
          ;;
        # 2.22.5: numeric/encoded IMDS (decimal/hex dword, Alibaba, IPv6 hextet)
        169.254.*|*metadata.google.internal*|*169.254.169.254*|*2852039166*|*0xa9fea9fe*|*a9fe:a9fe*|100.100.100.200*)
          deny "navigate to cloud metadata endpoint blocked (credential exfil)"
          ;;
      esac
    fi
    ;;
esac

exit 0
