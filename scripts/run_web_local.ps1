$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# Use a unique Chrome profile each run to avoid stale debug sessions.
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$profile = Join-Path $env:TEMP ("hustlr_chrome_" + $stamp)

Write-Host "Starting Flutter web with local backend..." -ForegroundColor Cyan
Write-Host "Chrome profile: $profile" -ForegroundColor DarkCyan

flutter run -d chrome --dart-define=HUSTLR_API_BASE=http://localhost:3000 --web-browser-flag="--user-data-dir=$profile"
