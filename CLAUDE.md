# claude-supercharger — project instructions

## Session handoff across machines

This project is worked on from more than one machine. `/handoff` behaves exactly as
its skill defines — per-session briefs at `.claude/handoff-<session-id>.md`, unchanged.
This project adds **one** thing on top:

**`.claude/handoff.md` is this project's carry file.** One file, tracked in git, so
state travels between machines. Per-session briefs stay session-scoped (two concurrent
sessions must not clobber one brief); the carry file is a derived summary of them.

**Read it first.** Before asking what the state is, read `.claude/handoff.md`. Its
`### Current State` block is the claim of record; `### Log` links the fuller briefs.

**Update it whenever you write a session brief**, in the same turn — never instead of
the brief:
- Replace `### Current State` wholly. Branch and HEAD, released version, open PRs,
  anything mid-flight, live open questions. Under ~15 lines.
- Prepend one `### Log` entry: `#### <date> — <first 8 of session id>`, two to four
  lines, and a `Detail:` line pointing at the per-session brief.
- Keep the last 5 log entries. Delete older ones; their brief files remain.

**Write Current State from what you verified this session**, not from the previous
Current State — that is how a wrong claim survives ten sessions.

**Label per-machine facts as per-machine.** Installed version, absolute paths, whether
a hook is live locally: the file is shared, the machine is not. This has already caused
one wrong reading — a brief said "the machine is on v4.1.8" and the next machine was
three releases behind.

**Do not rank briefs by file mtime.** `git checkout` rewrites mtimes, so after a clone
the newest-by-mtime brief is whichever file git happened to write last. Sort by the
date on line 1, or just read the carry file.
