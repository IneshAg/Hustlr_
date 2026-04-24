# Model Improvement Summary

Updated: 2026-04-14

## What Changed

- Switched the main leakage-sensitive models to a `70/30` train/test split.
- Kept grouped splits to avoid leakage:
  - ISS: grouped by onboarding month
  - Fraud: grouped by `worker_id`
  - NLP: grouped by normalized template text
- Added fraud threshold tuning and saved the deployment threshold in `hustlr-ml/models/trained/model3_thresholds.pkl`.
- Cleaned up Prophet artifact generation so backend-facing Chennai zone aliases are regenerated on each training run.
- Downloaded external public data into `hustlr-ml/outputs/external_data`:
  - `chennai_rainfall_1991_2023.csv`
  - `chennai_openmeteo_air_quality_2024_2025.json`
  - `openaq_chennai_locations.json`
  - `openaq_chennai_measurements.csv`

## Latest Metrics

- ISS
  - Train R^2: `0.8570`
  - Test R^2: `0.8230`
  - Train MAE: `2.979`
  - Test MAE: `3.291`

- Fraud
  - Train ROC-AUC: `0.9871`
  - Test ROC-AUC: `0.8302`
  - Test recall: `67.7%`
  - Test precision: `43.1%`
  - Deployment threshold: `0.42`

- NLP
  - Train accuracy: `0.9759`
  - Test accuracy: `0.9574`

- Prophet
  - Test MAE: `0.193`
  - Test MAPE: `5.4%`
  - Interval coverage: `93.6%`

## Artifact Status

Latest trained models are in `hustlr-ml/models/trained` (consolidated location).

Key files:

- `model1_iss_xgboost.pkl`
- `model3_fraud_classifier.json`
- `model3_thresholds.pkl`
- `model4_rf_nlp.json`
- `model5_iso_connectivity.pkl`
- `model6_traffic_classifier.json`
- `model7_prophet_tier_1.pkl`
- `model7_prophet_chennai.pkl`
- `model7_prophet_adyar.pkl`
- `model7_prophet_anna_nagar.pkl`
- `model7_prophet_chromepet.pkl`
- `model7_prophet_guindy.pkl`
- `model7_prophet_omr.pkl`
- `model7_prophet_perambur.pkl`
- `model7_prophet_sholinganallur.pkl`
- `model7_prophet_t_nagar.pkl`
- `model7_prophet_tambaram.pkl`
- `model7_prophet_velachery.pkl`

## Notes

- `openaq_chennai_measurements.csv` is currently sparse/empty from the queried sensors, so the most useful external additions right now are the OpenCity rainfall data and Open-Meteo air-quality history.
- Fraud recall improved substantially, but precision is still moderate.
- Prophet is now much stronger on the current dataset and its backend artifact names are consistent again.
