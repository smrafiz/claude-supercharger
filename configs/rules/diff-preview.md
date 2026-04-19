# Diff Preview Mode (opt-in)

Before writing or editing any file:
- Show the proposed change as a diff (what will be added/removed/modified)
- Wait for the user to approve before applying
- If the user says "apply" or "go", make the change
- If the user says "no" or suggests modifications, adjust and show again

Skip this for:
- New files with no existing content to diff against
- Changes the user explicitly dictated word-for-word
- Test runs, build commands, and read-only operations
