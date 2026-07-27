#!/usr/bin/env bash
# Claude Supercharger — Config Validity Guard
# Event: PostToolUse | Matcher: Write, Edit, MultiEdit
#
# A malformed structured-config file (a stray trailing comma / unbalanced brace from
# a bad Edit to package.json, tsconfig.json, a CI workflow, pyproject.toml) parses
# fine to the eye but blows up one round-trip later at `npm install` / `tsc` / CI.
# This WARNS (additionalContext, never blocks) when a written `.json`/`.yaml`/`.toml`
# no longer parses. Runs POST-write, so it parses the FINAL on-disk file (an Edit's
# new_string is only a fragment). JSON that fails strict parse is retried leniently
# (comments + trailing commas stripped) so JSONC — tsconfig, .vscode/*.json — passes;
# only a genuinely broken file warns. YAML/TOML are checked only when their parser is
# importable (else skipped — fail-open). Disable: SUPERCHARGER_CONFIG_VALIDITY_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_CONFIG_VALIDITY_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
# Fast-path: only structured-config extensions are worth a parse.
case "$_INPUT" in *.json*|*.yaml*|*.yml*|*.toml*) : ;; *) exit 0 ;; esac
check_hook_disabled "config-validity-guard" 2>/dev/null && exit 0
hook_profile_skip "config-validity-guard" 2>/dev/null && exit 0

_CV_OUT=$(mktemp 2>/dev/null) || _CV_OUT="${TMPDIR:-/tmp}/configval.$$"
HOOK_INPUT="$_INPUT" python3 > "$_CV_OUT" 2>/dev/null <<'PYEOF'
import os, re, sys, json

try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ""
if not path:
    sys.exit(0)
low = path.lower()
if low.endswith(".json"):
    fmt = "json"
elif low.endswith((".yaml", ".yml")):
    fmt = "yaml"
elif low.endswith(".toml"):
    fmt = "toml"
else:
    sys.exit(0)

# PostToolUse → the write is applied; parse the final on-disk file. (Edit new_string
# is only a fragment, so never parse tool_input content.)
try:
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        sys.exit(0)                       # missing/empty → nothing to validate
    with open(path, "r", errors="replace") as f:
        text = f.read(1024 * 1024)        # cap at 1MB
except Exception:
    sys.exit(0)

err = None

if fmt == "json":
    try:
        json.loads(text)
    except Exception as e:
        # JSONC fallback: strip // and /* */ comments + trailing commas, retry.
        stripped = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
        stripped = re.sub(r'(^|[^:])//[^\n]*', lambda m: m.group(1), stripped)
        stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
        try:
            json.loads(stripped)
        except Exception:
            err = str(e)                  # broken even as JSONC → report strict error

elif fmt == "yaml":
    try:
        import yaml
    except Exception:
        sys.exit(0)                       # parser unavailable → skip (fail-open)
    try:
        yaml.safe_load(text)
    except Exception as e:
        err = str(e).replace("\n", " ")

elif fmt == "toml":
    try:
        import tomllib
    except Exception:
        sys.exit(0)                       # <3.11 → skip
    try:
        tomllib.loads(text)
    except Exception as e:
        err = str(e)

if err:
    print("%s|%s" % (fmt.upper(), err[:300]))
PYEOF
_RES=$(cat "$_CV_OUT" 2>/dev/null); rm -f "$_CV_OUT" 2>/dev/null
[ -z "$_RES" ] && exit 0

_FMT="${_RES%%|*}"
_ERR="${_RES#*|}"
_MSG="[invalid ${_FMT}] The file just written does not parse as ${_FMT}: ${_ERR}. This will fail at the next tool that reads it (npm/tsc/CI/loader). Fix the syntax — likely a trailing comma, unbalanced brace/bracket, or bad indentation — before continuing. (Disable: SUPERCHARGER_CONFIG_VALIDITY_GUARD=0)"
_JSON=$(printf '%s' "$_MSG" | python3 -c "import sys,json;print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.stdin.read()}}))" 2>/dev/null || true)
[ -z "$_JSON" ] && exit 0
printf '%s\n' "$_JSON"
echo "[Supercharger] config-validity-guard: unparseable ${_FMT} written" >&2
exit 0
