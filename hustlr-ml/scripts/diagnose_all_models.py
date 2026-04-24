"""
diagnose_all_models.py
======================
Evaluates ALL trained models with proper train/test splits and reports
precise metrics for each.

Models covered:
  Model 1  — ISS XGBoost Regressor
  Model 3  — Fraud Isolation Forest + XGBoost Classifier
  Model 4  — NLP Disruption Event Classifier
  Model 7  — Prophet Disruption Forecaster (per-zone backtesting)

Run from hustlr-ml/:
    python -X utf8 scripts/diagnose_all_models.py
"""

import warnings
warnings.filterwarnings("ignore")

import sys, os
os.environ.setdefault("PYTHONIOENCODING", "utf-8")

import joblib
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import (
    brier_score_loss,
    precision_score,
    recall_score,
    mean_absolute_error, r2_score,
    roc_auc_score, average_precision_score,
    classification_report, confusion_matrix, accuracy_score,
)

from model_data_utils import (
    cap_group_rows,
    grouped_train_test_indices,
    month_groups,
    template_text_groups,
)
from train_model3_fraud import augment_fraud_frame, prepare_fraud_features
from train_model7_prophet import (
    REGRESSORS as PROPHET_REGRESSORS,
    add_event_calendar_features,
    build_prophet_frame,
    enrich_with_real_aqi,
    enrich_with_real_precipitation,
)

# ── Paths ──────────────────────────────────────────────────────────────────
ML_DIR      = Path(__file__).parent.parent
MODELS_DIR  = ML_DIR / "models" / "trained"
DATA_DIR    = ML_DIR / "outputs" / "datasets"
RANDOM_STATE = 42
TEST_SIZE = 0.30

SEP = "=" * 70

def header(title):
    print(f"\n{SEP}")
    print(f"  {title}")
    print(SEP)


def expected_calibration_error(y_true, y_prob, bins: int = 10) -> float:
    y_true = np.asarray(y_true)
    y_prob = np.asarray(y_prob)
    edges = np.linspace(0.0, 1.0, bins + 1)
    ece = 0.0
    for lo, hi in zip(edges[:-1], edges[1:]):
        mask = (y_prob >= lo) & (y_prob < hi if hi < 1.0 else y_prob <= hi)
        if not mask.any():
            continue
        acc = y_true[mask].mean()
        conf = y_prob[mask].mean()
        ece += (mask.mean()) * abs(acc - conf)
    return float(ece)

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 1 — ISS XGBoost Regressor
# ══════════════════════════════════════════════════════════════════════════════
header("MODEL 1 — ISS XGBoost Regressor (worker_profiles.csv)")

ISS_FEATURES = joblib.load(MODELS_DIR / "model1_features.pkl")
iss_model    = joblib.load(MODELS_DIR / "model1_iss_xgboost.pkl")

df_iss = pd.read_csv(DATA_DIR / "worker_profiles.csv")
print(f"Dataset: {len(df_iss):,} rows | {df_iss['zone'].nunique()} zones")
print(f"Features: {ISS_FEATURES}")

X_iss = df_iss[ISS_FEATURES].astype(float).values
y_iss = df_iss["iss_score"].astype(float).clip(0, 100).values

iss_train_idx, iss_test_idx = grouped_train_test_indices(
    month_groups(df_iss["onboard_date"]),
    test_size=TEST_SIZE,
    random_state=RANDOM_STATE,
)
X_tr, X_te = X_iss[iss_train_idx], X_iss[iss_test_idx]
y_tr, y_te = y_iss[iss_train_idx], y_iss[iss_test_idx]

pred_tr = np.clip(iss_model.predict(X_tr), 0, 100)
pred_te = np.clip(iss_model.predict(X_te), 0, 100)

mae_tr  = mean_absolute_error(y_tr, pred_tr)
mae_te  = mean_absolute_error(y_te, pred_te)
r2_tr   = r2_score(y_tr, pred_tr)
r2_te   = r2_score(y_te, pred_te)

