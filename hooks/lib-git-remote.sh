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
import os, re, shlex

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

def is_urlish(tok):
    return bool(re.match(r'^([a-zA-Z][a-zA-Z0-9+.-]*://|[^/@\s]+@[^/@\s]+:)', tok))

# name -> host from the repo's real remotes.
name_host = {}
for line in remotes_raw.splitlines():
    if '\t' not in line:
        continue
    name, url = line.split('\t', 1)
    name_host[name.strip()] = host_of(url)
origin_host = name_host.get('origin')

# Tokenize (quote-aware); fall back to naive split on malformed quoting.
try:
    toks = shlex.split(cmd)
except Exception:
    toks = cmd.split()

SEPS = {'&&', '||', '|', ';', '&', '(', ')', '{', '}'}

def git_invocations(toks):
    # Each `git …` sub-invocation, up to the next shell separator. Catches
    # compound commands (`a && git push …`) without conflating segments.
    i, n = 0, len(toks)
    while i < n:
        if toks[i] == 'git':
            j = i + 1
            while j < n and toks[j] not in SEPS:
                j += 1
            yield toks[i:j]
            i = j
        else:
            i += 1

# git GLOBAL options that consume a following value (must skip the value too, so
# `git -C /repo push …` resolves `push` as the subcommand, not `/repo`).
GLOBAL_VAL = {'-C', '-c', '--git-dir', '--work-tree', '--namespace',
              '--exec-path', '--config-env', '--super-prefix'}

def subcommand_and_args(inv):
    k, n = 1, len(inv)              # inv[0] == 'git'
    while k < n:
        t = inv[k]
        if t in GLOBAL_VAL:
            k += 2; continue         # option + its value
        if t.startswith('-'):
            k += 1; continue         # flag, or --opt=value (self-contained)
        break
    if k >= n:
        return None, []
    return inv[k], inv[k + 1:]

# `git push` options that consume a following value.
PUSH_VAL = {'-o', '--push-option', '--receive-pack', '--exec', '--repo'}

def push_target(args):
    k, n = 0, len(args)
    while k < n:
        t = args[k]
        if t.startswith('--repo='):     # explicit repo target
            return t.split('=', 1)[1]
        if t == '--repo':
            return args[k + 1] if k + 1 < n else None
        if t in PUSH_VAL:
            k += 2; continue            # skip option + value
        if t.startswith('-'):
            k += 1; continue
        return t                        # first positional = remote name or URL
    return None

def remote_add_name_url(args):          # args after `remote add`
    k, n = 0, len(args); name = url = None
    VAL = {'-t', '-m'}
    while k < n:
        t = args[k]
        if t in VAL:
            k += 2; continue
        if t.startswith('-'):
            k += 1; continue
        if name is None: name = t
        elif url is None: url = t
        k += 1
    return name, url

invs = list(git_invocations(toks))

# First pass: remotes ADDED in this same command (the compound exfil setup
# `git remote add x <url> && git push x --all` — at PreToolUse the add hasn't run,
# so x isn't in the repo's remotes yet; learn it from the command itself).
local_added = {}
for inv in invs:
    sub, args = subcommand_and_args(inv)
    if sub == 'remote' and args and args[0] == 'add':
        name, url = remote_add_name_url(args[1:])
        if name and url:
            local_added[name] = host_of(url)

known = dict(name_host); known.update(local_added)

for inv in invs:
    sub, args = subcommand_and_args(inv)

    if sub == 'push':
        target = push_target(args)
        if not target:
            continue
        if is_urlish(target):
            th = host_of(target)
            if th and (origin_host is None or th != origin_host):
                print(f"ASK\t{th}\tPushes the repository to a direct URL on host '{th}' (not the 'origin' remote) — a whole-repo exfiltration vector. Confirm this destination is trusted.")
                raise SystemExit(0)
        elif target in known:
            th = known[target]
            if th and (origin_host is None or th != origin_host):
                via = " (added in this command)" if target in local_added else ""
                print(f"ASK\t{th}\tPushes to remote '{target}'{via} whose host ({th}) differs from origin ({origin_host}) — a whole-repo exfiltration vector. Confirm this remote is trusted.")
                raise SystemExit(0)

    elif sub == 'remote' and args and args[0] == 'set-url':
        rest = [a for a in args[1:] if a != '--push']
        if len(rest) >= 2:
            name, url = rest[0], rest[1]
            nh = host_of(url); cur = name_host.get(name)
            if nh and (cur is None or nh != cur) and (name == 'origin' or (cur and nh != cur)):
                print(f"ASK\t{nh}\tRepoints remote '{name}' to a different host ({nh}) — a whole-repo redirect/exfil or origin hijack. Confirm this remote is trusted.")
                raise SystemExit(0)
PY
}
