# SessionStart hook (Windows): prints the command that reopens this session in the Claude Desktop
# app after a credit cut-off, and appends it to ~/.claude/resume-commands.log.
$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
$id  = $j.session_id
$cwd = $j.cwd
if (-not $id) { exit 0 }

$claude = "claude"
foreach ($n in @("claude.cmd", "claude.exe", "claude")) {
  $c = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.Source -and $_.Source -notmatch '\.ps1$' } | Select-Object -First 1
  if ($c) { $claude = $c.Source; break }
}
if ($claude -eq "claude" -and (Test-Path "$env:APPDATA\npm\claude.cmd")) { $claude = "$env:APPDATA\npm\claude.cmd" }
$cmd = "Start-Process `"$claude`" -ArgumentList '--desktop','--resume','$id' -WorkingDirectory `"$cwd`" -WindowStyle Minimized"

$dir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss'Z'")
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::AppendAllText((Join-Path $dir "resume-commands.log"), "$stamp  $cmd`r`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $dir "last-resume-command.txt"), "$cmd`r`n", $utf8)

$msg = "RESUME COMMAND (run in PowerShell if credit runs out):`n$cmd`nAll sessions: ~/.claude/resume-commands.log"
$out = @{
  systemMessage = $msg
  hookSpecificOutput = @{ hookEventName = "SessionStart"; additionalContext = "This session's resume command is: $cmd  (If the user asks for it, give them exactly this.)" }
}
$out | ConvertTo-Json -Compress -Depth 4
