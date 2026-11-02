# Demo assets

`claude.gif` (the README's top image) is a real Claude Code session, recorded with
`vhs assets/demo/claude.tape`: Haiku runs `rm -rf src`, Supercharger asks because
3 files have no undo, then a force push to `main` is blocked. It needs the `claude`
CLI logged in, Supercharger installed, `/tmp/my-app` trusted once, and costs two
short Haiku turns. Claude's own wording varies between takes.

The rest of this folder is the no-install version:
Terminal recording of Supercharger deciding on commands before they run: allowed,
blocked (exit code 2), or asked about first (with how many files have no undo),
then the statusline. Nothing executes, and every message is produced live by the
hooks in this checkout.

## Regenerate the GIF

```bash
brew install vhs            # https://github.com/charmbracelet/vhs
vhs assets/demo/demo.tape   # run from the repo root → writes assets/demo/demo.gif
```

Re-render after changing a hook message, so the GIF never shows old wording.

## Files

- `demo.tape` — VHS script driving the recording
- `try.sh` — pipes a command string through `safety.sh`, `git-safety.sh` and
  `blast-radius-guard.sh` and prints `BLOCKED` / `ASKS` / `allowed` with the reason.
  Reusable on its own: `./assets/demo/try.sh 'rm -rf /'` (`TRY_CWD=<dir>` sets the project)
- `fixture.sh` — creates a throwaway git project with committed, edited and
  never-committed files, so the `rm -rf src` prompt has real files to count
- `statusline.sh` — renders the real statusline from a fixed sample payload in a
  throwaway HOME (5-hour and weekly usage included)
- `demo.gif` — generated output of `demo.tape` (commit after regenerating)
- `claude.tape` / `claude.gif` — the real-session recording described above
