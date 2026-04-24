from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pandas as pd

from model_data_utils import grouped_train_test_indices, month_groups, template_text_groups


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "datasets"
MODELS_DIR = PROJECT_ROOT / "hustlr-ml" / "models" / "trained"
BENCH_DIR = PROJECT_ROOT / "outputs" / "benchmarks"
MANIFEST_DIR = PROJECT_ROOT / "outputs" / "model_manifests"
TEST_SIZE = 0.30
RANDOM_STATE = 42


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def iss_manifest() -> dict:
    df = pd.read_csv(DATA_DIR / "worker_profiles.csv")
    train_idx, test_idx = grouped_train_test_indices(
        month_groups(df["onboard_date"]),
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
    )
    return {
        "dataset": "worker_profiles.csv",
        "split_policy": "grouped_by_onboard_month",
        "random_state": RANDOM_STATE,
        "test_size": TEST_SIZE,
        "train_indices": train_idx.tolist(),
        "test_indices": test_idx.tolist(),
    }


def fraud_manifest() -> dict:
    df = pd.read_csv(DATA_DIR / "claims_fraud.csv")
    train_idx, test_idx = grouped_train_test_indices(
        df["worker_id"].astype(str),
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
    )
    return {
        "dataset": "claims_fraud.csv",
        "split_policy": "grouped_by_worker_id",
        "random_state": RANDOM_STATE,
        "test_size": TEST_SIZE,
        "train_indices": train_idx.tolist(),
        "test_indices": test_idx.tolist(),
    }


def nlp_manifest() -> dict:
    df = pd.read_csv(DATA_DIR / "nlp_disruption_events.csv").dropna(subset=["raw_text", "trigger_label"]).copy()
    groups = template_text_groups(df["raw_text"], df["zone"].dropna().unique())
    train_idx, test_idx = grouped_train_test_indices(
        groups,
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
    )
    return {
        "dataset": "nlp_disruption_events.csv",
        "split_policy": "grouped_by_template_text",
        "random_state": RANDOM_STATE,
        "test_size": TEST_SIZE,
        "train_indices": train_idx.tolist(),
        "test_indices": test_idx.tolist(),
    }


def chrono_manifest(filename: str, date_col: str) -> dict:
    df = pd.read_csv(DATA_DIR / filename)
    df[date_col] = pd.to_datetime(df[date_col], errors="coerce")
    df = df.sort_values(date_col).reset_index(drop=True)
    split_idx = int(len(df) * (1 - TEST_SIZE))
    return {
        "dataset": filename,
        "split_policy": f"chronological_by_{date_col}",
        "test_size": TEST_SIZE,
        "train_indices": list(range(split_idx)),
        "test_indices": list(range(split_idx, len(df))),
    }


def prophet_manifest() -> dict:
    df = pd.read_csv(DATA_DIR / "prophet_training.csv")
    df["ds"] = pd.to_datetime(df["ds"], errors="coerce")
    split_idx = int(len(df) * 0.80)
    return {
        "dataset": "prophet_training.csv",
        "split_policy": "rolling_backtest_reference",
        "test_size_reference": 0.20,
        "reference_split_index": split_idx,
        "window_starts": [0.60, 0.70, 0.80],
    }


def build_model_manifest() -> dict:
    datasets = {}
    for path in sorted(DATA_DIR.glob("*.csv")):
        datasets[path.name] = {
            "sha256": file_sha256(path),
            "rows": int(pd.read_csv(path).shape[0]),
        }

    artifacts = {}
    for path in sorted(MODELS_DIR.glob("*")):
        if path.is_file():
            artifacts[path.name] = {
                "sha256": file_sha256(path),
                "bytes": path.stat().st_size,
            }

    return {
        "datasets": datasets,
        "artifacts": artifacts,
        "benchmark_dir": str(BENCH_DIR),
    }


def main() -> None:
    manifests = {
        "model1_iss_split.json": iss_manifest(),
        "model3_fraud_split.json": fraud_manifest(),
        "model4_nlp_split.json": nlp_manifest(),
        "model5_blackout_split.json": chrono_manifest("connectivity_dataset.csv", "date"),
        "model6_traffic_split.json": chrono_manifest("traffic_accidents.csv", "date"),
        "model7_prophet_split.json": prophet_manifest(),
    }
    for name, payload in manifests.items():
        write_json(BENCH_DIR / name, payload)
    write_json(MANIFEST_DIR / "latest_model_manifest.json", build_model_manifest())
    print(f"Wrote {len(manifests)} benchmark manifests to {BENCH_DIR}")
    print(f"Wrote model manifest to {MANIFEST_DIR / 'latest_model_manifest.json'}")


if __name__ == "__main__":
    main()
