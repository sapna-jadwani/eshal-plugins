# Builds a paste-ready PowerShell block that reopens every recent Claude Desktop session
# (claude --desktop --resume <id>) after a credit cut-off.
#   resume-all.ps1            -> sessions active in the last 48 h, current app account
#   resume-all.ps1 -Hours 6   -> narrower window
#   resume-all.ps1 -All       -> every non-archived session of the account
# Output: printed to stdout, and saved to ~/.claude/resume-all-latest.ps1 (+ a stamped copy).
param([int]$Hours = 48, [switch]$All, [int]$GapSeconds = 12)

$claude = "claude"
foreach ($n in @("claude.cmd", "claude.exe", "claude")) {
  $c = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.Source -and $_.Source -notmatch '\.ps1$' } | Select-Object -First 1
  if ($c) { $claude = $c.Source; break }
}
if ($claude -eq "claude" -and (Test-Path "$env:APPDATA\npm\claude.cmd")) { $claude = "$env:APPDATA\npm\claude.cmd" }

$root = if ($env:CLAUDE_DESKTOP_SESSIONS_DIR) { $env:CLAUDE_DESKTOP_SESSIONS_DIR } else { Join-Path $env:APPDATA "Claude\claude-code-sessions" }
if (-not (Test-Path $root)) { Write-Error "no Claude Desktop session store at $root"; exit 1 }

# The account the app is signed into = the account/org folder with the most recently written session file.
$newest = Get-ChildItem $root -Recurse -Filter "local_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $newest) { Write-Error "no sessions found under $root"; exit 1 }
$acctDir = $newest.Directory.FullName
$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$Hours).ToUnixTimeMilliseconds()

$rows = foreach ($f in Get-ChildItem $acctDir -Filter "local_*.json") {
  try { $s = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
  if (-not $s.cliSessionId -or $s.isArchived) { continue }
  $last = 0; if ($s.lastActivityAt) { $last = [int64]$s.lastActivityAt }
  if (-not $All -and $last -lt $cutoff) { continue }
  [pscustomobject]@{ id = $s.cliSessionId; cwd = $s.cwd; title = $s.title; last = $last }
}
$rows = @($rows | Sort-Object last -Descending)

$acctLabel = Split-Path (Split-Path $acctDir -Parent) -Leaf
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm'Z'")
$scope = if ($All) { "all non-archived" } else { "last $Hours h" }
$lines = @("# Resume all Claude Desktop sessions - built $stamp, account $acctLabel, $($rows.Count) sessions ($scope)")
$lines += "# Paste the whole block into PowerShell. Launches are spaced $GapSeconds s apart so the app registers each one."
foreach ($r in $rows) {
  $when = [DateTimeOffset]::FromUnixTimeMilliseconds($r.last).ToUniversalTime().ToString("dd-MMM HH:mm'Z'")
  $t = ($r.title -replace "[\r\n]", " ")
  $lines += "# $when  $t"
  $lines += "Start-Process `"$claude`" -ArgumentList '--desktop','--resume','$($r.id)' -WorkingDirectory `"$($r.cwd)`" -WindowStyle Minimized; Start-Sleep -Seconds $GapSeconds"
}
$text = $lines -join "`r`n"

$dir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
Set-Content -Path (Join-Path $dir "resume-all-latest.ps1") -Value $text -Encoding utf8
Set-Content -Path (Join-Path $dir ("resume-all-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmm") + ".ps1")) -Value $text -Encoding utf8
$text
