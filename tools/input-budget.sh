#!/usr/bin/env bash
# Claude Supercharger — Input budget: what every session loads before the first prompt
#
# The economy tiers cut OUTPUT (Claude's replies). This measures INPUT: the
# instruction files Claude Code loads in full at session start, which are paid
# for on every session whether or not the task needs them:
#
#   global   ~/.claude/CLAUDE.md (+ @imports), ~/.claude/rules/*.md
#   project  CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md (+ @imports),
#            .claude/rules/*.md without a `paths:` frontmatter (path-scoped
#            rules load only when a matching file is touched; listed apart)
#   memory   ~/.claude/projects/<cwd>/memory/MEMORY.md (the auto-memory index)
#
# Supercharger's own files are marked, since those are the ones this project can
# slim for every user. Tokens are estimated as bytes / 4.
#
# Usage: tools/input-budget.sh [--line] [--dir PROJECT_DIR]
#   --line   one summary line (for /sc-status and /sc-doctor)
# Budget: SUPERCHARGER_INPUT_BUDGET_KB, else .supercharger.json "inputBudgetKb",
#         else 32 (KB). Report-only: exits 0 over budget, the line says so.
set -euo pipefail
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

MODE=table
DIR="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --line) MODE=line; shift ;;
    --dir) DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "input-budget: unknown argument: $1" >&2; exit 2 ;;
  esac
done

IB_MODE="$MODE" IB_DIR="$DIR" python3 - <<'PY'
import json, os, re, sys
home = os.environ.get('HOME') or os.path.expanduser('~')  # $HOME first: Windows expanduser reads %USERPROFILE%
cwd = os.path.realpath(os.environ['IB_DIR'])
FENCE = '`' * 3

def read(p):
    try:
        with open(p, encoding='utf-8', errors='replace') as f: return f.read()
    except OSError: return None

def imports(path, text, seen):
    """Claude Code follows @path imports (relative to the file, ~ or absolute)."""
    body = re.sub(FENCE + '.*?' + FENCE + r'|`[^`\n]*`', '', text, flags=re.S)
    for m in re.findall(r'(?<![\w/])@((?:~|\.{1,2})?/?[\w./-]+\.\w+)', body):
        p = home + m[1:] if m.startswith('~') else os.path.join(os.path.dirname(path), m)
        p = os.path.realpath(p)
        if p not in seen and os.path.isfile(p): yield p

def load(entries, group, rows, seen):
    todo = [os.path.realpath(p) for p in entries if os.path.isfile(p)]
    while todo:
        p = todo.pop(0)
        if p in seen: continue
        seen.add(p)
        t = read(p)
        if t is None: continue
        rows.append((group, p, len(t.encode())))
        todo += list(imports(p, t, seen))

def conditional(p):
    t = read(p) or ''
    m = re.match(r'---\n(.*?)\n---', t, re.S)
    return bool(m and re.search(r'^paths\s*:', m.group(1), re.M))

rows, seen, cond = [], set(), []
load([os.path.join(home, '.claude', 'CLAUDE.md')], 'global', rows, seen)
rd = os.path.join(home, '.claude', 'rules')
if os.path.isdir(rd):
    load(sorted(os.path.join(rd, f) for f in os.listdir(rd) if f.endswith('.md')), 'global', rows, seen)
load([os.path.join(cwd, f) for f in ('CLAUDE.md', os.path.join('.claude', 'CLAUDE.md'), 'CLAUDE.local.md')],
     'project', rows, seen)
prd = os.path.join(cwd, '.claude', 'rules')
if os.path.isdir(prd):
    for f in sorted(os.listdir(prd)):
        p = os.path.join(prd, f)
        if not f.endswith('.md') or not os.path.isfile(p): continue
        if conditional(p): cond.append((p, len((read(p) or '').encode())))
        else: load([p], 'project', rows, seen)
enc = '-' + cwd.replace(os.sep, '-').lstrip('-')
load([os.path.join(home, '.claude', 'projects', enc, 'memory', 'MEMORY.md')], 'memory', rows, seen)

OURS = ('supercharger.md', 'guardrails.md', 'economy.md', 'developer.md', 'writer.md', 'student.md',
        'data.md', 'pm.md', 'designer.md', 'devops.md', 'researcher.md')
def ours(group, p):
    return group == 'global' and (os.path.basename(p) in OURS or p == os.path.realpath(os.path.join(home, '.claude', 'CLAUDE.md')))

def sc_block_bytes(p):
    """Only the managed block of ~/.claude/CLAUDE.md is Supercharger's."""
    t = read(p) or ''
    i = t.find('# --- Claude Supercharger')
    return len(t[i:].encode()) if i >= 0 else 0

budget = os.environ.get('SUPERCHARGER_INPUT_BUDGET_KB')
if not budget:
    try: budget = json.load(open(os.path.join(cwd, '.supercharger.json'))).get('inputBudgetKb')
    except Exception: budget = None
try: budget = float(budget) if budget else 32.0
except ValueError: budget = 32.0

total = sum(b for _, _, b in rows)
sc = sum(sc_block_bytes(p) if p.endswith('CLAUDE.md') else b for g, p, b in rows if ours(g, p))
kb = lambda b: f'{b / 1024:.1f} KB'
tok = lambda b: f'~{b // 4:,} tok'
over = total > budget * 1024
state = f'OVER budget {budget:g} KB' if over else f'within {budget:g} KB'

if os.environ['IB_MODE'] == 'line':
    print(f'{kb(total)} ({tok(total)}) loaded every session — Supercharger {kb(sc)}; {state}')
    sys.exit(0)

short = lambda p: p.replace(home, '~', 1)
print('Input budget — loaded in full at every session start')
for group in ('global', 'project', 'memory'):
    g = [(p, b) for gg, p, b in rows if gg == group]
    if not g: continue
    print(f'\n  {group} ({kb(sum(b for _, b in g))})')
    for p, b in g:
        mark = ' [Supercharger]' if ours(group, p) else ''
        print(f'    {b:>7,} B  {short(p)}{mark}')
if cond:
    print('\n  path-scoped rules (load only for matching files, not counted)')
    for p, b in cond: print(f'    {b:>7,} B  {short(p)}')
print(f'\n  total {kb(total)} ({tok(total)}); Supercharger-managed {kb(sc)} ({tok(sc)}); {state}')
if any(g == 'memory' and b > 24400 for g, _, b in rows):
    print('  note: MEMORY.md is over the ~24.4 KB load ceiling; entries past it do not load')
PY
