#!/bin/sh
# Dispatcher: runs scripts/<name>.ps1 under Windows PowerShell on Windows (Claude Code runs
# hook commands through Git Bash there), otherwise scripts/<name>.sh. Extra arguments and
# stdin are passed through unchanged.
#   sh run.sh print-resume-command      (SessionStart hook; reads the hook JSON on stdin)
#   sh run.sh resume-all [-Hours N] [-All] [-GapSeconds N]
name="$1"; shift
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

is_windows=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) is_windows=1 ;; esac
[ "${OS:-}" = "Windows_NT" ] && is_windows=1
[ -n "${USAGE_GUARD_FORCE_POSIX:-}" ] && is_windows=0

if [ "$is_windows" = 1 ]; then
  exec powershell -NoProfile -ExecutionPolicy Bypass -File "$root/scripts/$name.ps1" "$@"
else
  exec sh "$root/scripts/$name.sh" "$@"
fi
