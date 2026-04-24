# Dataset Notes

## Delivery-time model

- Primary dataset path: `C:/Users/inesh/Downloads/train.csv`
- External augmentation (already downloaded previously):
  - `C:/Users/inesh/Downloads/external_datasets/openml_46928_food_delivery_time.csv`

## Validation policy

- Use fixed-seed split from `config/delivery_time_v3.json`.
- Preserve stratification using target quantile bins.
- Reject new model artifact when MAE is worse than best known baseline.

## Generated reports

- `C:/Users/inesh/Downloads/model_outputs/delivery_time_improvement_report_v3.json`
- `C:/Users/inesh/Downloads/model_outputs/delivery_time_eval_report.json`
