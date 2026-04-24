"""
diagnose_model.py — Runs a proper train/test split evaluation on the
Isolation Forest fraud model and reports precision, recall, F1, ROC-AUC,
and a feature separability breakdown so we can see exactly where the
synthetic data is too noisy.

Run from hustlr-ml/:
    python scripts/diagnose_model.py
"""

import sys
import os
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.ensemble import IsolationForest
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    classification_report,
    roc_auc_score,
    confusion_matrix,
    precision_recall_curve,
    average_precision_score,
)

# ── Add parent dir so we can import fraud_model ──────────────────────────────
sys.path.insert(0, str(Path(__file__).parent.parent))
from fraud_model import (
    generate_training_data,
    prepare_features,
    CONTAMINATION_RATE,
    ANOMALY_THRESHOLD,
)

# ─────────────────────────────────────────────────────────────────────────────
# 1. Generate labelled data (we know which rows are fraud)
# ─────────────────────────────────────────────────────────────────────────────
print("=" * 70)
print("STEP 1 — Generating synthetic data")
print("=" * 70)

RANDOM_STATE = 42
N = 50_000
n_fraud = int(N * CONTAMINATION_RATE)
n_clean = N - n_fraud

rng = np.random.default_rng(RANDOM_STATE)

n_a = int(n_fraud * 0.4)
n_b = int(n_fraud * 0.3)
n_c = n_fraud - n_a - n_b

clean = {
    "claim_latency_seconds":            rng.uniform(30, 300, n_clean),
    "simultaneous_zone_claims":         rng.integers(1, 4, n_clean),
    "account_age_days":                 rng.integers(10, 365, n_clean),
    "historical_clean_claim_ratio":     rng.uniform(0.5, 1.0, n_clean),
    "shift_gap_count_today":            rng.integers(0, 2, n_clean),
    "device_shared_with_n_accounts":    np.ones(n_clean, dtype=int),
    "zone_depth_score":                 rng.uniform(0.4, 1.0, n_clean),
    "orders_completed_during_disruption": np.zeros(n_clean, dtype=int),
    "is_mock_location_ever":            np.zeros(n_clean, dtype=int),
    "poisson_p_value":                  rng.uniform(0.1, 1.0, n_clean),
    "label": 0,
}

fraud_a = {
    "claim_latency_seconds":            rng.uniform(0.1, 4.9, n_a),
    "simultaneous_zone_claims":         rng.integers(11, 40, n_a),
    "account_age_days":                 rng.integers(0, 5, n_a),
    "historical_clean_claim_ratio":     np.zeros(n_a),
    "shift_gap_count_today":            rng.integers(0, 3, n_a),
    "device_shared_with_n_accounts":    np.ones(n_a, dtype=int),
    "zone_depth_score":                 rng.uniform(0.0, 0.5, n_a),
    "orders_completed_during_disruption": np.zeros(n_a, dtype=int),
    "is_mock_location_ever":            np.zeros(n_a, dtype=int),
    "poisson_p_value":                  rng.uniform(0.0, 0.04, n_a),
    "label": 1,
}

fraud_b = {
    "claim_latency_seconds":            rng.uniform(10, 100, n_b),
    "simultaneous_zone_claims":         rng.integers(1, 5, n_b),
    "account_age_days":                 rng.integers(0, 60, n_b),
    "historical_clean_claim_ratio":     rng.uniform(0.0, 0.3, n_b),
    "shift_gap_count_today":            rng.integers(2, 6, n_b),
    "device_shared_with_n_accounts":    rng.integers(4, 12, n_b),
    "zone_depth_score":                 rng.uniform(0.1, 0.8, n_b),
    "orders_completed_during_disruption": np.zeros(n_b, dtype=int),
    "is_mock_location_ever":            rng.choice([0, 1], n_b, p=[0.2, 0.8]),
    "poisson_p_value":                  rng.uniform(0.05, 0.5, n_b),
    "label": 1,
}

fraud_c = {
    "claim_latency_seconds":            rng.uniform(50, 300, n_c),
    "simultaneous_zone_claims":         rng.integers(1, 3, n_c),
    "account_age_days":                 rng.integers(30, 300, n_c),
    "historical_clean_claim_ratio":     rng.uniform(0.5, 0.8, n_c),
    "shift_gap_count_today":            np.zeros(n_c, dtype=int),
    "device_shared_with_n_accounts":    np.ones(n_c, dtype=int),
    "zone_depth_score":                 rng.uniform(0.5, 1.0, n_c),
    "orders_completed_during_disruption": rng.integers(3, 8, n_c),
    "is_mock_location_ever":            np.zeros(n_c, dtype=int),
    "poisson_p_value":                  rng.uniform(0.1, 0.9, n_c),
    "label": 1,
}

