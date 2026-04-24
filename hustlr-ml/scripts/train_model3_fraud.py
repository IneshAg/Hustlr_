"""
Train fraud stack from claims_fraud.csv (zone-level Chennai claims ledger).
No synthetic RNG rows — labels and telemetry come from the dataset.
"""

import joblib
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    fbeta_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

from model_data_utils import grouped_train_test_indices

PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "trained"
CLAIMS_CSV = PROJECT_ROOT / "outputs" / "datasets" / "claims_fraud.csv"
TEST_SIZE = 0.30

IF_FEATURES = [
    "gps_zone_mismatch",
    "wifi_home_ssid",
    "battery_charging",
    "accelerometer_idle",
    "platform_app_inactive",
    "ip_home_match",
    "claim_latency_under30s",
    "gps_jitter_perfect",
    "barometer_mismatch",
    "hw_fingerprint_match",
    "app_install_cluster",
    "days_since_onboard",
    "referral_depth",
    "claim_hour_sin",
    "claim_hour_cos",
    "city_behavioral_risk",
    "zone_depth_score",
    "has_real_disruption",
    "simultaneous_zone_claims",
    "iss_score",
]

CITY_RISK_MAP = {
    "chennai": 0.65,
    "mumbai": 0.50,
    "bengaluru": 0.55,
    "bangalore": 0.55,
    "kolkata": 0.45,
}