print(f"\n{'Metric':<20} {'Train':>12} {'Test':>12}  {'Gap':>10}")
print("-" * 56)
print(f"{'MAE (points)':<20} {mae_tr:>12.3f} {mae_te:>12.3f}  {abs(mae_tr-mae_te):>10.3f}")
print(f"{'R-squared':<20} {r2_tr:>12.4f} {r2_te:>12.4f}  {abs(r2_tr-r2_te):>10.4f}")
print(f"{'Samples':<20} {len(X_tr):>12,} {len(X_te):>12,}")

# Score distribution
for split, preds, actuals in [("TRAIN", pred_tr, y_tr), ("TEST", pred_te, y_te)]:
    print(f"\n  {split} prediction distribution:")
    for lo, hi, label in [(0,30,"RED (<30)"), (30,50,"AMBER_LOW"), (50,70,"AMBER"), (70,100,"GREEN (>=70)")]:
        n = ((preds >= lo) & (preds < hi)).sum()
        print(f"    {label:<18}: predicted={n:>5}  actual={((actuals>=lo)&(actuals<hi)).sum():>5}")

if r2_te > 0.85:
    note = "Excellent — model captures ISS score variance well"
elif r2_te > 0.65:
    note = "Acceptable — some variance unaccounted for"
else:
    note = "WARNING: poor fit — check feature alignment"
print(f"\n  Verdict: {note}")

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 3 — Fraud Detection (Isolation Forest + XGBoost Classifier)
# ══════════════════════════════════════════════════════════════════════════════
header("MODEL 3 — Fraud Detection (claims_fraud.csv)")

IF_FEATURES = joblib.load(MODELS_DIR / "model3_features.pkl")
iso_model   = joblib.load(MODELS_DIR / "model3_isolation_forest.pkl")
scaler      = joblib.load(MODELS_DIR / "model3_scaler.pkl")
prob_calibrator = None
try:
    prob_calibrator = joblib.load(MODELS_DIR / "model3_probability_calibrator.pkl")
except Exception:
    prob_calibrator = None

from xgboost import XGBClassifier
xgb_fraud = XGBClassifier()
xgb_fraud.load_model(MODELS_DIR / "model3_fraud_classifier.json")

df_fraud = augment_fraud_frame(pd.read_csv(DATA_DIR / "claims_fraud.csv"))
print(f"Dataset: {len(df_fraud):,} rows | fraud rate: {df_fraud['is_fraud'].mean():.3f} | {df_fraud['zone'].nunique()} zones")

X_f  = prepare_fraud_features(df_fraud).values
y_f  = df_fraud["is_fraud"].astype(int).values

fraud_train_idx, fraud_test_idx = grouped_train_test_indices(
    df_fraud["worker_id"].astype(str),
    test_size=TEST_SIZE,
    random_state=RANDOM_STATE,
)
X_ftr, X_fte = X_f[fraud_train_idx], X_f[fraud_test_idx]
y_ftr, y_fte = y_f[fraud_train_idx], y_f[fraud_test_idx]

X_ftr_s = scaler.transform(X_ftr)
X_fte_s = scaler.transform(X_fte)

# -- XGBoost Classifier (supervised)
prob_tr_raw = xgb_fraud.predict_proba(X_ftr_s)[:, 1]
prob_te_raw = xgb_fraud.predict_proba(X_fte_s)[:, 1]
if prob_calibrator is not None:
    prob_tr = prob_calibrator.predict_proba(prob_tr_raw.reshape(-1, 1))[:, 1]
    prob_te = prob_calibrator.predict_proba(prob_te_raw.reshape(-1, 1))[:, 1]
else:
    prob_tr = prob_tr_raw
    prob_te = prob_te_raw

auc_tr = roc_auc_score(y_ftr, prob_tr)
auc_te = roc_auc_score(y_fte, prob_te)
ap_tr  = average_precision_score(y_ftr, prob_tr)
ap_te  = average_precision_score(y_fte, prob_te)
brier_tr = brier_score_loss(y_ftr, prob_tr)
brier_te = brier_score_loss(y_fte, prob_te)
ece_tr = expected_calibration_error(y_ftr, prob_tr)
ece_te = expected_calibration_error(y_fte, prob_te)

try:
    fraud_threshold = float(joblib.load(MODELS_DIR / "model3_thresholds.pkl")["threshold"])
