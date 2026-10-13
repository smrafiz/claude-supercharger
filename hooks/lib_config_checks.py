# Claude Supercharger — shared config-content checks
# One copy of the checks that read a config file's CONTENT and say what in it runs
# code, imported by:
#   config-scan.sh            SessionStart: the project's settings, .mcp.json, .git/config
#   file-watcher.sh           FileChanged: the same files when they change mid-session
#                             (git pull, gh pr checkout) — Chaindrop
#   git-config-exec-guard.sh  PreToolUse:Bash: a FOREIGN repo's .git/config before git
#                             runs there — GitSpawn
#   editor-config-guard.sh    PreToolUse:Write: .vscode/tasks.json folderOpen
# Keeping them here means the SessionStart scan and the mid-session rescan cannot
# drift. Stdlib only.
import json, os, re, sys  # subprocess is imported where used: the git guard's hot path rarely needs it
from pathlib import Path

protected = re.compile(r'^(Edit|Write|Bash|MultiEdit)$')

def scan_settings(path, settings, home_dir=''):
    out = []
    where = path.name
    if str(path).startswith(home_dir + '/.claude'):
        where = '~/.claude/' + where

    flagged_tools = set()
    for entry in settings.get('allowedTools', []) or []:
        if isinstance(entry, str) and protected.match(entry.strip()):
            flagged_tools.add(entry.strip())
    for entry in (settings.get('permissions', {}) or {}).get('allow', []) or []:
        if isinstance(entry, str) and protected.match(entry.strip()):
            flagged_tools.add(entry.strip())
    if flagged_tools:
        tools = ', '.join(sorted(flagged_tools))
        out.append(
            f'[SECURITY] {where} pre-approves bare {tools} — supercharger PreToolUse guards '
            f'(path-guard, env-file-guard, git-safety, safety) are silently bypassed for these '
            f'tools (claude-code#44482). Restrict to scoped patterns like "Edit(src/**)" or '
            f'remove from allow-list to restore protection.'
        )

    deny_read = (((settings.get('sandbox', {}) or {}).get('filesystem', {}) or {}).get('denyRead', []) or [])
    if deny_read:
        sample = ', '.join(deny_read[:3])
        more = len(deny_read) - 3
        suffix = f' (+{more} more)' if more > 0 else ''
        out.append(
            f'[SECURITY] {where} sets sandbox.filesystem.denyRead ({sample}{suffix}) — this field '
            f'is NOT enforced by Claude Code (claude-code#44274). Files in those paths are still '
            f'readable. Use supercharger env-file-guard.sh and path-guard.sh for actual read protection.'
        )

    default_mode = ((settings.get('permissions', {}) or {}).get('defaultMode', '')) or ''
    skip_perms = bool(settings.get('dangerouslySkipPermissions') or settings.get('dangerously_skip_permissions'))
    if default_mode == 'bypassPermissions' or skip_perms:
        field = 'permissions.defaultMode=bypassPermissions' if default_mode == 'bypassPermissions' else 'dangerouslySkipPermissions'
        out.append(
            f'[SECURITY] {where} sets {field} — this disables the trust dialog and runs all tools '
            f'without confirmation (CVE-2026-33068, patched v2.1.53). If this project file is from '
            f'a cloned repo you do not fully trust, remove the entry before continuing.'
        )

    # --- TrustFall (no CVE, May 2026, Anthropic won't patch): a cloned repo
    # ships settings with enableAllProjectMcpServers:true so every server in
    # project .mcp.json auto-spawns as an unsandboxed OS process the moment the
    # folder-trust dialog is accepted — no per-server prompt. In headless CI no
    # dialog appears at all. Surface it so the user reviews .mcp.json first.
    if settings.get('enableAllProjectMcpServers') is True:
        out.append(
            f'[SECURITY] {where} sets enableAllProjectMcpServers — every server in '
            f'project .mcp.json auto-starts as an UNSANDBOXED OS process on folder-trust, '
            f'with no per-server prompt (TrustFall, unpatched). Review .mcp.json before '
            f'trusting this folder; remove the flag if this repo is not fully trusted.'
        )

    plugin_marketplaces = settings.get('pluginSuggestionMarketplaces')
    if isinstance(plugin_marketplaces, list) and plugin_marketplaces:
        sample = ', '.join(plugin_marketplaces[:3])
        more = len(plugin_marketplaces) - 3
        suffix = f' (+{more} more)' if more > 0 else ''
        out.append(
            f'[INFO] {where} pins plugin suggestions to {len(plugin_marketplaces)} marketplace(s): '
            f'{sample}{suffix}. Plugin discovery in this session is scoped to that allowlist '
            f'(admin policy, v2.1.152+).'
        )

    # --- CVE-2026-35022: auth helper fields with shell metacharacters ---
    # apiKeyHelper and env.aws*/gcp* are passed via shell=true in CC auth flow.
    # A malicious project settings file can inject shell metacharacters to
    # achieve RCE through the auth helper execution path (fixed in v2.1.92+).
    _shell_meta = re.compile(r'[\$`;|&]')
    auth_helper_fields = [
        ('apiKeyHelper', settings.get('apiKeyHelper') or ''),
    ]
    env_block = settings.get('env') or {}
    if isinstance(env_block, dict):
        for _k in ('awsAuthRefresh', 'awsCredentialExport', 'gcpAuthRefresh'):
            auth_helper_fields.append((_k, env_block.get(_k) or ''))
    for field_name, field_val in auth_helper_fields:
        if not isinstance(field_val, str) or not field_val:
            continue
        m = _shell_meta.search(field_val)
        if m:
            sys.stderr.write(
                f'[Supercharger] config-scan: CVE-2026-35022: {field_name} in {where} '
                f'contains shell metachar {m.group(0)!r}\n'
            )
            out.append(
                f'[SECURITY] {where} sets {field_name} to a value containing shell '
                f'metacharacters ({m.group(0)!r}). Auth helper fields are executed via '
                f'shell=true in Claude Code — a malicious value achieves RCE via the '
                f'auth helper path (CVE-2026-35022, fixed v2.1.92). Verify this '
                f'setting is intentional and remove if from an untrusted source.'
            )
    return out


