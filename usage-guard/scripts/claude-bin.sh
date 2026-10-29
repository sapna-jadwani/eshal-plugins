#!/bin/sh
# Prints the path of the Claude Code CLI to use for "claude --desktop --resume".
# Order: claude on PATH; else the newest CLI bundled with the Claude Desktop app
# (macOS: ~/Library/Application Support/Claude/claude-code/<version>/<build>/claude.app/...;
# Linux: ~/.config/Claude/claude-code/<version>/<build>/claude). Exit 1 if none is found.
# The same lookup is inlined into every generated resume line, so a pasted block keeps
# working after the Desktop app has updated its bundled CLI.
c=$(command -v claude 2>/dev/null)
[ -z "$c" ] && c=$(ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code"/*/*/claude 2>/dev/null | sort -V | tail -1)
[ -n "$c" ] || { echo "claude CLI not found: install it, or open the Claude Desktop app once" >&2; exit 1; }
printf '%s\n' "$c"
