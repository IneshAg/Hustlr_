"""Evaluate a saved delivery-time model on train.csv.

Usage:
  python scripts/evaluate_delivery_model.py
"""

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "delivery_time_v3.json"


def resolve_report_path(output_dir: Path) -> Path:
    candidates = [
        output_dir / "delivery_time_improvement_report_v4.json",
        output_dir / "delivery_time_improvement_report_v3.json",
    ]
    for path in candidates:
        if path.exists():
            return path
    raise FileNotFoundError(
        "Missing improvement report. Expected one of: "
        f"{candidates[0]}, {candidates[1]}"
    )


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
    df["distance_x_multi"] = df["distance_km"] * df["multiple_deliveries"].fillna(0)

    for col in ["order_hour", "pickup_hour"]:
        df[f"{col}_sin"] = np.sin(2 * np.pi * df[col] / 24.0)
        df[f"{col}_cos"] = np.cos(2 * np.pi * df[col] / 24.0)

    return df


def main() -> int:
    cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    input_csv = Path(cfg["input_csv"])
    output_dir = Path(cfg["output_dir"])
    report_path = resolve_report_path(output_dir)

    report = json.loads(report_path.read_text(encoding="utf-8"))
    model_path = Path(report["final_model_path"])
    if not model_path.exists():
        raise FileNotFoundError(f"Missing model: {model_path}")

    raw = pd.read_csv(input_csv)
    raw.columns = [c.strip() for c in raw.columns]

    target = cfg["target_column"]
    feat = build_features(raw)
    feat = feat[feat[target].notna()].copy()
    feat = feat[(feat["Restaurant_latitude"] != 0) & (feat["Restaurant_longitude"] != 0)].copy()

    drop_cols = ["ID", "Delivery_person_ID", "Order_Date", "Time_Orderd", "Time_Order_picked", target]
    x = feat.drop(columns=[c for c in drop_cols if c in feat.columns], errors="ignore")
    y = feat[target]

    bins = pd.qcut(y, q=10, duplicates="drop")
    _, x_test, _, y_test = train_test_split(
        x,
        y,
        test_size=float(cfg["test_size"]),
        random_state=int(cfg["seed"]),
        stratify=bins,
    )

    model = joblib.load(model_path)
    pred = model.predict(x_test)

    metrics = {
        "MAE": float(mean_absolute_error(y_test, pred)),
        "RMSE": float(np.sqrt(mean_squared_error(y_test, pred))),
        "R2": float(r2_score(y_test, pred)),
        "model_path": str(model_path),
        "test_rows": int(len(x_test)),
    }

    out = output_dir / "delivery_time_eval_report.json"
    out.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
