#!/usr/bin/env bash
# Claude Supercharger — Custom MCP servers, profile-aware
#
# Claude Code already owns ADDING an MCP server (`claude mcp add`, any transport —
# stdio, http, sse, headers, env). This tool deliberately does not reimplement that.
# What Claude Code has no notion of is Supercharger's context-cost PROFILES, so this
# lets a server you already added participate in them: register it once, pick which
# profiles it belongs to, and `/profile` will add/remove it as you switch.
#
# Usage:
#   mcp-custom.sh adopt <name> [profiles]   register an existing server (default: all)
#   mcp-custom.sh list                      show the registry
#   mcp-custom.sh remove <name>             unregister (server itself is left alone)
#
#   <profiles> is `all` or a comma list of light|dev|research|full — e.g. "dev,full"
#   means the server is configured only while one of those profiles is active.
#
# Typical flow:
#   claude mcp add my-thing -- npx -y my-mcp-server     # Claude Code adds it
#   bash tools/mcp-custom.sh adopt my-thing dev,full    # Supercharger manages it
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/mcp.sh
. "$REPO_DIR/lib/mcp.sh" 2>/dev/null || true
: "${SUPERCHARGER_MCP_CUSTOM:=$HOME/.claude/supercharger/mcp-custom.json}"
: "${SUPERCHARGER_MCP_TAG:=#supercharger}"

VALID_PROFILES="light dev research full"

_usage() { sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

case "${1:-list}" in
  adopt)
    NAME="${2:-}"; PROFILES="${3:-all}"
    [ -z "$NAME" ] && { echo "usage: mcp-custom.sh adopt <name> [profiles]" >&2; exit 1; }
    # validate the profile list up front — a typo here silently hides the server
    if [ "$PROFILES" != "all" ]; then
      _bad=""
      _IFS_OLD="$IFS"; IFS=','
      for _p in $PROFILES; do
        case " $VALID_PROFILES " in *" $_p "*) : ;; *) _bad="$_bad $_p" ;; esac
      done
      IFS="$_IFS_OLD"
      [ -n "$_bad" ] && { echo "Unknown profile(s):$_bad — valid: all, $VALID_PROFILES" >&2; exit 1; }
    fi
    SC_NAME="$NAME" SC_PROFILES="$PROFILES" SC_REG="$SUPERCHARGER_MCP_CUSTOM" \
    SC_TAG="$SUPERCHARGER_MCP_TAG" python3 - <<'PY'
import json, os, sys
name, profiles = os.environ["SC_NAME"], os.environ["SC_PROFILES"]
reg_path, tag = os.environ["SC_REG"], os.environ["SC_TAG"]
# Find the server in either config file; accept a tagged or untagged key.
entry = None
for p in (os.path.expanduser("~/.claude.json"), os.path.expanduser("~/.claude/settings.json")):
    if not os.path.isfile(p):
        continue
    try:
        with open(p) as f: m = (json.load(f) or {}).get("mcpServers") or {}
    except Exception:
        continue
    for k, v in m.items():
        if k == name or k == name + " " + tag:
            entry = v; break
    if entry: break
if entry is None:
    print("Not found: '%s' is not a configured MCP server." % name, file=sys.stderr)
    print("Add it first, e.g.:  claude mcp add %s -- npx -y <package>" % name, file=sys.stderr)
    sys.exit(1)
try:
    with open(reg_path) as f: reg = json.load(f) or {}
except Exception:
    reg = {}
reg[name] = {"profiles": profiles, "entry": entry}
os.makedirs(os.path.dirname(reg_path), exist_ok=True)
tmp = reg_path + ".tmp"
with open(tmp, "w") as f: json.dump(reg, f, indent=2)
os.replace(tmp, reg_path)