def mcp_server_risk(server, project_dir):
    if not isinstance(server, dict):
        return None
    cmd = server.get('command') or ''
    if not isinstance(cmd, str) or not cmd:
        return None  # http/sse servers have no command — not a spawn vector here
    args = server.get('args') if isinstance(server.get('args'), list) else []
    argstr = ' '.join(str(a) for a in args if isinstance(a, (str, int, float)))
    reasons = []
    rp = os.path.realpath(project_dir) if project_dir else ''
    if cmd.startswith('./') or cmd.startswith('../'):
        reasons.append('relative command path')
    elif '/' in cmd and not os.path.isabs(cmd):
        reasons.append('relative command path')
    elif os.path.isabs(cmd) and rp and os.path.realpath(cmd).startswith(rp):
        reasons.append('command points inside the project dir')
    if re.search(r'(^|\s)(\./|\.\./)', argstr):
        reasons.append('runs a project-local script (relative path in args)')
    if rp:
        for a in args:
            if isinstance(a, str) and a.startswith('/') and os.path.realpath(a).startswith(rp):
                reasons.append('an argument references a path inside the project')
                break
    return reasons or None

def settings_hook_commands(settings):
    """'<event>: <command>' for every hook a settings dict defines that is not ours."""
    out = []
    hooks_block = (settings or {}).get('hooks', {}) or {}
    if not isinstance(hooks_block, dict):
        return out
    for event, entries in hooks_block.items():
        for entry in (entries if isinstance(entries, list) else []):
            if not isinstance(entry, dict):
                continue
            for h in entry.get('hooks', []) or []:
                if not isinstance(h, dict):
                    continue
                cmd = h.get('command', '') or h.get('prompt', '')
                if cmd and isinstance(cmd, str) and '#supercharger' not in cmd:
                    out.append(f'{event}: {cmd[:80]}')
    return out


# --- git config keys git EXECUTES on ordinary operations (GitSpawn) ---
# A value that is SHELL-COMMAND-shaped (vs a plain program name / keyword).
CMD_SHAPE = re.compile(
    r'(^\s*!|\$\(|`|;|\||&&|\b(ba|z)?sh\s+-c\b|\bpython3?\s+-c\b|\bnode\s+-e\b|'
    r'\bperl\s+-e\b|\bruby\s+-e\b|/\S+\.(sh|py|rb|pl|js|ps1)\b)', re.I)
# A bare program name plus flags (`less -FRX`, `delta`): resolved on PATH, so not
# something a repo can carry. Anything else — a path, an argument naming a file —
# can point into the repo the config arrived with.
_BARE = re.compile(r'^[\w.+-]+(\s+-[\w=.-]+)*$')
_BOOL = ('', 'true', 'false', '0', '1', 'yes', 'no', 'on', 'off')
_LFS = re.compile(r'\s*git[- ]lfs\b')


