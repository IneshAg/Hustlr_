"""
Train ISS regressor — feature order must match hustlr-ml/main.py /iss ML branch.
"""

import joblib
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error
from sklearn.metrics import r2_score
from sklearn.linear_model import Ridge
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from xgboost import XGBRegressor

from model_data_utils import grouped_train_test_indices, month_groups

PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "trained"
DATASETS_DIR = PROJECT_ROOT / "outputs" / "datasets"
WORKER_CSV = DATASETS_DIR / "worker_profiles.csv"
TEST_SIZE = 0.30

# Same order as main.py calculate_iss X row (after flood blending, training uses zone_flood_risk proxy).
ISS_FEATURE_NAMES = [
    "zone_flood_risk",
    "avg_daily_income",
    "disruption_freq_12mo",
    "claims_history_penalty",
    "bandh_freq_zone",
    "platform_outage_per_mo",
    "coastal_zone",
]


def train_iss_model():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    print("Training Model 1 — ISS (XGBoost regressor)")

    if not WORKER_CSV.is_file():
        raise FileNotFoundError(f"Missing dataset: {WORKER_CSV}")

    df = pd.read_csv(WORKER_CSV)
    for c in ISS_FEATURE_NAMES:
        if c not in df.columns:
            raise ValueError(f"worker_profiles.csv missing column: {c}")
    if "iss_score" not in df.columns:
        raise ValueError("worker_profiles.csv missing iss_score target column")

    X = df[ISS_FEATURE_NAMES].astype(float).values
    y = df["iss_score"].astype(float).clip(0, 100).values

    if "onboard_date" not in df.columns:
        raise ValueError("worker_profiles.csv must include onboard_date for leakage-safe ISS splitting")

    train_idx, test_idx = grouped_train_test_indices(
        month_groups(df["onboard_date"]),
        test_size=TEST_SIZE,
        random_state=42,
    )
    X_tr, X_te = X[train_idx], X[test_idx]
    y_tr, y_te = y[train_idx], y[test_idx]

    model = XGBRegressor(
        n_estimators=300,
        max_depth=4,
        learning_rate=0.06,
        subsample=0.85,
        random_state=42,
        tree_method="hist",
        n_jobs=-1,
        device="cpu",
    )
    model.fit(X_tr, y_tr)
    pred_tr = np.clip(model.predict(X_tr), 0, 100)
    pred = np.clip(model.predict(X_te), 0, 100)
    ridge = Pipeline([
        ("scale", StandardScaler()),
        ("ridge", Ridge(alpha=2.0, random_state=42)),
    ])
    ridge.fit(X_tr, y_tr)
    ridge_pred = np.clip(ridge.predict(X_te), 0, 100)
    print(f"Train MAE (ISS): {mean_absolute_error(y_tr, pred_tr):.3f}")
    print(f"Test MAE (ISS):  {mean_absolute_error(y_te, pred):.3f}")
    print(f"Train R^2 (ISS): {r2_score(y_tr, pred_tr):.4f}")
    print(f"Test R^2 (ISS):  {r2_score(y_te, pred):.4f}")
    print(f"Baseline Ridge Test MAE: {mean_absolute_error(y_te, ridge_pred):.3f}")
    print(f"Baseline Ridge Test R^2: {r2_score(y_te, ridge_pred):.4f}")
    print(f"Workers: {len(df)} | zones: {df['zone'].nunique()} | onboard months: {month_groups(df['onboard_date']).nunique()}")

    joblib.dump(model, MODELS_DIR / "model1_iss_xgboost.pkl")
    joblib.dump(ISS_FEATURE_NAMES, MODELS_DIR / "model1_features.pkl")
    joblib.dump(ridge, MODELS_DIR / "model1_baseline_ridge.pkl")
    (MODELS_DIR / "model1_diagnostics.json").write_text(
        json.dumps(
            {
                "test_size": TEST_SIZE,
                "xgboost_test_mae": mean_absolute_error(y_te, pred),
                "xgboost_test_r2": r2_score(y_te, pred),
                "ridge_test_mae": mean_absolute_error(y_te, ridge_pred),
                "ridge_test_r2": r2_score(y_te, ridge_pred),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Saved {MODELS_DIR / 'model1_iss_xgboost.pkl'}")


if __name__ == "__main__":
    train_iss_model()
