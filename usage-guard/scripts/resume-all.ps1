# Builds a paste-ready PowerShell block that reopens every recent Claude Desktop session
# (claude --desktop --resume <id>) after a credit cut-off.
#   resume-all.ps1                  -> sessions active in the last 48 h
#   resume-all.ps1 -Hours 6         -> narrower window
#   resume-all.ps1 -All             -> every non-archived session
#   resume-all.ps1 -IncludeChildren -> also reopen child side-sessions (see below)
# The app keeps one record per session per store folder (<store>\<folder>\<org>\local_*.json) and a
# session touched from several app instances has a copy in each folder, so every folder of the current
# org is read and one line is built per CLI session id from its latest record.
# Child side-sessions (started from another session through a task card) are grouped under their
# parent and commented out: a resume by id opens a standalone tab that no longer sits under the
# parent, and the parent's own line already brings the parent back. -IncludeChildren turns their
# lines on. A child whose parent is not in the block is listed in a trailing group, also commented.
# Output: printed to stdout, and saved to ~/.claude/resume-all-latest.ps1 (+ a stamped copy).
param([int]$Hours = 48, [switch]$All, [int]$GapSeconds = 12, [switch]$IncludeChildren)

$claude = "claude"
foreach ($n in @("claude.cmd", "claude.exe", "claude")) {
  $c = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.Source -and $_.Source -notmatch '\.ps1$' } | Select-Object -First 1
  if ($c) { $claude = $c.Source; break }
}
if ($claude -eq "claude" -and (Test-Path "$env:APPDATA\npm\claude.cmd")) { $claude = "$env:APPDATA\npm\claude.cmd" }

$root = if ($env:CLAUDE_DESKTOP_SESSIONS_DIR) { $env:CLAUDE_DESKTOP_SESSIONS_DIR } else { Join-Path $env:APPDATA "Claude\claude-code-sessions" }
if (-not (Test-Path $root)) { Write-Error "no Claude Desktop session store at $root"; exit 1 }

# The org the app is signed into = the org sub-folder holding the most recently written record.
$files = @(Get-ChildItem $root -Recurse -Filter "local_*.json")
if ($files.Count -eq 0) { Write-Error "no sessions found under $root"; exit 1 }
$newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$org = $newest.Directory.Name
$files = @($files | Where-Object { $_.Directory.Name -eq $org })
$folders = @($files | ForEach-Object { $_.Directory.Parent.FullName } | Sort-Object -Unique)
$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$Hours).ToUnixTimeMilliseconds()

# JavaScriptSerializer parses a few thousand records in seconds; ConvertFrom-Json takes minutes.
Add-Type -AssemblyName System.Web.Extensions
$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$json.MaxJsonLength = [int]::MaxValue
$records = @(foreach ($f in $files) {
  try { $json.DeserializeObject([IO.File]::ReadAllText($f.FullName)) } catch { continue }
})
function Get-Field($d, [string]$k) { if ($d -is [System.Collections.IDictionary] -and $d.ContainsKey($k)) { $d[$k] } else { $null } }

# A child's spawnedFrom.sessionId names the parent's RECORD id (local_...), which differs from the
# parent's CLI session id once the parent has been resumed, so record ids are resolved over every
# record, archived and out-of-window ones included.
$recToCli = @{}
foreach ($s in $records) {
  $rec = Get-Field $s 'sessionId'; $cli = Get-Field $s 'cliSessionId'
  if ($rec -and $cli) { $recToCli[[string]$rec] = [string]$cli }
}

# One row per CLI session: latest record wins for title/cwd/time/archived; the parent link counts
# from any record, because a resumed copy of a child does not carry it.
$latest = @{}; $parentOf = @{}
foreach ($s in $records) {
  $id = Get-Field $s 'cliSessionId'
  if (-not $id) { continue }
  $id = [string]$id
  $last = 0; $la = Get-Field $s 'lastActivityAt'; if ($la) { $last = [int64]$la }
  $sf = Get-Field $s 'spawnedFrom'
  $parentRec = Get-Field $sf 'sessionId'
  if ($parentRec) {
    $parentRec = [string]$parentRec
    $p = $recToCli[$parentRec]
    if (-not $p -and $parentRec -match '^local_(.+)$') { $p = $Matches[1] }
    if ($p) { $parentOf[$id] = $p }
  }
  if (-not $latest.ContainsKey($id) -or $latest[$id].last -lt $last) {
    $latest[$id] = [pscustomobject]@{ id = $id; cwd = [string](Get-Field $s 'cwd'); title = [string](Get-Field $s 'title'); last = $last; archived = [bool](Get-Field $s 'isArchived'); parent = $null }
  }
}
$rows = foreach ($r in $latest.Values) {
  if ($r.archived) { continue }
  if (-not $All -and $r.last -lt $cutoff) { continue }
  if ($parentOf.ContainsKey($r.id)) { $r.parent = $parentOf[$r.id] }
  $r
}
$rows = @($rows | Sort-Object last -Descending)

$byId = @{}; foreach ($r in $rows) { $byId[$r.id] = $r }
$roots = @($rows | Where-Object { -not $_.parent })
$children = @($rows | Where-Object { $_.parent })
$orphans = @($children | Where-Object { -not $byId.ContainsKey($_.parent) })

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm'Z'")
$scope = if ($All) { "all non-archived" } else { "last $Hours h" }
$childNote = ""
if ($children.Count -gt 0) {
  $childNote = if ($IncludeChildren) { " + $($children.Count) child side-sessions" } else { " + $($children.Count) child side-sessions commented out" }
}
$lines = @("# Resume all Claude Desktop sessions - built $stamp, org $org, $($roots.Count) sessions$childNote ($scope, $($folders.Count) store folders)")
$lines += "# Paste the whole block into PowerShell. Launches are spaced $GapSeconds s apart so the app registers each one."
if ($children.Count -gt 0 -and -not $IncludeChildren) {
  $lines += "# Child side-sessions sit under their parent as comments: a resume by id opens them as standalone tabs. Rerun with -IncludeChildren to reopen them too."
}

function Format-Row($r, [bool]$asChild) {
  $when = [DateTimeOffset]::FromUnixTimeMilliseconds($r.last).ToUniversalTime().ToString("dd-MMM HH:mm'Z'")
  $t = ($r.title -replace "[\r\n]", " ")
  $cmd = "Start-Process `"$claude`" -ArgumentList '--desktop','--resume','$($r.id)' -WorkingDirectory `"$($r.cwd)`" -WindowStyle Minimized; Start-Sleep -Seconds $GapSeconds"
  if ($asChild) {
    $prefix = if ($IncludeChildren) { "  " } else { "#   " }
    @("#   child $when  $t", "$prefix$cmd")
  } else {
    @("# $when  $t", $cmd)
  }
}

foreach ($r in $roots) {
  $lines += Format-Row $r $false
  foreach ($c in @($children | Where-Object { $_.parent -eq $r.id })) { $lines += Format-Row $c $true }
}
if ($orphans.Count -gt 0) {
  $lines += "# Child side-sessions whose parent is not in this block (archived or outside the window):"
  foreach ($c in $orphans) { $lines += Format-Row $c $true }
}
$text = $lines -join "`r`n"

$dir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
Set-Content -Path (Join-Path $dir "resume-all-latest.ps1") -Value $text -Encoding utf8
Set-Content -Path (Join-Path $dir ("resume-all-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmm") + ".ps1")) -Value $text -Encoding utf8
$text