df = pd.concat([
    pd.DataFrame(clean),
    pd.DataFrame(fraud_a),
    pd.DataFrame(fraud_b),
    pd.DataFrame(fraud_c),
], ignore_index=True).sample(frac=1, random_state=RANDOM_STATE).reset_index(drop=True)

feature_cols = [
    "claim_latency_seconds", "simultaneous_zone_claims", "account_age_days",
    "historical_clean_claim_ratio", "shift_gap_count_today",
    "device_shared_with_n_accounts", "zone_depth_score",
    "orders_completed_during_disruption", "is_mock_location_ever",
    "poisson_p_value",
]

X = df[feature_cols].values.astype(float)
y = df["label"].values  # 0 = clean, 1 = fraud

print(f"Total samples : {len(df):,}")
print(f"Clean         : {(y == 0).sum():,}  ({(y==0).mean()*100:.1f}%)")
print(f"Fraud         : {(y == 1).sum():,}  ({(y==1).mean()*100:.1f}%)")
print(f"  Pattern A   : {n_a:,}  ({n_a/len(df)*100:.1f}%)")
print(f"  Pattern B   : {n_b:,}  ({n_b/len(df)*100:.1f}%)")
print(f"  Pattern C   : {n_c:,}  ({n_c/len(df)*100:.1f}%)")

# ─────────────────────────────────────────────────────────────────────────────
# 2. Feature separability — do fraud/clean distributions actually differ?
# ─────────────────────────────────────────────────────────────────────────────
print()
print("=" * 70)
print("STEP 2 — Feature separability (mean clean vs mean fraud)")
print("         High overlap = model will struggle")
print("=" * 70)

df_clean = df[df.label == 0]
df_fraud = df[df.label == 1]

print(f"\n{'Feature':<42} {'Clean mean':>12} {'Fraud mean':>12} {'Overlap?':>10}")
print("-" * 78)
for col in feature_cols:
    cm = df_clean[col].mean()
    fm = df_fraud[col].mean()
    # Simple overlap heuristic: normalised diff < 0.2 = problematic
    spread = abs(cm - fm) / (df[col].std() + 1e-9)
    flag = "⚠️  LOW SEP" if spread < 0.5 else "✓"
    print(f"{col:<42} {cm:>12.3f} {fm:>12.3f} {flag:>10}")

# ─────────────────────────────────────────────────────────────────────────────
# 3. Train / test split + model evaluation
# ─────────────────────────────────────────────────────────────────────────────
print()
print("=" * 70)
print("STEP 3 — Train / Test split (80/20 stratified)")
print("=" * 70)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.20, random_state=RANDOM_STATE, stratify=y
)
print(f"Train: {len(X_train):,} samples  |  Test: {len(X_test):,} samples")

model = IsolationForest(
    n_estimators=200,
    max_samples=256,
    contamination=CONTAMINATION_RATE,
    random_state=RANDOM_STATE,
    n_jobs=-1,
)
model.fit(X_train)

# decision_function: more negative = more anomalous
# Convert to anomaly probability with same sigmoid as production code
def to_score(raw): return 1.0 - (1.0 / (1.0 + np.exp(-raw * 4.0)))

raw_train = model.decision_function(X_train)
raw_test  = model.decision_function(X_test)

scores_train = to_score(raw_train)
scores_test  = to_score(raw_test)

pred_train = (scores_train > ANOMALY_THRESHOLD).astype(int)
pred_test  = (scores_test  > ANOMALY_THRESHOLD).astype(int)

# ─────────────────────────────────────────────────────────────────────────────
# 4. Report metrics
# ─────────────────────────────────────────────────────────────────────────────
print()
print("=" * 70)
print("STEP 4 — Classification Report")
print("=" * 70)

print("\n── TRAINING SET ──────────────────────────────────────────")
print(classification_report(y_train, pred_train, target_names=["clean", "fraud"], digits=3))
cm_tr = confusion_matrix(y_train, pred_train)
print(f"Confusion Matrix (train): TN={cm_tr[0,0]} FP={cm_tr[0,1]} FN={cm_tr[1,0]} TP={cm_tr[1,1]}")

print("\n── TEST SET ──────────────────────────────────────────────")
print(classification_report(y_test, pred_test, target_names=["clean", "fraud"], digits=3))
cm_te = confusion_matrix(y_test, pred_test)
print(f"Confusion Matrix (test) : TN={cm_te[0,0]} FP={cm_te[0,1]} FN={cm_te[1,0]} TP={cm_te[1,1]}")