# Take ownership: drop the ORIGINAL untagged entry. Otherwise adopting leaves the
# server configured twice (untagged + tagged) — loaded twice, double context cost —
# and the profile filter would never actually hide it. The full config now lives in
# the registry, and `remove` puts the untagged entry back.
for p in (os.path.expanduser("~/.claude.json"), os.path.expanduser("~/.claude/settings.json")):
    if not os.path.isfile(p):
        continue
    try:
        with open(p) as f: s = json.load(f) or {}
    except Exception:
        continue
    m = s.get("mcpServers") or {}
    if name not in m:
        continue
    del m[name]
    if m: s["mcpServers"] = m
    else: s.pop("mcpServers", None)
    t = p + ".sctmp"
    try:
        with open(t, "w") as f: json.dump(s, f, indent=2)
        os.replace(t, p)
    except Exception:
        try: os.unlink(t)
        except Exception: pass
print("Registered '%s' for profile(s): %s" % (name, profiles))
PY
    rc=$?
    [ "$rc" -ne 0 ] && exit "$rc"
    echo "  Apply it with:  /profile   (or bash tools/mcp-profile.sh <profile>)"
    echo "  It is now Supercharger-managed: profile switches add/remove it, and /sc off moves it aside."
    ;;

  list)
    SC_REG="$SUPERCHARGER_MCP_CUSTOM" python3 - <<'PY'
import json, os
p = os.environ["SC_REG"]
try:
    with open(p) as f: reg = json.load(f) or {}
except Exception:
    reg = {}
if not reg:
    print("No custom MCP servers registered.")
    print("Register one:  bash tools/mcp-custom.sh adopt <name> [profiles]")
else:
    print("Supercharger-managed custom MCP servers:")
    for k, v in sorted(reg.items()):
        e = v.get("entry", {})
        what = e.get("url") or ((e.get("command", "") + " " + " ".join(e.get("args", []))).strip())
        print("  - %-22s profiles: %-16s %s" % (k, v.get("profiles", "all"), what[:60]))
PY
    ;;

  remove|rm)
    NAME="${2:-}"
    [ -z "$NAME" ] && { echo "usage: mcp-custom.sh remove <name>" >&2; exit 1; }
    SC_NAME="$NAME" SC_REG="$SUPERCHARGER_MCP_CUSTOM" SC_TAG="$SUPERCHARGER_MCP_TAG" python3 - <<'PY'
import json, os, sys
name, p = os.environ["SC_NAME"], os.environ["SC_REG"]
try:
    with open(p) as f: reg = json.load(f) or {}
except Exception:
    reg = {}
if name not in reg:
    print("'%s' is not registered." % name); sys.exit(0)
spec = reg.pop(name)
tmp = p + ".tmp"
with open(tmp, "w") as f: json.dump(reg, f, indent=2)
os.replace(tmp, p)

# Hand the server back: restore the untagged entry we removed at adopt time and drop
# the managed copy, so unregistering never loses a server the user configured.
entry = (spec or {}).get("entry")
tag = os.environ.get("SC_TAG", "#supercharger")
cfg = os.path.expanduser("~/.claude.json")
if isinstance(entry, dict):
    try:
        with open(cfg) as f: s = json.load(f) or {}
    except Exception:
        s = {}
    m = s.get("mcpServers") or {}
    m.pop(name + " " + tag, None)
    m.setdefault(name, entry)
    s["mcpServers"] = m
    t = cfg + ".sctmp"
    try:
        with open(t, "w") as f: json.dump(s, f, indent=2)
        os.replace(t, cfg)
        print("Unregistered '%s' — it is yours again (untagged) in ~/.claude.json." % name)
    except Exception:
        try: os.unlink(t)
        except Exception: pass
        print("Unregistered '%s' (could not rewrite ~/.claude.json)." % name)
else:
    print("Unregistered '%s'." % name)
print("Remove the server entirely with:  claude mcp remove %s" % name)
PY
    ;;

  -h|--help|help) _usage ;;
  *) echo "usage: mcp-custom.sh adopt <name> [profiles] | list | remove <name>" >&2; exit 1 ;;
esac
