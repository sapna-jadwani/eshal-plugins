#!/bin/sh
# SessionStart hook (macOS/Linux): prints the command that reopens this session in the Claude
# Desktop app after a credit cut-off, and appends it to ~/.claude/resume-commands.log.
# The command resolves the CLI itself (claude on PATH, else the Desktop app's bundled CLI),
# so it works on a Mac where claude was never added to PATH.
raw=$(cat)
id=$(printf '%s' "$raw" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
cwd=$(printf '%s' "$raw" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$id" ] && exit 0

resolver='c=$(command -v claude 2>/dev/null || ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code"/*/*/claude 2>/dev/null | sort -V | tail -1)'
cmd="(cd \"$cwd\" && $resolver && \"\$c\" --desktop --resume $id)"

dir="$HOME/.claude"
mkdir -p "$dir"
stamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")
printf '%s  %s\n' "$stamp" "$cmd" >> "$dir/resume-commands.log"
printf '%s\n' "$cmd" > "$dir/last-resume-command.txt"

# "claude --desktop" needs the CLI itself to be signed in, which is separate from the Desktop
# app's sign-in. Warn once per session start when it is not, with the exact command to run.
warn=""
bin=$(sh "$(dirname "$0")/claude-bin.sh" 2>/dev/null || true)
if [ -n "$bin" ] && "$bin" auth status 2>/dev/null | grep -q '"loggedIn": false'; then
  warn="CLI NOT SIGNED IN: the resume command will refuse to run until you sign the CLI in once: \"$bin\" auth login"
  printf '"%s" auth login\n' "$bin" > "$dir/cli-sign-in-command.txt"
fi

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
msg="RESUME COMMAND (run in a terminal if credit runs out):\\n$(esc "$cmd")\\nAll sessions: ~/.claude/resume-commands.log"
ctx="This session's resume command is: $(esc "$cmd")  (If the user asks for it, give them exactly this.)"
if [ -n "$warn" ]; then
  msg="$msg\\n$(esc "$warn")"
  ctx="$ctx $(esc "$warn")"
fi
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg" "$ctx"
