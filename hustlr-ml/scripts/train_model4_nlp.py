"""
Train NLP classifier from nlp_disruption_events.csv (multi-city, dated feed text).
No hand-generated synthetic corpus — only rows from the dataset.
"""

import joblib
from pathlib import Path

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import accuracy_score
from xgboost import XGBClassifier

from model_data_utils import cap_group_rows, grouped_train_test_indices, template_text_groups

PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "trained"
NLP_CSV = PROJECT_ROOT / "outputs" / "datasets" / "nlp_disruption_events.csv"
TEST_SIZE = 0.30


def train_nlp_model():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    print("Training Model 4 — NLP (from nlp_disruption_events.csv)")

    if not NLP_CSV.is_file():
        raise FileNotFoundError(f"Missing dataset: {NLP_CSV}")

    df = pd.read_csv(NLP_CSV)
    if "raw_text" not in df.columns or "trigger_label" not in df.columns:
        raise ValueError("nlp_disruption_events.csv needs raw_text and trigger_label")

    df = df.dropna(subset=["raw_text", "trigger_label"])
    df["raw_text"] = df["raw_text"].astype(str).str.strip()
    df = df[df["raw_text"].str.len() > 0]
    df["text_group"] = template_text_groups(df["raw_text"], df["zone"].dropna().unique())
    df = cap_group_rows(df, "text_group", max_rows_per_group=3, random_state=42)

    labels = df["trigger_label"].astype(str)
    label_map = {lab: i for i, lab in enumerate(sorted(labels.unique()))}
    y_encoded = labels.map(label_map).astype(int).values
    train_idx, test_idx = grouped_train_test_indices(df["text_group"], test_size=TEST_SIZE, random_state=42)

    train_text = df.iloc[train_idx]["raw_text"]
    test_text = df.iloc[test_idx]["raw_text"]
    y_tr = y_encoded[train_idx]
    y_te = y_encoded[test_idx]

    tfidf = TfidfVectorizer(
        max_features=4000,
        ngram_range=(1, 3),
        sublinear_tf=True,
        min_df=2,
        strip_accents="unicode",
        analyzer="word",
    )
    X_tr = tfidf.fit_transform(train_text)
    X_te = tfidf.transform(test_text)

    xgb_clf = XGBClassifier(
        n_estimators=300,
        learning_rate=0.05,
        max_depth=6,
        random_state=42,
        n_jobs=-1,
        tree_method="hist",
        device="cpu",
        objective="multi:softprob",
        num_class=len(label_map),
    )
    xgb_clf.fit(X_tr, y_tr)

    train_acc = accuracy_score(y_tr, xgb_clf.predict(X_tr))
    test_acc = accuracy_score(y_te, xgb_clf.predict(X_te))
    print(f"Train Accuracy: {train_acc:.4f}")
    print(f"Test Accuracy:  {test_acc:.4f}")
    print(
        f"Rows: {len(df)} | unique text groups: {df['text_group'].nunique()} | "
        f"zones: {df['zone'].nunique()} | labels: {list(label_map.keys())}"
    )

    joblib.dump(label_map, MODELS_DIR / "model4_label_map.pkl")
    xgb_clf.save_model(MODELS_DIR / "model4_rf_nlp.json")
    joblib.dump(tfidf, MODELS_DIR / "model4_tfidf.pkl")
    print("Saved NLP model successfully.")


if __name__ == "__main__":
    train_nlp_model()
