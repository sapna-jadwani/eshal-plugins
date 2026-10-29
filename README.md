# ESHAL plugins for Claude Code

A small Claude Code plugin marketplace from ESHAL AI. One plugin so far:

| Plugin | What it does |
|---|---|
| [usage-guard](usage-guard/) | Hands every Claude Desktop session its own resume command at start, prints a paste-ready "reopen all sessions" block when plan usage reaches 95 %, and adds `/resume-all`. On a Mac it finds the CLI bundled with the Desktop app, so it works even when `claude` was never added to PATH. |

## Install

Inside any Claude Code session:

```
/plugin marketplace add sapna-jadwani/eshal-plugins
/plugin install usage-guard@eshal-plugins
```

Then start a new session. A `RESUME COMMAND` line at the top means it is working.

To pick up a new version later:

```
/plugin marketplace update eshal-plugins
```

Each plugin's README covers its requirements and settings. The 95 % check needs the Claude Desktop app (Code tab); plain terminal sessions still get the per-session resume command and `/resume-all`.

## Credits

usage-guard is a fork, adapted for Macs, of [premnaraindas/usage-guard](https://github.com/premnaraindas/usage-guard) by Prem Naraindas (Katonic), MIT. The Windows scripts are his, unchanged.

## Licence

MIT. See [LICENSE](LICENSE).
