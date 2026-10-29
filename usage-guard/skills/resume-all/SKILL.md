---
name: resume-all
description: Print a paste-ready block that reopens every recent Claude Desktop session after a credit cut-off. Use when the user asks for the resume-all list, to resume all sessions, or for the command to reopen their sessions after the limit resets.
---

# Resume all sessions

Run the generator and show the user its whole output in a code block they can paste into a terminal:

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/run.sh" resume-all
```

- On Windows the block is PowerShell (`Start-Process ... claude --desktop --resume <id>`); print it in a `powershell` fenced block.
- On macOS/Linux the block is shell; print it in a `bash` fenced block. Its first line finds the Claude Code CLI (`claude` on PATH, else the one bundled with the Desktop app), and each later line reopens one session with `"$c" --desktop --resume <id>`.
- Arguments pass straight through: `-Hours 6` narrows the window (default 48 h), `-All` takes every non-archived session, `-GapSeconds 15` changes the spacing (default 12 s).

The same block is saved under `~/.claude/resume-all-latest.*` with a timestamped copy next to it.

What the block does when pasted: each line reopens one session as a tab in the Claude Desktop app. Resuming only opens the tab; nothing continues on its own until the user sends a prompt. Launches must stay spaced out or the app fails to register some of them. The reopened tabs run under the account the Desktop app is signed into.
