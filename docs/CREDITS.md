# Credits

[Back to README](../README.md)

Supercharger builds on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), and others.

The security layer adapts enforcement patterns from several MIT-licensed guardrail projects:

- [efij/secure-claude-code (Stallion)](https://github.com/efij/secure-claude-code): cloud, container, persistence, exfiltration and MCP vectors
- [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails): staged-diff secret scan and crypto keys
- [wintermeyer/heinzel](https://github.com/wintermeyer/heinzel): disk and partition rules
- [mafiaguy/claude-security-guardrails](https://github.com/mafiaguy/claude-security-guardrails): docker, system power and scp exfiltration
- [Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness): file lease, fact gate, MCP circuit breaker
- [domengabrovsek/claude](https://github.com/domengabrovsek/claude): the commit-attribution gate concept

All were re-implemented independently as self-contained bash and Python. See [NOTICE](../NOTICE) for attributions.