except Exception:
    fraud_threshold = 0.5
pred_tr_xgb = (prob_tr >= fraud_threshold).astype(int)
pred_te_xgb = (prob_te >= fraud_threshold).astype(int)

cm_tr = confusion_matrix(y_ftr, pred_tr_xgb)
cm_te = confusion_matrix(y_fte, pred_te_xgb)

def cm_stats(cm):
    tn, fp, fn, tp = cm.ravel()
    rec = tp/(tp+fn) if (tp+fn) > 0 else 0
    prec = tp/(tp+fp) if (tp+fp) > 0 else 0
    f1 = 2*rec*prec/(rec+prec) if (rec+prec) > 0 else 0
    return tn, fp, fn, tp, rec, prec, f1

tn_tr, fp_tr, fn_tr, tp_tr, rec_tr, prec_tr, f1_tr = cm_stats(cm_tr)
tn_te, fp_te, fn_te, tp_te, rec_te, prec_te, f1_te = cm_stats(cm_te)

print(f"\n  XGBoost Fraud Classifier:")
print(f"  {'Metric':<22} {'Train':>10} {'Test':>10}  {'Gap':>8}")
print("  " + "-" * 52)
print(f"  {'ROC-AUC':<22} {auc_tr:>10.4f} {auc_te:>10.4f}  {abs(auc_tr-auc_te):>8.4f}")
print(f"  {'PR-AUC':<22} {ap_tr:>10.4f} {ap_te:>10.4f}  {abs(ap_tr-ap_te):>8.4f}")
print(f"  {'Brier score':<22} {brier_tr:>10.4f} {brier_te:>10.4f}")
print(f"  {'ECE (10 bins)':<22} {ece_tr:>10.4f} {ece_te:>10.4f}")
print(f"  {'Recall (fraud)':<22} {rec_tr:>10.1%} {rec_te:>10.1%}")
print(f"  {'Precision (fraud)':<22} {prec_tr:>10.1%} {prec_te:>10.1%}")
print(f"  {'F1 (fraud)':<22} {f1_tr:>10.4f} {f1_te:>10.4f}")
print(f"  {'TN/FP/FN/TP (train)':<22} {tn_tr}/{fp_tr}/{fn_tr}/{tp_tr}")
print(f"  {'TN/FP/FN/TP (test)':<22}            {tn_te}/{fp_te}/{fn_te}/{tp_te}")

print("\n  Test recall by tenure cohort:")
tenure_days = pd.to_numeric(df_fraud.iloc[fraud_test_idx]["days_since_onboard"], errors="coerce").fillna(0)
tenure_bins = pd.cut(
    tenure_days,
    bins=[-1, 30, 90, 180, 3660],
    labels=["new_0_30d", "ramp_31_90d", "active_91_180d", "tenured_181d_plus"],
)
for cohort in tenure_bins.astype("string").fillna("unknown").unique():
    mask = tenure_bins.astype("string").fillna("unknown") == cohort
    if mask.sum() == 0 or y_fte[mask].sum() == 0:
        continue
    cohort_rec = recall_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
    cohort_prec = precision_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
    print(f"    {cohort:<18} recall={cohort_rec:>6.1%} precision={cohort_prec:>6.1%} samples={int(mask.sum()):>5}")

if "claim_date" in df_fraud.columns:
    print("\n  Test recall by claim month:")
    claim_month = pd.to_datetime(df_fraud.iloc[fraud_test_idx]["claim_date"], errors="coerce").dt.to_period("M").astype("string")
    for month in sorted(claim_month.dropna().unique()):
        mask = claim_month == month
        if mask.sum() == 0 or y_fte[mask].sum() == 0:
            continue
        month_rec = recall_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
        month_prec = precision_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
        print(f"    {month:<10} recall={month_rec:>6.1%} precision={month_prec:>6.1%} samples={int(mask.sum()):>5}")

