# hustlr-ml

Machine learning workspace for Hustlr fraud and delivery-time models.

## What was improved

- Added local-only artifact hygiene using `.gitignore`.
- Added config-driven delivery-time retraining script with no-regression guard.
- Added standalone evaluation script for saved delivery-time model artifacts.
- Added one-command Windows pipeline runner.

## Folder guide

- `scripts/` training, diagnostics, and utility scripts.
- `config/` reproducible runtime configs.
- `docs/` dataset and workflow notes.
- `models/` local model artifacts used by services.
- `outputs/` generated reports, metrics, and transformed data.
- `services/` online serving code.

## Delivery-time workflow

1. Train with guard:

```powershell
python scripts/train_delivery_time_v3.py
```

2. Evaluate selected artifact:

```powershell
python scripts/evaluate_delivery_model.py
```

3. Run both with one command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_ml_pipeline.ps1
```

## Notes

- `config/delivery_time_v3.json` points to your existing dataset and output location in `C:/Users/inesh/Downloads`.
- The trainer writes `delivery_time_improvement_report_v3.json` and keeps previous best if a new candidate regresses.
