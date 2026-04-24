"""Train delivery-time model with no-regression guard.

Usage:
  python scripts/train_delivery_time_v3.py
"""

import json
import os
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import ExtraTreesRegressor, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "delivery_time_v3.json"


def load_config() -> dict:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def _get_nested(dct, keys):
    cur = dct
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def collect_baseline_mae(report_paths):
    candidates = []
    key_paths = [
        ("metrics", "RandomForest", "MAE"),
        ("augmented_metrics", "MAE"),
        ("best_new_model_mae",),
        ("best_candidate_mae",),
    ]
    for path in report_paths:
        p = Path(path)
        if not p.exists():
            continue
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
            for key_path in key_paths:
                value = _get_nested(data, key_path)
                if value is not None:
                    value = float(value)
                    if np.isfinite(value):
                        candidates.append(value)
        except Exception:
            continue
    return min(candidates) if candidates else None


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1 = np.radians(lat1)
    p2 = np.radians(lat2)
    dphi = np.radians(lat2 - lat1)
    dlambda = np.radians(lon2 - lon1)
    a = np.sin(dphi / 2.0) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dlambda / 2.0) ** 2
    return 2 * r * np.arctan2(np.sqrt(a), np.sqrt(1 - a))


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    numeric_cols = [
        "Restaurant_latitude",
        "Restaurant_longitude",
        "Delivery_location_latitude",
        "Delivery_location_longitude",
        "Delivery_person_Age",
        "Delivery_person_Ratings",
        "Vehicle_condition",
        "multiple_deliveries",
        "Time_taken(min)",
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    for col in ["Time_Orderd", "Time_Order_picked"]:
        if col in df.columns:
            raw = df[col].astype(str).str.strip()
            df[col] = pd.to_datetime(raw, format="%H:%M:%S", errors="coerce")

    if "Order_Date" in df.columns:
        order_dt = pd.to_datetime(df["Order_Date"].astype(str).str.strip(), format="%d-%m-%Y", errors="coerce")
    else:
        order_dt = pd.Series(pd.NaT, index=df.index)

    df["distance_km"] = haversine_km(
        df["Restaurant_latitude"],
        df["Restaurant_longitude"],
        df["Delivery_location_latitude"],
        df["Delivery_location_longitude"],
    )
    df["distance_km_sq"] = df["distance_km"] ** 2

    df["order_hour"] = df["Time_Orderd"].dt.hour
    df["pickup_hour"] = df["Time_Order_picked"].dt.hour

    prep = (df["Time_Order_picked"] - df["Time_Orderd"]).dt.total_seconds() / 60.0
    prep = prep.where(prep >= 0, prep + 24 * 60)
    df["prep_time_min"] = prep

    df["order_weekday"] = order_dt.dt.weekday
    df["order_month"] = order_dt.dt.month
    df["is_weekend"] = (df["order_weekday"] >= 5).astype(float)

    df["age_x_rating"] = df["Delivery_person_Age"] * df["Delivery_person_Ratings"]
    df["rating_sq"] = df["Delivery_person_Ratings"] ** 2
    df["distance_x_rating"] = df["distance_km"] * df["Delivery_person_Ratings"]

    for col in ["order_hour", "pickup_hour"]:
        df[f"{col}_sin"] = np.sin(2 * np.pi * df[col] / 24.0)
        df[f"{col}_cos"] = np.cos(2 * np.pi * df[col] / 24.0)

    return df


def main() -> int:
    cfg = load_config()
    np.random.seed(int(cfg["seed"]))

    target = cfg["target_column"]
    input_csv = Path(cfg["input_csv"])
    output_dir = Path(cfg["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    if not input_csv.exists():
        raise FileNotFoundError(f"Input CSV not found: {input_csv}")

    baseline_mae = collect_baseline_mae(cfg["baseline_report_candidates"])

    raw = pd.read_csv(input_csv)
    raw.columns = [c.strip() for c in raw.columns]

    feat = build_features(raw)
    feat = feat[feat[target].notna()].copy()
    feat = feat[(feat["Restaurant_latitude"] != 0) & (feat["Restaurant_longitude"] != 0)].copy()

    drop_cols = ["ID", "Delivery_person_ID", "Order_Date", "Time_Orderd", "Time_Order_picked", target]
    x = feat.drop(columns=[c for c in drop_cols if c in feat.columns], errors="ignore")
    y = feat[target]

    bins = pd.qcut(y, q=10, duplicates="drop")
    x_train, x_test, y_train, y_test = train_test_split(
        x,
        y,
        test_size=float(cfg["test_size"]),
        random_state=int(cfg["seed"]),
        stratify=bins,
    )

    num_cols = [c for c in x_train.columns if pd.api.types.is_numeric_dtype(x_train[c])]
    cat_cols = [c for c in x_train.columns if c not in num_cols]

    pre = ColumnTransformer(
        [
            ("num", Pipeline([("imp", SimpleImputer(strategy="median"))]), num_cols),
            (
                "cat",
                Pipeline(
                    [
                        ("imp", SimpleImputer(strategy="most_frequent")),
                        ("ohe", OneHotEncoder(handle_unknown="ignore", min_frequency=20)),
                    ]
                ),
                cat_cols,
            ),
        ]
    )

    models = {
        "RF_tuned": RandomForestRegressor(
            n_estimators=900,
            random_state=int(cfg["seed"]),
            n_jobs=-1,
            min_samples_leaf=1,
            max_features=0.6,
        ),
        "ET_tuned": ExtraTreesRegressor(
            n_estimators=1200,
            random_state=int(cfg["seed"]),
            n_jobs=-1,
            min_samples_leaf=1,
            max_features=0.7,
        ),
    }

    results = {}
    best_name = None
    best_mae = 10**9
    best_pipe = None

    for name, model in models.items():
        pipe = Pipeline([("pre", pre), ("model", model)])
        pipe.fit(x_train, y_train)
        pred = pipe.predict(x_test)
        mae = float(mean_absolute_error(y_test, pred))
        rmse = float(np.sqrt(mean_squared_error(y_test, pred)))
        r2 = float(r2_score(y_test, pred))
        results[name] = {"MAE": mae, "RMSE": rmse, "R2": r2}

        if mae < best_mae:
            best_mae = mae
            best_name = name
            best_pipe = pipe

    accepted = baseline_mae is None or best_mae <= baseline_mae
    if accepted:
        model_path = output_dir / f"delivery_time_best_v3_{best_name}.joblib"
        joblib.dump(best_pipe, model_path)
        source = "new_v3"
    else:
        # keep older best if regression happens
        fallback = output_dir / "delivery_time_best_v3_RF_tuned.joblib"
        model_path = fallback if fallback.exists() else Path("")
        source = "kept_previous_no_regression"

    report = {
        "baseline_best_mae_across_reports": baseline_mae,
        "rows_used": int(len(x)),
        "train_rows": int(len(x_train)),
        "test_rows": int(len(x_test)),
        "feature_count": int(x.shape[1]),
        "results": results,
        "best_candidate": best_name,
        "best_candidate_mae": float(best_mae),
        "accepted_new_model": bool(accepted),
        "final_model_source": source,
        "final_model_path": str(model_path),
    }

    report_path = output_dir / "delivery_time_improvement_report_v3.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
