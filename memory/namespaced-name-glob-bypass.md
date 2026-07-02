---
name: namespaced-name-glob-bypass
description: Scanners that map an invoked identifier to a file on disk must handle namespaced (plugin:name) forms, or the glob misses the file and the check is bypassed
metadata:
  type: project
---

Bug class (v2.7.54): a security hook that takes an invoked identifier and globs the filesystem for the matching file will silently BYPASS when the identifier is namespaced but the on-disk file is not.

Concrete case: `skill-poisoning-scanner.sh` globbed for `<skill>.md` / `<skill>/SKILL.md` using the raw `tool_input.skill`. Plugin skills are invoked as `plugin:skill` (per the Skill tool contract) but the file lives at `.../<skill>/SKILL.md` (bare name). So `plugin:skill` → glob matches nothing → file never read → skill loads UNSCANNED. Reproduced: bare `mskill` → exit 2 (blocked); `evilplugin:mskill` → exit 0 (allowed). Fix: also search the bare name via `re.split(r'[:/]', name)[-1]`, and dedup matches.

**Why:** the scanner's whole value is finding the file; a name→file mismatch defeats it silently (exit 0 looks identical to "scanned and clean").

**How to apply:** for ANY hook that resolves an invoked name to a path (skills, commands, agents, MCP tools), test the NAMESPACED invocation form, not just the bare one. If a bypass makes a check silently no-op, that's a security bug even though nothing errors. mcp-provenance.sh was audited alongside and found solid. Related: [[hook-contract-audit]].
