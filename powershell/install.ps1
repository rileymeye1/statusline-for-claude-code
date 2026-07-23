# Installer for the Claude Code status line — Windows (PowerShell).
# No external dependencies. Safe to re-run; backs up existing script and settings.json.
# Run from PowerShell:  .\install.ps1
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here 'statusline-command.ps1'
$confSrc = Join-Path (Split-Path -Parent $here) 'statusline.conf.example'   # shared config at repo root
$claudeDir = Join-Path $HOME '.claude'
$scriptPath = Join-Path $claudeDir 'statusline-command.ps1'
$confPath = Join-Path $claudeDir 'statusline.conf'
$settingsPath = Join-Path $claudeDir 'settings.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8 = New-Object System.Text.UTF8Encoding($false)   # UTF-8, no BOM (safe for JSON)

Write-Host 'Installing Claude Code status line (PowerShell)...'

if (-not (Test-Path $src)) { Write-Error "Cannot find $src"; exit 1 }
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

if (Test-Path $scriptPath) {
  Copy-Item $scriptPath "$scriptPath.bak-$stamp"
  Write-Host "  backed up existing script -> $scriptPath.bak-$stamp"
}
Copy-Item $src $scriptPath -Force
Write-Host "  installed script  -> $scriptPath"

# Config: install only if absent, so we never clobber the user's edits.
if (Test-Path $confSrc) {
  if (Test-Path $confPath) {
    Write-Host "  config exists     -> $confPath (left as-is)"
  } else {
    Copy-Item $confSrc $confPath -Force
    Write-Host "  installed config  -> $confPath"
  }
}

if (-not (Test-Path $settingsPath)) { [System.IO.File]::WriteAllText($settingsPath, '{}', $utf8) }
Copy-Item $settingsPath "$settingsPath.bak-$stamp"

try { $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json } catch { $settings = $null }
if ($null -eq $settings) { $settings = [pscustomobject]@{} }

$sl = [pscustomobject]@{ type = 'command'; command = 'powershell -NoProfile -File ~/.claude/statusline-command.ps1' }
if ($settings.PSObject.Properties.Name -contains 'statusLine') { $settings.statusLine = $sl }
else { $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $sl }

$json = $settings | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText($settingsPath, $json, $utf8)
Write-Host "  updated settings  -> $settingsPath (backup: $settingsPath.bak-$stamp)"
Write-Host ''
Write-Host 'Done. Restart Claude Code (or start a new session) to see the status line.'
