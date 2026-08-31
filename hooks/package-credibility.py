#!/usr/bin/env python3
"""Registry credibility check for packages named on an install command line.

Companion to package-credibility-guard.sh. Kept as a separate file rather than a
`python3 -c` string because it needs real parsing and this repo has been bitten
twice by quoting inside interpolated -c blocks (a backtick in one of them reached
eval and executed).

Only checks packages NAMED ON THE COMMAND LINE, not the whole manifest. That is
the slopsquat vector -- the agent typed a name it invented -- and it keeps the
work to one or two lookups instead of a project-wide crawl.

Reads CMD from the environment. Prints one line if anything is worth saying, and
nothing at all otherwise. Never raises: a supply-chain check that breaks the
session when the registry is slow is a check people turn off.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

MIN_AGE_DAYS = int(os.environ.get("SC_MIN_AGE_DAYS") or 90)
MIN_DOWNLOADS = int(os.environ.get("SC_MIN_DOWNLOADS") or 1000)
TIMEOUT = 4          # per request; the whole hook must not outlast a human's patience
MAX_PACKAGES = 5     # a 40-package install is a manifest restore, not an invented name

NPM_INSTALL = re.compile(r"^\s*(?:npm\s+(?:install|i)|yarn\s+add|pnpm\s+add)\b(.*)", re.S)
PIP_INSTALL = re.compile(r"^\s*(?:pip3?\s+install|uv\s+add|poetry\s+add)\b(.*)", re.S)
# A package token: not a flag, not a path, not a URL, not a git ref.
TOKEN_OK = re.compile(r"^(?:@[a-z0-9][\w.-]*/)?[a-z0-9][\w.-]*$", re.I)


def tokens(tail):
    out = []
    for raw in tail.split():
        if raw.startswith("-"):
            continue
        if raw.startswith(("/", ".", "~", "http", "git+", "git:", "file:")):
            continue
        if "://" in raw or raw.endswith((".tgz", ".whl", ".tar.gz")):
            continue
        name = re.split(r"(?<!^)@|==|>=|<=|~=|>|<", raw, maxsplit=1)[0].strip()
        if name and TOKEN_OK.match(name):
            out.append(name)
    return out[:MAX_PACKAGES]


def get(url):
    try:
        r = subprocess.run(
            ["curl", "-sSL", "--max-time", str(TIMEOUT), "-H", "Accept: application/json", url],
            capture_output=True, text=True, timeout=TIMEOUT + 2)
        if r.returncode != 0 or not r.stdout.strip():
            return None
        return json.loads(r.stdout)
    except Exception:
        return None


def age_days(stamp):
    try:
        d = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - d).days
    except Exception:
        return None


def check_npm(name):
    meta = get("https://registry.npmjs.org/%s" % name.replace("/", "%2f"))
    if meta is None:
        return None                                   # network trouble: say nothing
    if meta.get("error") or not meta.get("name"):
        return "%s does NOT EXIST on npm" % name
    created = (meta.get("time") or {}).get("created")
    age = age_days(created) if created else None
    repo = (meta.get("repository") or {}).get("url") if isinstance(meta.get("repository"), dict) else meta.get("repository")
    dl = get("https://api.npmjs.org/downloads/point/last-week/%s" % name)
    weekly = (dl or {}).get("downloads")
    return verdict(name, age, weekly, repo)


def check_pypi(name):
    meta = get("https://pypi.org/pypi/%s/json" % name)
    if meta is None:
        return None
    info = meta.get("info")
    if not info:
        return "%s does NOT EXIST on PyPI" % name
    stamps = [r.get("upload_time_iso_8601") for v in (meta.get("releases") or {}).values()
              for r in (v or []) if r.get("upload_time_iso_8601")]
    age = age_days(min(stamps)) if stamps else None
    repo = info.get("project_urls", {}).get("Source") if info.get("project_urls") else info.get("home_page")
    return verdict(name, age, None, repo)            # PyPI has no download API here


def verdict(name, age, weekly, repo):
    flags = []
    if age is not None and age < MIN_AGE_DAYS:
        flags.append("first published %d day%s ago" % (age, "" if age == 1 else "s"))
    if weekly is not None and weekly < MIN_DOWNLOADS:
        flags.append("%d download%s last week" % (weekly, "" if weekly == 1 else "s"))
    if not repo:
        flags.append("no repository link")
    # A package that is old AND popular is credible even with no repo field.
    if not flags:
        return None
    if len(flags) == 1 and flags[0] == "no repository link":
        return None                                   # on its own, too weak to mention
    return "%s: %s" % (name, ", ".join(flags))


def main():
    cmd = os.environ.get("CMD") or ""
    m = NPM_INSTALL.match(cmd)
    if m:
        names, check = tokens(m.group(1)), check_npm
    else:
        m = PIP_INSTALL.match(cmd)
        if not m:
            return
        names, check = tokens(m.group(1)), check_pypi
    if not names:
        return                                        # bare `npm install` restores a manifest
    found = []
    for n in names:
        try:
            v = check(n)
        except Exception:
            v = None
        if v:
            found.append(v)
    if found:
        print("; ".join(found))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
