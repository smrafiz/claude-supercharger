Trust an MCP server to request credentials via Elicitation forms. Argument: $ARGUMENTS (a server name, or `--list`, or `--remove <server>`)

Supercharger's elicitation-guard declines any MCP server that asks for a password / token / API-key — in a form field or in the prompt text — via an `Elicitation` dialog, unless that server is trusted. Use this command to trust a server you recognize (e.g. your own database or GitHub MCP) so its legitimate credential prompts go through.

**Run it:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/trust-mcp.sh $ARGUMENTS
```

Then report the tool's output verbatim.

- No argument → show the current trusted list and the usage.
- `/trust-mcp <server>` → trust that server (matches the MCP server name the guard sees).
- `/trust-mcp --list` → list trusted servers.
- `/trust-mcp --remove <server>` → untrust a server.

**Security note:** only trust servers you recognize. A trusted server can request credential fields without being declined — that is the entire protection you are turning off for it. If you didn't expect a credential prompt, do NOT trust the server; investigate it instead.