if "city" in df_fraud.columns:
    print("\n  Test recall by city:")
    test_city = df_fraud.iloc[fraud_test_idx]["city"].astype(str).fillna("unknown")
    for city_name in sorted(test_city.unique()):
        mask = test_city == city_name
        if mask.sum() == 0 or y_fte[mask].sum() == 0:
            continue
        city_rec = recall_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
        city_prec = precision_score(y_fte[mask], pred_te_xgb[mask], zero_division=0)
        print(f"    {city_name:<12} recall={city_rec:>6.1%} precision={city_prec:>6.1%} samples={int(mask.sum()):>5}")

for feature in ["days_since_onboard", "simultaneous_zone_claims", "zone_depth_score", "iss_score"]:
    if feature not in df_fraud.columns:
        continue
    train_mean = pd.to_numeric(df_fraud.iloc[fraud_train_idx][feature], errors="coerce").mean()
    test_mean = pd.to_numeric(df_fraud.iloc[fraud_test_idx][feature], errors="coerce").mean()
    print(f"  Drift check {feature:<24} train={train_mean:>8.3f} test={test_mean:>8.3f} delta={abs(train_mean-test_mean):>7.3f}")

# -- Isolation Forest (unsupervised — evaluate against labels for reference)
iso_scores_tr = -iso_model.decision_function(X_ftr_s)  # higher = more anomalous
iso_scores_te = -iso_model.decision_function(X_fte_s)

iso_auc_tr = roc_auc_score(y_ftr, iso_scores_tr)
iso_auc_te = roc_auc_score(y_fte, iso_scores_te)

print(f"\n  Isolation Forest (unsupervised — AUC only, no threshold required):")
print(f"  {'ROC-AUC train':<22}: {iso_auc_tr:.4f}")
print(f"  {'ROC-AUC test':<22}: {iso_auc_te:.4f}")
print(f"  {'Gap':<22}: {abs(iso_auc_tr-iso_auc_te):.4f}")

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 4 — NLP Disruption Event Classifier
# ══════════════════════════════════════════════════════════════════════════════
header("MODEL 4 — NLP Disruption Classifier (nlp_disruption_events.csv)")

try:
    from xgboost import XGBClassifier as XGB4
    from sklearn.feature_extraction.text import TfidfVectorizer

    tfidf     = joblib.load(MODELS_DIR / "model4_tfidf.pkl")
    label_map = joblib.load(MODELS_DIR / "model4_label_map.pkl")
    nlp_clf   = XGB4()
    nlp_clf.load_model(MODELS_DIR / "model4_rf_nlp.json")

    df_nlp = pd.read_csv(DATA_DIR / "nlp_disruption_events.csv")
    text_col = "raw_text"
    label_col = "trigger_label"
    
    print(f"Dataset: {len(df_nlp):,} rows | {df_nlp[label_col].nunique()} classes")
    print(f"Classes: {sorted(df_nlp[label_col].unique())}")

    df_nlp = df_nlp.dropna(subset=[text_col, label_col])
    df_nlp[text_col] = df_nlp[text_col].astype(str).str.strip()
    df_nlp = df_nlp[df_nlp[text_col].str.len() > 0].copy()
    df_nlp["text_group"] = template_text_groups(df_nlp[text_col], df_nlp["zone"].dropna().unique())
    df_nlp = cap_group_rows(df_nlp, "text_group", max_rows_per_group=3, random_state=RANDOM_STATE)

    X_nlp = tfidf.transform(df_nlp[text_col])
    y_nlp = df_nlp[label_col].map(label_map).fillna(-1).astype(int)
    valid  = y_nlp >= 0
    X_nlp = X_nlp[valid.values]
    y_nlp = y_nlp[valid].values
    groups = df_nlp.loc[valid.values, "text_group"]
    nlp_train_idx, nlp_test_idx = grouped_train_test_indices(
        groups,
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
    )
    X_ntr, X_nte = X_nlp[nlp_train_idx], X_nlp[nlp_test_idx]
    y_ntr, y_nte = y_nlp[nlp_train_idx], y_nlp[nlp_test_idx]

    acc_tr = (nlp_clf.predict(X_ntr) == y_ntr).mean()
    acc_te = (nlp_clf.predict(X_nte) == y_nte).mean()

    print(f"\n  {'Metric':<22} {'Train':>10} {'Test':>10}  {'Gap':>8}")
    print("  " + "-" * 52)
    print(f"  {'Accuracy':<22} {acc_tr:>10.4f} {acc_te:>10.4f}  {abs(acc_tr-acc_te):>8.4f}")
    print(f"  {'Samples':<22} {X_ntr.shape[0]:>10,} {X_nte.shape[0]:>10,}")
    rev_map = {v: k for k, v in label_map.items()}
    target_names = [rev_map[i] for i in sorted(rev_map)]
    print("\n  Test classification report:")
    print(classification_report(y_nte, nlp_clf.predict(X_nte), target_names=target_names, zero_division=0))

    if abs(acc_tr - acc_te) > 0.08:
        print("  WARNING: Train-test gap > 8% — possible overfitting or class imbalance")
    else:
        print("  Generalisation: stable")

