<#
  Start Hustlr full stack: Python ML (8000) + Node API (3000) + Flutter app.

  **One terminal (recommended):** from repo root:
    npm install
    cd hustlr-backend && npm install
    npm run dev              # Android emulator API → 10.0.2.2:3000
    npm run dev:web          # Chrome → 127.0.0.1:3000
    npm run dev:stack        # only ML + Node (run Flutter from IDE)

  This script opens separate windows + launches Flutter (legacy flow).

  Default Flutter API target is Android emulator loopback (10.0.2.2 → host).

  Examples:
    .\scripts\start-dev.ps1
    .\scripts\start-dev.ps1 -ApiBase "http://192.168.1.10:3000"   # physical phone on Wi‑Fi
    .\scripts\start-dev.ps1 -ApiBase "http://127.0.0.1:3000"      # rare: special proxy setup

  Prerequisites: Python 3 with hustlr-ml deps, Node/npm in hustlr-backend, Flutter SDK.
  Optional: venv at hustlr-ml\.venv — set -UseVenv to use it for ML.
#>
param(
  [string]$ApiBase = "http://10.0.2.2:3000",
  [switch]$UseVenv
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mlDir = Join-Path $repoRoot "hustlr-ml"
$beDir = Join-Path $repoRoot "hustlr-backend"

$venvPy = Join-Path $mlDir ".venv\Scripts\python.exe"
$python = if ($UseVenv -and (Test-Path $venvPy)) { $venvPy } else { "python" }
if ($UseVenv -and -not (Test-Path $venvPy)) {
  Write-Warning "hustlr-ml\.venv not found — using 'python' from PATH"
}
if (-not (Get-Command $python -ErrorAction SilentlyContinue)) {
  Write-Error "Python not found. Install Python 3 or create hustlr-ml\.venv"
}

Write-Host ""
Write-Host "=== Hustlr dev stack ===" -ForegroundColor Cyan
Write-Host "  ML:    http://127.0.0.1:8000  (uvicorn)"
Write-Host "  API:   http://127.0.0.1:3000  (Node)"
Write-Host "  App:   Flutter → API $ApiBase"
Write-Host ""

$mlCmd = "Set-Location -LiteralPath '$mlDir'; & '$python' -m uvicorn main:app --host 127.0.0.1 --port 8000"
Write-Host "Opening window: ML service..." -ForegroundColor Green
Start-Process pwsh -ArgumentList @("-NoExit", "-Command", $mlCmd)

$beCmd = "Set-Location -LiteralPath '$beDir'; npm run dev"
Write-Host "Opening window: Node backend..." -ForegroundColor Green
Start-Process pwsh -ArgumentList @("-NoExit", "-Command", $beCmd)

Write-Host "Waiting for backends to boot..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

Set-Location -LiteralPath $repoRoot
Write-Host "Launching Flutter..." -ForegroundColor Green
flutter run --dart-define=HUSTLR_API_BASE=$ApiBase
