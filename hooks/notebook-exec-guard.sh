#!/usr/bin/env bash
# Claude Supercharger — Notebook Exec Guard
# Event: PreToolUse | Matcher: NotebookEdit
#
# A Jupyter cell executes through the kernel, not the shell — so a cell that
# shells out (`!rm -rf …`, `%%bash` body, `%pip install …`, `os.system(…)`,
# `subprocess.run(…)`) NEVER passes the Bash matcher, and safety.sh / git-safety /
# enforce-pkg-manager never see it. This closes that channel: shell content
# extracted from the edited cell is routed through safety.sh (so it inherits the
# EXACT same destructive/network/credential rules — no pattern drift), and a
# package install in a cell is surfaced for confirmation.
# Advisory + fail-open; disable with SUPERCHARGER_NOTEBOOK_EXEC_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_NOTEBOOK_EXEC_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
check_hook_disabled "notebook-exec-guard" 2>/dev/null && exit 0

# Extract shell content + install signal from the edited cell. Output protocol
# (one line, tab-separated): <shell-payload-json-or-dash> TAB <install-reason-or-dash>
EXTRACT=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import os, sys, json, re

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

if (d.get("tool_name") or "") != "NotebookEdit":
    sys.exit(0)

ti = d.get("tool_input") or {}
src = ti.get("new_source") or ti.get("source") or ti.get("content") or ""
if not isinstance(src, str) or not src.strip():
    sys.exit(0)
cwd = d.get("cwd") or (d.get("workspace") or {}).get("current_dir") or ""

lines = src.split("\n")

# Extract shell snippets from the cell.
shell_parts = []
# %%bash / %%sh / %%script bash -> the whole rest of the cell body is shell.
if lines and re.match(r"^\s*%%\s*(bash|sh|script\s+\S*sh)\b", lines[0]):
    shell_parts.append("\n".join(lines[1:]))
else:
    for ln in lines:
        m = re.match(r"^\s*!(.+)$", ln)          # !command  (line shell-escape)
        if m:
            shell_parts.append(m.group(1))
# os.system("...") / os.popen("...")
for m in re.finditer(r'os\.(?:system|popen)\(\s*["\x27](.+?)["\x27]\s*\)', src):
    shell_parts.append(m.group(1))
# subprocess.run/call/Popen/check_output/getoutput(...) - capture the command,
# whether a "string" or a ["list", "of", "args"].
for m in re.finditer(r'subprocess\.(?:run|call|check_output|check_call|Popen|getoutput)\(\s*(.+?)\)', src, re.S):
    arg = m.group(1)
    strs = re.findall(r'["\x27]([^"\x27]+)["\x27]', arg)
    if strs:
        shell_parts.append(" ".join(strs))

shell = "\n".join(p for p in shell_parts if p and p.strip()).strip()

# Detect package installs (ask, even if safety.sh does not block).
install = ""
im = re.search(
    r'(?:^|\n)\s*[!%]\s*(pip3?|conda|mamba|uv\s+pip|poetry|npm|pnpm|yarn|npx|gem|cargo)\s+(install|add|i)\b(.*)',
    src)
if im:
    tool = im.group(1).strip()
    pkgs = (im.group(3) or "").strip()[:120]
    install = "notebook cell installs packages via %s (%s) - runs on cell execution, bypassing enforce-pkg-manager. Confirm the source is trusted." % (tool, pkgs or "unpinned")

if not shell and not install:
    sys.exit(0)

payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": shell}, "cwd": cwd}) if shell else "-"
sys.stdout.write(payload + "\t" + (install or "-"))
PYEOF
)

[ -z "$EXTRACT" ] && exit 0

SHELL_PAYLOAD="${EXTRACT%%$'\t'*}"
INSTALL_REASON="${EXTRACT#*$'\t'}"

# 1. Route extracted shell through safety.sh — inherits its full rule set (parity,
#    no drift). If it denies (exit 2), relay its decision verbatim.
if [ "$SHELL_PAYLOAD" != "-" ] && [ -f "$HOOKS_DIR/safety.sh" ]; then
  SAFE_OUT=$(printf '%s' "$SHELL_PAYLOAD" | bash "$HOOKS_DIR/safety.sh" 2>/dev/null)
  SAFE_RC=$?
  if [ "$SAFE_RC" = 2 ] && [ -n "$SAFE_OUT" ]; then
    echo "[Supercharger] notebook-exec-guard: DENY on shell in notebook cell" >&2
    printf '%s\n' "$SAFE_OUT"
    exit 2
  fi
fi

# 2. Package install in a cell → ask (safety.sh does not treat installs as
#    destructive, but an unvetted install in a notebook still warrants a look).
if [ "$INSTALL_REASON" != "-" ] && [ -n "$INSTALL_REASON" ]; then
  RSN=$(printf '%s' "$INSTALL_REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$INSTALL_REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
  echo "[Supercharger] notebook-exec-guard: ASK on notebook install" >&2
  exit 0
fi

exit 0
