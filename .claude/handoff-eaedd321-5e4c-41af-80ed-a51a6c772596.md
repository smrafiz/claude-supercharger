## Handoff — claude-supercharger — 2026-11-18 (session eaedd321)

### Outcome
Reviewed, fixed and merged #324–#333, then released **v4.4.8** (tag on `68071b2a`).

### What happened
- Read-only reviewers found that three of the five open code PRs made a guard fail OPEN:
  - #326 approval gate: any command containing the text `UserPromptSubmit` took the prompt branch and was allowed. Fixed by branching on the parsed `.hook_event_name`.
  - #329 quoted-pipe scanner: `"$(echo "it's")"` nesting and an apostrophe inside a `#` comment masked a real `| sh`. Fixed by bailing (masking nothing) on `$(`, backticks and unquoted `#`.
  - #325 memokit delta: `eval "$(brew shellenv)" "$(cat x)"` was neutralised because only the FIRST eval argument was checked. Fixed by anchoring the match to the end of the simple command.
- #331 (new): a `>|` (noclobber) redirect slipped past four guards: selfmod, shell profile, readonly-guard and harness-tamper-guard. harness-tamper splits on every `|`, so `>|` separated the redirect from its target.
- #332: disk-watch put its state file into `$(( ))`. `PATH[$(cmd)]` ran on the hook as merged in #327, which was never released. Also: `df` column parsing and a timeout test that proves the timeout.
- #333: `safety.sh` exited 128 silently on fork exhaustion (reproduced with `ulimit -u`). It now has a builtin-only EXIT trap that turns any rc other than 0/2 into a deny. A grep error now counts as a hit. A `--build-arg` dangerous pattern never matched (grep read it as an option); fixed with `grep -e`.
- #330: shellcheck now runs on ubuntu only. The macOS leg was cancelled because no runner was ever acquired (capacity), not because it hung.

### Decisions
- Dropped "register disk-watch on Bash only": test-powershell-parity requires every PostToolUse hook on Bash to also run on PowerShell. That parity is deliberate.
- #328 cache eviction was left out as a new feature, not a fix.

### What failed / lessons
- I first called the macOS shellcheck cancellations "hangs". The check-run annotations said "job was not acquired by Runner". Read the annotations first.
- Three full suites run in parallel produced load-only failures (perf-chain statusline; quoted-pipe case B). The quoted-pipe case turned out to be a real fail-open (fork exhaustion → rc 128), fixed in #333.
- `set -- $var` does not word-split in zsh. It broke a push loop and a merge step this session; the merge was redone by hand at the tested head.
- A "clean" git merge kept hook count 178 where 179 was right (#326 and #328 each added one). Run test-install after every merge of two PRs that each add a hook.

### Not done
- A crash before safety.sh installs its trap (inside lib-timing/lib-paths) still relies on `onFailure`.
- Variable-built paths still bypass the string-matching guards (accepted limit).
- This machine's install is still v4.4.7: run `/sc-update`.
