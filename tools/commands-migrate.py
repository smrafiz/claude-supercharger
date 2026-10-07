#!/usr/bin/env python3
"""Reconcile ~/.claude/commands with this release's slash commands.

4.3.0 renamed every command to sc-<name>. A file is only ever replaced or
removed when its content matches a version we shipped (configs/commands-shipped.txt);
a file the user wrote or edited is never touched, only reported.

  install   <commands_dir> <repo_dir>  old names -> redirect stub; dropped names -> removed
  uninstall <commands_dir> <repo_dir>  our unmodified files, old names and stubs -> removed
"""
import hashlib, os, sys

STUB_MARK = '<!-- supercharger:renamed -->'


def sha(data):
    return hashlib.sha256(data.replace(b'\r', b'')).hexdigest()


def stub(old, new):
    # User-only and description-less in context: a redirect must not cost tokens every turn.
    return (f'---\ndescription: "Renamed: use /{new}"\ndisable-model-invocation: true\n---\n'
            f'{STUB_MARK}\n'
            f'`/{old}` was renamed to `/{new}` in Supercharger 4.3.0 (this redirect goes away in 4.4.0).\n\n'
            f'Tell the user, in one line, that `/{old}` is now `/{new}`. Then run `/{new}` with: $ARGUMENTS\n')


def main():
    mode, cmd_dir, repo = sys.argv[1:4]
    shipped = {}
    with open(os.path.join(repo, 'configs', 'commands-shipped.txt')) as f:
        for line in f:
            name, h = line.split()
            shipped.setdefault(name, set()).add(h)
    current = {n[:-3] for n in os.listdir(os.path.join(repo, 'configs', 'commands')) if n.endswith('.md')}

    for name in sorted(shipped):
        path = os.path.join(cmd_dir, name + '.md')
        if not os.path.isfile(path):
            continue
        with open(path, 'rb') as f:
            data = f.read()
        new = 'sc-' + name
        is_stub = new in current and data.replace(b'\r', b'') == stub(name, new).encode()
        ours = sha(data) in shipped[name]
        if mode == 'uninstall':
            if ours or is_stub:
                os.remove(path)
            continue
        if name in current or is_stub:
            continue
        if not ours:
            if new in current:
                print(f'  /{name}: you edited it, so it was left alone; the Supercharger command is now /{new}')
            continue
        if new in current:
            with open(path, 'wb') as f:  # binary: text mode writes CRLF on Windows
                f.write(stub(name, new).encode())
            print(f'  /{name} -> /{new}')
        else:
            os.remove(path)


if __name__ == '__main__':
    main()
