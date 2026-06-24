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
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "mcp-playwright-guard" && exit 0

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  mcp__playwright__*|mcp__puppeteer__*) ;;
  *) exit 0 ;;
esac

deny() {
  local reason="$1"
  echo "" >&2
  echo "Supercharger blocked browser-MCP call." >&2
  echo "  Tool   : $TOOL" >&2
  echo "  Reason : $reason" >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# Unsafe in-browser code eval — no legitimate agentic use
case "$TOOL" in
  *browser_run_code_unsafe*|*puppeteer_evaluate*|*evaluate_handle*)
    deny "$TOOL blocked — arbitrary in-browser JS eval (CVE-2025-9611 class)"
    ;;
esac

# Navigation — block SSRF / internal / file:// targets
case "$TOOL" in
  *browser_navigate*|*puppeteer_navigate*|*goto*)
    URL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.url // empty' 2>/dev/null || true)
    if [ -n "$URL" ]; then
      # Normalize for matching
      URL_LC=$(printf '%s' "$URL" | tr '[:upper:]' '[:lower:]')
      case "$URL_LC" in
        file://*)
          deny "navigate to file:// blocked (local file disclosure, GH #1651)"
          ;;
        http://localhost*|https://localhost*|http://127.*|https://127.*)
          deny "navigate to localhost blocked (SSRF to local services)"
          ;;
        http://10.*|https://10.*|http://192.168.*|https://192.168.*|http://172.16.*|http://172.17.*|http://172.18.*|http://172.19.*|http://172.2*.*|http://172.30.*|http://172.31.*)
          deny "navigate to RFC1918 private network blocked (SSRF)"
          ;;
        http://169.254.*|https://169.254.*|*metadata.google.internal*|*169.254.169.254*)
          deny "navigate to cloud metadata endpoint blocked (credential exfil)"
          ;;
      esac
    fi
    ;;
esac

exit 0
