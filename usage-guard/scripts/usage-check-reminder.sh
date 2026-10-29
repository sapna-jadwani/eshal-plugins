#!/bin/sh
# UserPromptSubmit hook: tells Claude to check plan usage at the end of the turn and, at the
# threshold or above, run resume-all and print the paste-ready block so every session can be
# reopened after the reset. Threshold: USAGE_GUARD_THRESHOLD (default 95).
threshold="${USAGE_GUARD_THRESHOLD:-95}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

ctx="USAGE GUARD (standing instruction from the user): before you end this turn, call mcp__ccd_session_mgmt__get_usage. \
If ANY plan window (5-hour, weekly, per-model) shows percentUsed >= $threshold, run: sh \"$root/scripts/run.sh\" resume-all \
and print its full output to the user in a powershell code block (bash block on macOS/Linux), headed 'CREDIT AT <n> % - paste this into your terminal after the reset to reopen all sessions'. \
Below $threshold %, print nothing about usage. If the get_usage tool does not exist in this session (plain CLI, not the Desktop app), do nothing and say nothing about it."

# JSON-escape the backslashes and double quotes in the context string.
esc=$(printf '%s' "$ctx" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$esc"
