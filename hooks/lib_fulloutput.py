"""Keep the full tool output our trimmers cut, and say where it is.

bash-output-compactor, trace-compactor and mcp-output-truncator replace what the
model sees with a summary (updatedToolOutput). Before 4.4 the only full copy was
the session transcript, which the model cannot read back, so a line the summary
dropped was gone for the rest of the turn. Caveman's recovery handles showed the
fix (audited 2026-10-26): save the original, print where it went.

Files are 0600 under scope/ and pruned after a day by tools/scope-cleanup.sh.
They hold the same bytes Claude Code already writes to the transcript.
"""
import os
import time


def save(text):
    """Write text to a private file; return a one-line note naming it, or ''."""
    try:
        state = os.environ.get('SUPERCHARGER_STATE') or os.path.join(
            os.environ.get('HOME') or os.path.expanduser('~'), '.claude', 'supercharger')
        scope = os.path.join(state, 'scope')
        os.makedirs(scope, exist_ok=True)
        path = os.path.join(scope, '.full-output-%d-%d.txt' % (int(time.time()), os.getpid()))
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8', errors='replace') as f:
            f.write(text)
        return '\n[Supercharger: full output (%d chars) saved to %s; Read it if the summary dropped what you need]' % (len(text), path)
    except OSError:
        return ''


if __name__ == '__main__':
    import tempfile
    os.environ['SUPERCHARGER_STATE'] = tempfile.mkdtemp()
    note = save('line one\nFAIL: kept in full\n')
    p = note.split('saved to ')[1].split(';')[0]
    assert open(p).read() == 'line one\nFAIL: kept in full\n'
    assert oct(os.stat(p).st_mode & 0o777) == '0o600'
    print('ok')
