"""
Train connectivity anomaly model — 3 features match main.py detect_blackout ML branch.
"""

import joblib
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.metrics import roc_auc_score
from sklearn.preprocessing import StandardScaler

PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "trained"
CONNECTIVITY_CSV = PROJECT_ROOT / "outputs" / "datasets" / "connectivity_dataset.csv"
TEST_SIZE = 0.30

FEATURE_COLS = ["ookla_avg_speed", "device_pct_weak", "sustained_minutes"]


def train_blackout_models():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    print("Training Model 5 — Blackout (IsolationForest + scaler)")

    if not CONNECTIVITY_CSV.is_file():
        raise FileNotFoundError(f"Missing dataset: {CONNECTIVITY_CSV}")

    df = pd.read_csv(CONNECTIVITY_CSV)
    for c in FEATURE_COLS + ["is_blackout"]:
        if c not in df.columns:
            raise ValueError(f"connectivity_dataset.csv missing column: {c}")

    X = df[FEATURE_COLS].astype(float).values
    y = df["is_blackout"].astype(int).values
    n = len(df)
    pos_rate = float(df["is_blackout"].mean())
    contamination = float(np.clip(max(pos_rate, 0.02), 0.02, 0.15))

    split_idx = int(n * (1.0 - TEST_SIZE))
    X_tr, X_te = X[:split_idx], X[split_idx:]
    y_tr, y_te = y[:split_idx], y[split_idx:]

    scaler = StandardScaler()
    X_tr_scaled = scaler.fit_transform(X_tr)
    X_te_scaled = scaler.transform(X_te)

    iso = IsolationForest(
        n_estimators=200,
        contamination=contamination,
        max_features=1.0,
        random_state=42,
    )
    iso.fit(X_tr_scaled)

    train_auc = roc_auc_score(y_tr, -iso.decision_function(X_tr_scaled))
    test_auc = roc_auc_score(y_te, -iso.decision_function(X_te_scaled))
    print(f"Train ROC-AUC (blackout): {train_auc:.4f}")
    print(f"Test ROC-AUC (blackout):  {test_auc:.4f}")

    joblib.dump(iso, MODELS_DIR / "model5_iso_connectivity.pkl")
    joblib.dump(scaler, MODELS_DIR / "model5_scaler.pkl")
    joblib.dump(
        {
            "ookla_mbps_lt": 2.0,
            "device_weak_ge": 0.30,
            "sustained_min_ge": 20,
            "feature_cols": FEATURE_COLS,
            "train_rows": n,
            "blackout_rate": pos_rate,
            "test_auc": round(float(test_auc), 4),
        },
        MODELS_DIR / "model5_thresholds.pkl",
    )
    print(f"Saved blackout artifacts to {MODELS_DIR}")


if __name__ == "__main__":
    train_blackout_models()
