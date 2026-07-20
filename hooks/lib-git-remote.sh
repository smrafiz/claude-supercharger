#!/usr/bin/env bash
# Claude Supercharger — Git remote exfil detector (single source of truth)
# Answers "does this git command push the whole repo to a non-origin host, or
# hijack origin's URL to a foreign host?". Used by git-remote-guard.sh (to ask)
# AND lib-smart-approve.sh (to refuse auto-approval so autopilot can't swallow the
# ask). One detector → no sibling-parity drift.
#
# git_remote_exfil_reason "<command>" "<project_dir>"
#   → prints "ASK<TAB>HOST<TAB>REASON" when the command is a foreign-host push or
#     origin hijack; prints nothing otherwise. No side effects (read-only git).

git_remote_exfil_reason() {
  local _cmd="$1" _pdir="$2" _remotes
  _remotes=$(git -C "$_pdir" remote -v 2>/dev/null | awk '{print $1"\t"$2}' | sort -u || true)
  COMMAND="$_cmd" REMOTES="$_remotes" python3 <<'PY' 2>/dev/null || true
import os, re

cmd = os.environ.get('COMMAND', '')
remotes_raw = os.environ.get('REMOTES', '')

def host_of(url):
    if not url:
        return None
    u = url.strip()
    u = re.sub(r'^[a-zA-Z][a-zA-Z0-9+.-]*://', '', u)   # strip scheme://
    m = re.match(r'^[^/@]+@([^:/]+):', u)                # scp-like git@host:path
    if m:
        return m.group(1).lower()
    u = re.sub(r'^[^/@]+@', '', u)                       # strip userinfo@
    m = re.match(r'^([^/:]+)', u)                        # host up to / or :
    return m.group(1).lower() if m else None

# name -> host
name_host = {}
for line in remotes_raw.splitlines():
    if '\t' not in line:
        continue
    name, url = line.split('\t', 1)
    name_host[name.strip()] = host_of(url)
origin_host = name_host.get('origin')

def is_urlish(tok):
    return bool(re.match(r'^([a-zA-Z][a-zA-Z0-9+.-]*://|[^/@\s]+@[^/@\s]+:)', tok))

# 1. origin (or any known remote) hijack: git remote set-url [--push] <name> <url>
m = re.search(r'\bgit\s+remote\s+set-url\s+(?:--push\s+)?(\S+)\s+(\S+)', cmd)
if m:
    name, url = m.group(1), m.group(2)
    nh = host_of(url)
    cur = name_host.get(name)
    if nh and (cur is None or nh != cur) and (name == 'origin' or (cur and nh != cur)):
        print(f"ASK\t{nh}\tRepoints remote '{name}' to a different host ({nh}) — a whole-repo redirect/exfil or origin hijack. Confirm this remote is trusted.")
        raise SystemExit(0)

# 2. foreign-host push: git push [flags] <target> ...
m = re.search(r'\bgit\s+push\b(.*)', cmd)
if m:
    rest = m.group(1)
    args = [a for a in rest.split() if not a.startswith('-')]
    target = args[0] if args else None
    if target:
        if is_urlish(target):
            th = host_of(target)
            if th and (origin_host is None or th != origin_host):
                print(f"ASK\t{th}\tPushes the repository to a direct URL on host '{th}' (not the 'origin' remote) — a whole-repo exfiltration vector. Confirm this destination is trusted.")
                raise SystemExit(0)
        elif target in name_host:
            th = name_host[target]
            if th and origin_host and th != origin_host:
                print(f"ASK\t{th}\tPushes to remote '{target}' whose host ({th}) differs from origin ({origin_host}) — a whole-repo exfiltration vector. Confirm this remote is trusted.")
                raise SystemExit(0)
PY
}