def augment_fraud_frame(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    if "claim_hour" not in out.columns:
        out["claim_hour"] = 12
    claim_hour = pd.to_numeric(out["claim_hour"], errors="coerce").fillna(12).clip(lower=0, upper=23)
    radians = 2.0 * np.pi * claim_hour / 24.0
    out["claim_hour_sin"] = np.sin(radians)
    out["claim_hour_cos"] = np.cos(radians)
    out["city_behavioral_risk"] = (
        out.get("city", pd.Series("Chennai", index=out.index))
        .astype(str)
        .str.strip()
        .str.lower()
        .map(CITY_RISK_MAP)
        .fillna(0.55)
    )
    return out


def prepare_fraud_features(df: pd.DataFrame) -> pd.DataFrame:
    feat = augment_fraud_frame(df)[IF_FEATURES].astype(float).copy()

    # Compress the strongest label-proxy columns so the classifier has to rely
    # more on interaction patterns than on a couple of nearly deterministic cuts.
    feat["days_since_onboard"] = np.log1p(feat["days_since_onboard"].clip(lower=7, upper=365))
    feat["simultaneous_zone_claims"] = np.log1p(
        feat["simultaneous_zone_claims"].clip(lower=0, upper=12)
    )
    feat["referral_depth"] = np.log1p(feat["referral_depth"].clip(lower=0, upper=8))
    feat["zone_depth_score"] = feat["zone_depth_score"].clip(lower=0.05, upper=0.95)
    feat["iss_score"] = feat["iss_score"].clip(lower=10, upper=95)
    return feat


def calibrate_probabilities(calibrator: LogisticRegression, raw_prob: np.ndarray) -> np.ndarray:
    raw_prob = np.asarray(raw_prob, dtype=float).reshape(-1, 1)
    return calibrator.predict_proba(raw_prob)[:, 1]


def train_fraud_model():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    print("Training Model 3 — Fraud (from claims_fraud.csv)")

    if not CLAIMS_CSV.is_file():
        raise FileNotFoundError(f"Missing dataset: {CLAIMS_CSV}")

    df = augment_fraud_frame(pd.read_csv(CLAIMS_CSV))
    for c in IF_FEATURES + ["is_fraud"]:
        if c not in df.columns:
            raise ValueError(f"claims_fraud.csv missing column: {c}")

    X = prepare_fraud_features(df).values
    y = df["is_fraud"].astype(int).values
    groups = df["worker_id"].astype(str)

    if "worker_id" not in df.columns:
        raise ValueError("claims_fraud.csv must include worker_id for leakage-safe splitting")

    train_idx, test_idx = grouped_train_test_indices(
        groups,
        test_size=TEST_SIZE,
        random_state=42,
    )
    X_tr, X_te = X[train_idx], X[test_idx]
    y_tr, y_te = y[train_idx], y[test_idx]
    groups_tr = groups.iloc[train_idx]

    scaler = StandardScaler()
    fraud_rate = float(np.mean(y_tr))
    contamination = float(np.clip(max(fraud_rate, 0.02), 0.02, 0.2))
    scale_pos_weight = float(max((len(y_tr) - y_tr.sum()) / max(y_tr.sum(), 1), 1.0))

    inner_train_idx, val_idx = grouped_train_test_indices(
        groups_tr,
        test_size=0.20,
        random_state=43,
    )

    X_fit = X_tr[inner_train_idx]
    y_fit = y_tr[inner_train_idx]
    X_val = X_tr[val_idx]
    y_val = y_tr[val_idx]

    scaler = StandardScaler()
    X_fit_s = scaler.fit_transform(X_fit)
    X_val_s = scaler.transform(X_val)
    X_tr_s = scaler.transform(X_tr)
    X_te_s = scaler.transform(X_te)

    iso = IsolationForest(
        n_estimators=200,
        contamination=contamination,
        max_features=0.75,
        random_state=42,
    )
    iso.fit(X_tr_s)

    xgb_clf = XGBClassifier(
        n_estimators=320,
        max_depth=4,
        learning_rate=0.04,
        subsample=0.85,
        colsample_bytree=0.85,
        scale_pos_weight=scale_pos_weight,
        random_state=42,
        tree_method="hist",
        n_jobs=-1,
        device="cpu",
    )
    xgb_clf.fit(X_fit_s, y_fit)

    val_prob_raw = xgb_clf.predict_proba(X_val_s)[:, 1]
    calibrator = LogisticRegression(solver="lbfgs", max_iter=500)
    calibrator.fit(val_prob_raw.reshape(-1, 1), y_val)
    val_prob = calibrate_probabilities(calibrator, val_prob_raw)

    business_tp_gain = 6.0
    business_fp_cost = 1.5
    business_fn_cost = 8.0
    best_threshold = 0.50
    best_utility = float("-inf")
    best_stats = {"precision": 0.0, "recall": 0.0, "f2": 0.0}
    fallback_threshold = 0.50
    fallback_f2 = float("-inf")
    val_frame = df.iloc[train_idx].iloc[val_idx].copy()
    val_frame["y_true"] = y_val
    val_frame["city"] = val_frame.get("city", "unknown").astype(str).fillna("unknown")
    val_frame["tenure_bucket"] = pd.cut(
        pd.to_numeric(val_frame["days_since_onboard"], errors="coerce").fillna(0),
        bins=[-1, 30, 90, 180, 3660],
        labels=["new_0_30d", "ramp_31_90d", "active_91_180d", "tenured_181d_plus"],
    ).astype("string").fillna("unknown")
    for threshold in np.arange(0.18, 0.72, 0.02):
        pred = (val_prob >= threshold).astype(int)
        prec = precision_score(y_val, pred, zero_division=0)
        rec = recall_score(y_val, pred, zero_division=0)
        f2 = fbeta_score(y_val, pred, beta=2, zero_division=0)
        val_frame["pred"] = pred
        city_recalls = []
        for city_name, part in val_frame.groupby("city", sort=False):
            if int(part["y_true"].sum()) <= 0:
                continue
            city_recalls.append(recall_score(part["y_true"], part["pred"], zero_division=0))
        tenure_recalls = []
        for bucket, part in val_frame.groupby("tenure_bucket", sort=False):
            if int(part["y_true"].sum()) <= 0:
                continue
            tenure_recalls.append(recall_score(part["y_true"], part["pred"], zero_division=0))
        min_city_recall = min(city_recalls) if city_recalls else 0.0
        min_tenure_recall = min(tenure_recalls) if tenure_recalls else 0.0
        if f2 > fallback_f2:
            fallback_f2 = f2
            fallback_threshold = float(round(threshold, 2))
        tp = float(((pred == 1) & (y_val == 1)).sum())
        fp = float(((pred == 1) & (y_val == 0)).sum())
        fn = float(((pred == 0) & (y_val == 1)).sum())
        utility = tp * business_tp_gain - fp * business_fp_cost - fn * business_fn_cost
        utility += 120.0 * min_city_recall + 80.0 * min_tenure_recall + 35.0 * rec
        if (
            rec >= 0.50
            and prec >= 0.20
            and min_city_recall >= 0.20
            and (utility > best_utility or (utility == best_utility and f2 > best_stats["f2"]))
        ):
            best_threshold = float(round(threshold, 2))
            best_utility = utility
            best_stats = {
                "precision": prec,
                "recall": rec,
                "f2": f2,
                "min_city_recall": min_city_recall,
                "min_tenure_recall": min_tenure_recall,
            }

    if best_utility == float("-inf"):
        best_threshold = fallback_threshold
        pred = (val_prob >= best_threshold).astype(int)
        prec = precision_score(y_val, pred, zero_division=0)
        rec = recall_score(y_val, pred, zero_division=0)
        f2 = fbeta_score(y_val, pred, beta=2, zero_division=0)
        tp = float(((pred == 1) & (y_val == 1)).sum())
        fp = float(((pred == 1) & (y_val == 0)).sum())
        fn = float(((pred == 0) & (y_val == 1)).sum())
        best_utility = tp * business_tp_gain - fp * business_fp_cost - fn * business_fn_cost
        best_stats = {
            "precision": prec,
            "recall": rec,
            "f2": f2,
            "min_city_recall": 0.0,
            "min_tenure_recall": 0.0,
        }

    xgb_clf.fit(X_tr_s, y_tr)

    train_prob_raw = xgb_clf.predict_proba(X_tr_s)[:, 1]
    test_prob_raw = xgb_clf.predict_proba(X_te_s)[:, 1]
    train_prob = calibrate_probabilities(calibrator, train_prob_raw)
    test_prob = calibrate_probabilities(calibrator, test_prob_raw)
    train_auc = roc_auc_score(y_tr, train_prob)
    test_auc = roc_auc_score(y_te, test_prob)
    train_pr_auc = average_precision_score(y_tr, train_prob)
    test_pr_auc = average_precision_score(y_te, test_prob)
    train_pred = (train_prob >= best_threshold).astype(int)
    test_pred = (test_prob >= best_threshold).astype(int)
    train_rec = recall_score(y_tr, train_pred, zero_division=0)
    test_rec = recall_score(y_te, test_pred, zero_division=0)
    train_prec = precision_score(y_tr, train_pred, zero_division=0)
    test_prec = precision_score(y_te, test_pred, zero_division=0)
    train_brier = brier_score_loss(y_tr, train_prob)
    test_brier = brier_score_loss(y_te, test_prob)
    print(f"Train AUC: {train_auc:.4f}")
    print(f"Test AUC:  {test_auc:.4f}")
    print(f"Train PR-AUC: {train_pr_auc:.4f}")
    print(f"Test PR-AUC:  {test_pr_auc:.4f}")
    print(f"Decision threshold: {best_threshold:.2f}")
    print(f"Train recall/precision: {train_rec:.1%} / {train_prec:.1%}")
    print(f"Test recall/precision:  {test_rec:.1%} / {test_prec:.1%}")
    print(f"Train/Test Brier: {train_brier:.4f} / {test_brier:.4f}")
    print(
        f"Rows: {len(df)} | workers: {df['worker_id'].nunique()} | "
        f"zones: {df['zone'].nunique()} | fraud rate: {fraud_rate:.3f}"
    )

    joblib.dump(iso, MODELS_DIR / "model3_isolation_forest.pkl")
    xgb_clf.save_model(MODELS_DIR / "model3_fraud_classifier.json")
    joblib.dump(scaler, MODELS_DIR / "model3_scaler.pkl")
    joblib.dump(IF_FEATURES, MODELS_DIR / "model3_features.pkl")
    joblib.dump(calibrator, MODELS_DIR / "model3_probability_calibrator.pkl")
    joblib.dump(
        {
            "threshold": best_threshold,
            "scale_pos_weight": scale_pos_weight,
            "test_size": TEST_SIZE,
            "business_tp_gain": business_tp_gain,
            "business_fp_cost": business_fp_cost,
            "business_fn_cost": business_fn_cost,
            "validation_precision": best_stats["precision"],
            "validation_recall": best_stats["recall"],
            "validation_f2": best_stats["f2"],
            "validation_min_city_recall": best_stats["min_city_recall"],
            "validation_min_tenure_recall": best_stats["min_tenure_recall"],
            "validation_utility": best_utility,
        },
        MODELS_DIR / "model3_thresholds.pkl",
    )
    print("Saved fraud models successfully.")


if __name__ == "__main__":
    train_fraud_model()