def git_config_classify(key, val):
    """'exec' (runs a command whatever the value), 'plain' (a path-valued key a
    repo-shipped binary can sit behind), or None."""
    k = key.lower()
    v = val.strip()
    vl = v.lower()
    if k == 'core.fsmonitor':
        return 'exec' if vl not in _BOOL else None
    if re.match(r'filter\.[^.]+\.(clean|smudge|process)$', k):
        return None if _LFS.match(v) else 'exec'
    if re.match(r'(diff\.[^.]+\.(command|textconv)|(difftool|mergetool)\.[^.]+\.cmd)$', k):
        return 'exec'
    if k == 'core.hookspath':
        return 'plain' if v else None
    if k in ('core.sshcommand', 'core.pager') or k.startswith('pager.'):
        if k.startswith('pager.') and vl in _BOOL:
            return None
        if CMD_SHAPE.search(v):
            return 'exec'
        return None if (not v or _BARE.match(v)) else 'plain'
    if k in ('core.editor', 'credential.helper', 'core.askpass', 'sequence.editor',
             'diff.external', 'gpg.program') and CMD_SHAPE.search(v):
        return 'exec'
    return None


def git_config_hits(paths):
    """[(key, value, kind)] across config files, read with `git config --file`
    (read-only; follows include.path). Runs from / with GIT_* cleared, so git never
    discovers -- let alone operates in -- the repo these files belong to."""
    import subprocess
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    hits = []
    for cf in paths:
        if not os.path.isfile(cf):
            continue
        try:
            out = subprocess.run(['git', 'config', '--file', str(cf), '--includes', '--list'],
                                 capture_output=True, text=True, timeout=3,
                                 cwd=os.path.abspath(os.sep), env=env).stdout
        except Exception:
            continue
        for line in out.splitlines():
            k, _, v = line.partition('=')
            kind = git_config_classify(k, v)
            if kind:
                hits.append((k.lower(), v, kind))
    return hits


def git_dirs(path):
    """(gitdir, commondir) for a .git dir or a `gitdir:` file, else (None, None)."""
    p = Path(path)
    if p.is_file():
        try:
            m = re.match(r'gitdir:\s*(.+)', p.read_text(errors='replace').strip())
        except Exception:
            m = None
        if not m:
            return None, None
        g = Path(m.group(1).strip())
        p = g if g.is_absolute() else (p.parent / g)
    if not p.is_dir():
        return None, None
    gd = Path(os.path.realpath(p))
    common = gd
    try:
        c = (gd / 'commondir').read_text(errors='replace').strip()
        if c:
            common = Path(os.path.realpath(c if os.path.isabs(c) else gd / c))
    except Exception:
        pass
    return gd, common


def git_config_files(gitdir, commondir):
    return [commondir / 'config', gitdir / 'config.worktree']


# --- VS Code tasks that run on folder open ---
def _strip_jsonc(text):
    # tasks.json is JSONC: drop // and /* */ comments outside strings, trailing commas.
    out, i, n, q = [], 0, len(text), None
    while i < n:
        c = text[i]
        if q:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == q:
                q = None
        elif c == '"':
            q = c; out.append(c)
        elif text.startswith('//', i):
            j = text.find('\n', i); i = n if j < 0 else j; continue
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        else:
            out.append(c)
        i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))


def folder_open_tasks(text):
    """[(label, command)] for tasks with runOptions.runOn == folderOpen (tasks.json, or
    a .code-workspace's tasks block). The bare-key test editor-config-guard has always
    used stays the floor: text that does not parse (an Edit fragment) or names
    folderOpen somewhere the parse did not reach reports one unnamed task."""
    bare = [('?', '?')] if re.search(r'"?folderOpen"?', text) else []
    try:
        data = json.loads(_strip_jsonc(text))
    except Exception:
        return bare
    tasks = data.get('tasks') if isinstance(data, dict) else None
    if isinstance(tasks, dict):
        tasks = tasks.get('tasks')
    out = []
    for t in (tasks if isinstance(tasks, list) else []):
        if isinstance(t, dict) and ((t.get('runOptions') or {}).get('runOn') == 'folderOpen'):
            args = t.get('args') if isinstance(t.get('args'), list) else []
            cmd = ' '.join([str(t.get('command') or '')] +
                           [str(a.get('value', '') if isinstance(a, dict) else a) for a in args])
            out.append((str(t.get('label') or '?'), cmd.strip()[:100]))
    return out or bare
