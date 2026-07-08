#!/usr/bin/env bash
export PYTHONUTF8=1  # v2.9.3: this meta-test forks python to scan repo files; Windows Python defaults to cp1252 and chokes on UTF-8 bytes. No-op on mac/Linux.
# Meta-test: every scope-file a slash COMMAND reads must match how the hooks/tools
# actually WRITE it. This is the "stale scope-file path" class that silently broke
# /sc-status, /why, /perf, /cache-stats — commands referencing names/suffixes that
# drifted (e.g. /why globbed `.blocked-commands-*` when the real file is the bare
# `.blocked-commands`; /sc-status read `.tool-history` when it's `.tool-history-<sid>`).
# Unit tests can't catch it (they use fixtures); this derives ground truth from the
# writers and validates every command reference against it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Command Scope-File Reference Meta-Test ==="

begin_test "command-scope-refs: every command scope reference matches a writer's suffix form"
RESULT=$(REPO_DIR="$REPO_DIR" python3 - <<'PY'
import os, re, glob
repo = os.environ['REPO_DIR']

# 1) Ground truth: for each scope-file base, which suffix FORMS do the writers use?
#    'bare'  = written with no suffix (e.g. .blocked-commands)
#    'suffix'= written with a -<session>/-<hash>/-<something> suffix
writers = glob.glob(f'{repo}/hooks/*.sh') + glob.glob(f'{repo}/tools/*.sh') + \
          glob.glob(f'{repo}/lib/*.sh') + [f'{repo}/install.sh']
forms = {}   # base -> set(of 'bare'/'suffix')
WRITE = re.compile(r'(?:>>?|touch|json\.dump\([^)]*open\(|open\()\s*"?[^"\n]*?'
                   r'(\.[a-z][a-z0-9-]{2,})(-\$\{?[A-Za-z_]+\}?|-\{[a-z_]+\}|\$\{)?')
for w in writers:
    try: txt = open(w).read()
    except Exception: continue
    for m in re.finditer(r'(\.[a-z][a-z0-9-]{2,})(-\$\{?[A-Za-z_]+\}?|-\{[a-z_]+\}|-\$\()', txt):
        forms.setdefault(m.group(1), set()).add('suffix')
    # bare writes: name followed by a quote/space/newline, not a dash-suffix
    for m in re.finditer(r'(\.[a-z][a-z0-9-]{2,})(?=["\s\)/])', txt):
        base = m.group(1)
        # only count as bare if this exact name (no trailing dash-var) is written to
        if re.search(re.escape(base) + r'["\s]', txt):
            forms.setdefault(base, set()).add('bare')

problems = []
for f in sorted(glob.glob(f'{repo}/configs/commands/*.md')):
    name = os.path.basename(f)[:-3]
    txt = open(f).read()
    for ref in set(re.findall(r'scope/(\.[a-z][a-z0-9-]{2,}(?:-\*|-\$\{?[A-Za-z_]+\}?|-\{[a-z_]+\})?)', txt)):
        m = re.match(r'(\.[a-z][a-z0-9-]*?)(-\*|-\$\{?[A-Za-z_]+\}?|-\{[a-z_]+\})?$', ref)
        base, suf = m.group(1), m.group(2)
        wf = forms.get(base)
        if wf is None:
            continue  # base not written by any tracked writer — covered by other checks
        read_suffixed = suf is not None  # command globs/interpolates a suffix
        if read_suffixed and wf == {'bare'}:
            problems.append(f"/{name}: reads {ref} (suffixed) but {base} is written BARE")
        if (not read_suffixed) and 'bare' not in wf and 'suffix' in wf:
            problems.append(f"/{name}: reads {ref} (bare) but {base} is written SUFFIXED (per-session/project)")
print("OK" if not problems else "PROBLEMS\n" + "\n".join(problems))
PY
)
if [ "$RESULT" = "OK" ]; then
  pass
else
  fail "stale command scope-file references:"$'\n'"$RESULT"
fi

report