except Exception as e:
    print(f"  SKIP — {e}")

# MODEL 5 — Blackout
header("MODEL 5 — Blackout Detection (connectivity_dataset.csv)")
try:
    from sklearn.metrics import roc_auc_score
    df_b = pd.read_csv(DATA_DIR / "connectivity_dataset.csv")
    feat_b = ["ookla_avg_speed", "device_pct_weak", "sustained_minutes"]
    y_b = df_b["is_blackout"].astype(int).values
    split_idx = int(len(df_b) * 0.7)
    X_btr = df_b.iloc[:split_idx][feat_b].astype(float).values
    X_bte = df_b.iloc[split_idx:][feat_b].astype(float).values
    y_btr = y_b[:split_idx]
    y_bte = y_b[split_idx:]
    scaler_b = joblib.load(MODELS_DIR / "model5_scaler.pkl")
    iso_b = joblib.load(MODELS_DIR / "model5_iso_connectivity.pkl")
    auc_btr = roc_auc_score(y_btr, -iso_b.decision_function(scaler_b.transform(X_btr)))
    auc_bte = roc_auc_score(y_bte, -iso_b.decision_function(scaler_b.transform(X_bte)))
    print(f"  ROC-AUC train: {auc_btr:.4f}")
    print(f"  ROC-AUC test : {auc_bte:.4f}")
except Exception as e:
    print(f"  SKIP — {e}")

# MODEL 6 — Traffic
header("MODEL 6 — Traffic Classifier (traffic_accidents.csv)")
try:
    from xgboost import XGBClassifier as XGB6
    df_t = pd.read_csv(DATA_DIR / "traffic_accidents.csv")
    feat_t = ["congestion_probability","speed_pct_drop","accident_duration_min","news_confidence","is_peak_hour","is_weekend"]
    split_idx = int(len(df_t) * 0.7)
    X_ttr = df_t.iloc[:split_idx][feat_t].astype(float).values
    X_tte = df_t.iloc[split_idx:][feat_t].astype(float).values
    le_t = joblib.load(MODELS_DIR / "model6_label_encoder.pkl")
    y_t = le_t.transform(df_t["blockspot_classification"].astype(str))
    y_ttr = y_t[:split_idx]
    y_tte = y_t[split_idx:]
    clf_t = XGB6()
    clf_t.load_model(MODELS_DIR / "model6_traffic_classifier.json")
    pred_ttr = clf_t.predict(X_ttr)
    pred_tte = clf_t.predict(X_tte)
    print(f"  Accuracy train: {accuracy_score(y_ttr, pred_ttr):.4f}")
    print(f"  Accuracy test : {accuracy_score(y_tte, pred_tte):.4f}")
    print("\n  Test classification report:")
    print(classification_report(y_tte, pred_tte, target_names=le_t.classes_, zero_division=0))
except Exception as e:
    print(f"  SKIP — {e}")

# ══════════════════════════════════════════════════════════════════════════════
# MODEL 7 — Prophet Forecaster (backtesting: hold out last 20% of time)
# ══════════════════════════════════════════════════════════════════════════════
header("MODEL 7 — Prophet Disruption Forecaster (prophet_training.csv)")
print("  Backtest: rolling temporal windows with the same regressors used in training")
print("  Metrics: MAE, MAPE, 80% Coverage Interval Hit Rate")

