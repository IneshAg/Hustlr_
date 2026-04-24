param(
  [switch]$SkipFraudTraining
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "[1/3] Delivery-time retraining with no-regression guard..."
python scripts/train_delivery_time_v3.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[2/3] Delivery-time evaluation..."
python scripts/evaluate_delivery_model.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $SkipFraudTraining) {
  Write-Host "[3/3] Existing fraud pipeline training..."
  python scripts/train_all_local.py
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "[3/3] Skipped fraud pipeline training."
}

Write-Host "Pipeline finished successfully."