# ROC-AUC
try:
    auc_train = roc_auc_score(y_train, scores_train)
    auc_test  = roc_auc_score(y_test,  scores_test)
    ap_train  = average_precision_score(y_train, scores_train)
    ap_test   = average_precision_score(y_test,  scores_test)
    print(f"\n{'Metric':<25} {'Train':>10} {'Test':>10}")
    print("-" * 46)
    print(f"{'ROC-AUC':<25} {auc_train:>10.4f} {auc_test:>10.4f}")
    print(f"{'Avg Precision (PR-AUC)':<25} {ap_train:>10.4f} {ap_test:>10.4f}")
    gap = abs(auc_train - auc_test)
    print(f"\nTrain-Test AUC gap: {gap:.4f}", end="  ")
    if gap > 0.05:
        print("⚠️  Overfitting / data leakage suspected")
    else:
        print("✓ Generalisation looks stable")
except Exception as e:
    print(f"AUC failed: {e}")

# ─────────────────────────────────────────────────────────────────────────────
# 5. Per-pattern breakdown (how well does the model catch each fraud type?)
# ─────────────────────────────────────────────────────────────────────────────
print()
print("=" * 70)
print("STEP 5 — Per-pattern fraud detection rate (recall per pattern)")
print("         This shows which patterns are invisible to the model")
print("=" * 70)

labels_full = np.array(
    [0]*n_clean + [1]*n_a + [1]*n_b + [1]*n_c
)
# Re-score on the full dataset without shuffling
X_ordered = np.vstack([
    X[:n_clean],
    X[n_clean:n_clean+n_a],
    X[n_clean+n_a:n_clean+n_a+n_b],
    X[n_clean+n_a+n_b:],
])
# Actually we already shuffled. Use the split by rebuilding unshuffled:

rng2 = np.random.default_rng(RANDOM_STATE)
n_a2 = int(n_fraud * 0.4)
n_b2 = int(n_fraud * 0.3)
n_c2 = n_fraud - n_a2 - n_b2

fraud_a_X = np.column_stack([
    rng2.uniform(0.1, 4.9, n_a2),
    rng2.integers(11, 40, n_a2),
    rng2.integers(0, 5, n_a2),
    np.zeros(n_a2),
    rng2.integers(0, 3, n_a2),
    np.ones(n_a2),
    rng2.uniform(0.0, 0.5, n_a2),
    np.zeros(n_a2),
    np.zeros(n_a2),
    rng2.uniform(0.0, 0.04, n_a2),
])
rng2 = np.random.default_rng(RANDOM_STATE + 1)
fraud_b_X = np.column_stack([
    rng2.uniform(10, 100, n_b2),
    rng2.integers(1, 5, n_b2),
    rng2.integers(0, 60, n_b2),
    rng2.uniform(0.0, 0.3, n_b2),
    rng2.integers(2, 6, n_b2),
    rng2.integers(4, 12, n_b2),
    rng2.uniform(0.1, 0.8, n_b2),
    np.zeros(n_b2),
    rng2.choice([0, 1], n_b2, p=[0.2, 0.8]),
    rng2.uniform(0.05, 0.5, n_b2),
])
rng2 = np.random.default_rng(RANDOM_STATE + 2)
fraud_c_X = np.column_stack([
    rng2.uniform(50, 300, n_c2),
    rng2.integers(1, 3, n_c2),
    rng2.integers(30, 300, n_c2),
    rng2.uniform(0.5, 0.8, n_c2),
    np.zeros(n_c2),
    np.ones(n_c2),
    rng2.uniform(0.5, 1.0, n_c2),
    rng2.integers(3, 8, n_c2),
    np.zeros(n_c2),
    rng2.uniform(0.1, 0.9, n_c2),
])

for name, Xp in [("Pattern A (fast latency + mass claims)", fraud_a_X),
                  ("Pattern B (Sybil device sharing)", fraud_b_X),
                  ("Pattern C (fake disruption)", fraud_c_X)]:
    sc   = to_score(model.decision_function(Xp))
    hits = (sc > ANOMALY_THRESHOLD).sum()
    recall = hits / len(Xp)
    bar = "█" * int(recall * 20) + "░" * (20 - int(recall * 20))
    flag = " ⚠️  BLIND SPOT" if recall < 0.50 else ""
    print(f"\n{name}")
    print(f"  Detected {hits}/{len(Xp)}  recall={recall:.1%}  [{bar}]{flag}")

print()
print("=" * 70)
print("DIAGNOSIS COMPLETE")
print("=" * 70)
print("""
What to look for:
  • ROC-AUC < 0.80  → model isn't separating fraud from clean
  • PR-AUC  < 0.40  → very poor at catching the minority class
  • Pattern C recall < 50% → synthetic data overlaps clean too much
  • Train AUC >> Test AUC → overfitting (unlikely for IF, but worth checking)
""")