try:
    df_pr = pd.read_csv(DATA_DIR / "prophet_training.csv")
    df_pr["ds"] = pd.to_datetime(df_pr["ds"])
    df_pr = enrich_with_real_aqi(df_pr)
    df_pr = enrich_with_real_precipitation(df_pr)
    df_pr = add_event_calendar_features(df_pr)

    if "zone" in df_pr.columns and "city_type" not in df_pr.columns:
        df_pr["city_type"] = df_pr["zone"]
    elif "zone_id" in df_pr.columns and "city_type" not in df_pr.columns:
        df_pr["city_type"] = df_pr["zone_id"]

    print(f"\n  {'City':<16} {'Zones':>6} {'Windows':>8} {'Avg MAE':>10} {'Avg MAPE':>10} {'Coverage':>10}")
    print("  " + "-" * 76)

    if "zone_id" not in df_pr.columns:
        print("  prophet_training.csv has no zone_id column; zone-wise backtest skipped")
    else:
        zone_city = (
            df_pr[["zone_id", "city_type"]]
            .dropna()
            .drop_duplicates()
            .assign(zone_id=lambda x: x["zone_id"].astype(str), city_type=lambda x: x["city_type"].astype(str))
        )
        for city_type in sorted(zone_city["city_type"].unique()):
            city_zones = sorted(zone_city.loc[zone_city["city_type"] == city_type, "zone_id"].unique())[:8]
            all_mae = []
            all_mape = []
            all_cov = []
            windows = 0
            for zone_id in city_zones:
                pkl = MODELS_DIR / f"model7_prophet_{zone_id.lower()}.pkl"
                if not pkl.exists():
                    continue
                sub = df_pr[df_pr["zone_id"].astype(str) == zone_id].copy()
                sub = build_prophet_frame(sub)
                if len(sub) < 240:
                    continue
                model = joblib.load(pkl)
                window = max(48, int(len(sub) * 0.10))
                starts = [int(len(sub) * 0.60), int(len(sub) * 0.70), int(len(sub) * 0.80)]
                for start in starts:
                    test_df = sub.iloc[start:min(start + window, len(sub))].copy()
                    if len(test_df) < 24:
                        continue
                    feature_df = test_df[["ds"] + [r for r in PROPHET_REGRESSORS if r in test_df.columns]].copy()
                    forecast = model.predict(feature_df)
                    y_true = test_df["y"].values
                    y_pred = forecast["yhat"].values
                    y_lo = forecast["yhat_lower"].values
                    y_hi = forecast["yhat_upper"].values
                    all_mae.append(mean_absolute_error(y_true, y_pred))
                    all_mape.append(np.mean(np.abs((y_true - y_pred) / (np.abs(y_true) + 1e-6))) * 100)
                    all_cov.append(np.mean((y_true >= y_lo) & (y_true <= y_hi)) * 100)
                    windows += 1
            if not all_mae:
                print(f"  {city_type:<16} -- no usable zone models found")
                continue
            print(
                f"  {city_type:<16} {len(city_zones):>6} {windows:>8} {np.mean(all_mae):>10.3f} "
                f"{np.mean(all_mape):>9.1f}% {np.mean(all_cov):>9.1f}%"
            )

    print("""
  Interpretation:
    MAE      — mean absolute error in log(disruption_units)
    MAPE     — mean absolute % error (< 20% good, < 10% excellent)
    Coverage — % of actuals within the 80% confidence interval
               (should be ~75-85% for a well-calibrated Prophet)""")

except Exception as e:
    print(f"  SKIP — {e}")

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY TABLE
# ══════════════════════════════════════════════════════════════════════════════
header("ALL MODELS — SUMMARY")
print(f"""
  Model  Name                       Key Train Metric    Key Test Metric
  ------+---------------------------+------------------+------------------
  M1     ISS XGBoost Regressor       R2 / MAE (points)   R2 / MAE (points)
  M3a    Fraud XGBoost Classifier     ROC-AUC + Recall    ROC-AUC + Recall
  M3b    Isolation Forest             ROC-AUC (ref)       ROC-AUC (ref)
  M4     NLP Disruption Classifier    Accuracy            Accuracy
  M7     Prophet Zone Forecaster      (temporal backtest) MAE + Coverage
""")
print("See individual sections above for exact numbers.\n")
