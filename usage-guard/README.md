# usage-guard

A Claude Code plugin for people who run many Claude Desktop sessions at once and get cut off when a plan limit resets. It does three things:

1. **Every session hands you its own resume command at start.** A `SessionStart` hook prints the command that reopens that session as a tab in the Claude Desktop app, and appends it to `~/.claude/resume-commands.log`.
2. **At 95 % plan usage it prints a paste-ready block for all sessions.** A `UserPromptSubmit` hook asks Claude to check plan usage at the end of every turn. At the threshold it runs the generator and prints one line per recent session, spaced 12 s apart. Paste the block into a terminal after the reset and every session comes back.
3. **`/resume-all` gives you that block on demand.**

This is a fork of [premnaraindas/usage-guard](https://github.com/premnaraindas/usage-guard) with one change: on macOS and Linux the generated commands find the Claude Code CLI themselves. `claude` on PATH is used when present; otherwise the newest CLI bundled with the Claude Desktop app is used. Without that, every resume line fails on a Mac that runs Claude Code only through the Desktop app, which is the common case.

## Requirements

- Claude Code **in the Claude Desktop app** (Code tab). The usage check uses the app's `get_usage` tool, which plain CLI sessions do not have. In a plain CLI session the hooks stay silent.
- macOS/Linux: `python3` or `node` for reading the app's session records. `claude` on PATH is optional: the Desktop app's bundled CLI is found when it is missing.
- The CLI signed in once (`claude auth login`, or the full path the start line prints followed by `auth login`). The Desktop app's own sign-in does not count: `--desktop` refuses to run until the CLI has an account. The start line warns when this is missing.
- Windows: Git for Windows (Claude Code already needs it), `claude` on PATH. The scripts run under Windows PowerShell 5.1, which every Windows has.

## Install

From GitHub, inside any Claude Code session:

```
/plugin marketplace add sapna-jadwani/eshal-plugins
/plugin install usage-guard@eshal-plugins
```

From an organization library on claude.ai, where an admin has published it: enable it under Plugins and it applies to your Claude Code sessions.

From a folder, for one session:

```bash
claude --plugin-dir /path/to/usage-guard
```

Or add the folder as a local marketplace and install it with `/plugin`.

Two things to remove first, or each hook fires twice:

- the same hooks wired by hand in `~/.claude/settings.json`;
- the original plugin, if you have it: `/plugin uninstall usage-guard@katonic-plugins`.

## How a resume works

`claude --desktop --resume <session-id>` reopens that transcript as a tab in the Desktop app. The app matches it to the existing sidebar entry, so there is no duplicate. The tab opens idle: nothing continues until you send a prompt.

- Keep launches 7 to 18 s apart. Back-to-back launches fail to register. The generated block uses 12 s.
- The reopened tabs run under the account the Desktop app is signed into, which can differ from the CLI's `/login` account.
- The usage windows reported are the 5-hour and weekly plan windows. An organization monthly spend limit is not visible to the check.
- `--desktop` needs a real terminal. It refuses to run with redirected output, so paste the block into Terminal, iTerm or the app's own Terminal panel, not into a script that captures output. On Windows the resume line is `Start-Process ... claude.cmd --desktop --resume <id>` for the same reason.
- On macOS/Linux the first line of the block sets `c` to the CLI path; every later line runs `"$c" --desktop --resume <id>`. The lookup happens when you paste, so the block survives a Desktop app update that moved the bundled CLI.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `USAGE_GUARD_THRESHOLD` | `95` | Percent of any plan window at which the block is printed |
| `CLAUDE_DESKTOP_SESSIONS_DIR` | app default | Override the Desktop app's session-record folder |

Generator arguments (`/resume-all` passes them through): `-Hours N` (default 48), `-All` (every non-archived session), `-GapSeconds N` (default 12).

## Files

```
.claude-plugin/plugin.json        manifest
hooks/hooks.json                  SessionStart + UserPromptSubmit wiring
scripts/run.sh                    dispatcher: PowerShell on Windows, sh elsewhere
scripts/claude-bin.sh             prints the CLI path (PATH, else the Desktop app's bundled CLI)
scripts/print-resume-command.ps1  SessionStart (Windows)
scripts/print-resume-command.sh   SessionStart (macOS/Linux)
scripts/resume-all.ps1            block generator (Windows)
scripts/resume-all.sh             block generator (macOS/Linux)
scripts/usage-check-reminder.sh   UserPromptSubmit (all platforms)
skills/resume-all/SKILL.md        /resume-all
```

Outputs land in `~/.claude/`: `resume-commands.log`, `last-resume-command.txt`, `cli-sign-in-command.txt` (only while the CLI is not signed in), `resume-all-latest.ps1` or `.sh` plus a timestamped copy per run.

## Tested

29 Oct 2026 on macOS 26 (Apple Silicon), Claude Code 2.1.309 bundled with the Desktop app, `claude` not on PATH, python3 3.9 and node 26:

- `SessionStart` hook fires through `--plugin-dir`: a real session id landed in `resume-commands.log` and the hook output parsed as JSON.
- The printed resume command resolves the bundled CLI from a clean environment (`PATH=/usr/bin:/bin`).
- `resume-all.sh` builds the same 5-session block on the python3 branch and on the node branch (python3 hidden).
- `UserPromptSubmit` hook output parses as JSON.
- `--desktop --resume <id>` from a terminal was not completed on this Mac: the bundled CLI had never been signed in and refused with "requires signing in with a Claude account". The hook now warns about that at session start and writes the sign-in command to `~/.claude/cli-sign-in-command.txt`. Reopening a tab after `auth login` is the one step still to verify on a Mac.

Windows: the upstream plugin was tested by its author on 22 Oct 2026 (Windows 11, Claude Code 2.1.306, Desktop app 3.16), including an 11-session resume block. The Windows scripts here are unchanged from that version.
