from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "datasets"
WORKER_CSV = DATA_DIR / "worker_profiles.csv"
CLAIMS_CSV = DATA_DIR / "claims_fraud.csv"
RANDOM_STATE = 42

CITY_CONFIG = {
    "Chennai": {
        "zones": [
            ("Adyar", 13.0012, 80.2565),
            ("Anna Nagar", 13.0850, 80.2101),
            ("Chromepet", 12.9516, 80.1462),
            ("Guduvanchery", 12.7449, 80.0179),
            ("Guindy", 13.0106, 80.2205),
            ("Kathankulathur", 12.8230, 80.0443),
            ("Kelambakkam", 12.7869, 80.2216),
            ("Perambur", 13.1189, 80.2326),
            ("Potheri", 12.8249, 80.0397),
            ("Porur", 13.0353, 80.1587),
            ("Sholinganallur", 12.9010, 80.2279),
            ("Siruseri", 12.8352, 80.2283),
            ("T Nagar", 13.0418, 80.2337),
            ("Tambaram", 12.9249, 80.1275),
            ("Urapakkam", 12.8899, 80.0694),
            ("Velachery", 12.9759, 80.2212),
        ],
        "income_shift": 0.0,
        "flood_shift": 0.03,
        "bandh_shift": 0.0,
        "outage_shift": 0.0,
        "fraud_shift": 0.00,
    },
    "Mumbai": {
        "zones": [
            ("Andheri", 19.1197, 72.8468),
            ("Bandra", 19.0544, 72.8402),
            ("Borivali", 19.2307, 72.8567),
            ("Chembur", 19.0522, 72.9005),
            ("Dadar", 19.0178, 72.8478),
            ("Ghatkopar", 19.0790, 72.9080),
            ("Lower Parel", 18.9985, 72.8306),
            ("Powai", 19.1176, 72.9060),
            ("Thane", 19.2183, 72.9781),
            ("Vashi", 19.0771, 72.9986),
        ],
        "income_shift": 95.0,
        "flood_shift": 0.10,
        "bandh_shift": -0.8,
        "outage_shift": 0.2,
        "fraud_shift": 0.02,
    },
    "Bengaluru": {
        "zones": [
            ("BTM Layout", 12.9166, 77.6101),
            ("Electronic City", 12.8456, 77.6603),
            ("Indiranagar", 12.9784, 77.6408),
            ("Jayanagar", 12.9250, 77.5938),
            ("Koramangala", 12.9352, 77.6245),
            ("Marathahalli", 12.9569, 77.7011),
            ("Rajajinagar", 12.9911, 77.5560),
            ("Whitefield", 12.9698, 77.7500),
            ("Yelahanka", 13.1007, 77.5963),
            ("HSR Layout", 12.9116, 77.6474),
        ],
        "income_shift": 70.0,
        "flood_shift": 0.00,
        "bandh_shift": -0.5,
        "outage_shift": -0.1,
        "fraud_shift": 0.01,
    },
    "Kolkata": {
        "zones": [
            ("Dum Dum", 22.6420, 88.4312),
            ("Garia", 22.4594, 88.3854),
            ("Howrah", 22.5958, 88.2636),
            ("New Town", 22.5752, 88.4794),
            ("Park Street", 22.5519, 88.3529),
            ("Salt Lake", 22.5867, 88.4172),
            ("Sealdah", 22.5685, 88.3702),
            ("Tollygunge", 22.4869, 88.3456),
            ("Behala", 22.5036, 88.3174),
            ("Esplanade", 22.5646, 88.3506),
        ],
        "income_shift": -40.0,
        "flood_shift": 0.04,
        "bandh_shift": 1.2,
        "outage_shift": 0.1,
        "fraud_shift": -0.01,
    },
}


def stable_rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def expand_workers(base: pd.DataFrame) -> pd.DataFrame:
    parts: list[pd.DataFrame] = []
    base = base.copy().reset_index(drop=True)
    for idx, (city, cfg) in enumerate(CITY_CONFIG.items()):
        rng = stable_rng(RANDOM_STATE + idx)
        out = base.copy()
        n = len(out)
        zone_idx = rng.integers(0, len(cfg["zones"]), size=n)
        zone_names = [cfg["zones"][i][0] for i in zone_idx]
        lat = np.array([cfg["zones"][i][1] for i in zone_idx]) + rng.normal(0, 0.01, n)
        lon = np.array([cfg["zones"][i][2] for i in zone_idx]) + rng.normal(0, 0.01, n)

        out["worker_id"] = [f"{city[:3].upper()}_{i:05d}" for i in range(1, n + 1)]
        out["city"] = city
        out["zone"] = zone_names
        out["lat"] = lat.round(6)
        out["lon"] = lon.round(6)
        out["avg_daily_income"] = np.clip(out["avg_daily_income"] + cfg["income_shift"] + rng.normal(0, 35, n), 220, 1200).round(1)
        out["zone_flood_risk"] = np.clip(out["zone_flood_risk"] + cfg["flood_shift"] + rng.normal(0, 0.04, n), 0.02, 0.92).round(3)
        out["bandh_freq_zone"] = np.clip(np.round(out["bandh_freq_zone"] + cfg["bandh_shift"] + rng.normal(0, 1.0, n)), 0, 12).astype(int)
        out["platform_outage_per_mo"] = np.clip(np.round(out["platform_outage_per_mo"] + cfg["outage_shift"] + rng.normal(0, 0.7, n)), 0, 8).astype(int)
        out["disruption_freq_12mo"] = np.clip(np.round(out["disruption_freq_12mo"] + rng.normal(0, 2.5, n)), 1, 36).astype(int)
        out["claims_history_penalty"] = np.clip(np.round(out["claims_history_penalty"] + rng.normal(0, 0.8, n)), 0, 7).astype(int)
        out["coastal_zone"] = np.where(out["zone_flood_risk"] > 0.55, 1, out["coastal_zone"]).astype(int)
        parts.append(out)
    return pd.concat(parts, ignore_index=True)


def expand_claims(base_claims: pd.DataFrame, workers: pd.DataFrame) -> pd.DataFrame:
    claims = base_claims.copy()
    claims["claim_date"] = pd.to_datetime(claims["claim_date"], errors="coerce")
    workers_simple = workers[["worker_id", "city", "zone", "iss_score"]].copy()
    out_parts: list[pd.DataFrame] = []

    for idx, (city, cfg) in enumerate(CITY_CONFIG.items()):
        rng = stable_rng(RANDOM_STATE + 100 + idx)
        worker_ids = workers_simple.loc[workers_simple["city"] == city, "worker_id"].tolist()
        sample_idx = rng.integers(0, len(worker_ids), size=len(claims))
        part = claims.copy()
        part["worker_id"] = [worker_ids[i] for i in sample_idx]
        part = part.merge(workers_simple, on="worker_id", how="left", suffixes=("", "_worker"))
        part["city"] = city
        part["zone"] = part["zone_worker"].fillna(part["zone"])
        part["iss_score"] = part["iss_score_worker"].fillna(part["iss_score"]).astype(int)
        part.drop(columns=["zone_worker", "iss_score_worker"], inplace=True)

        part["days_since_onboard"] = np.clip(
            np.round(part["days_since_onboard"] + rng.normal(0, 18, len(part))),
            5,
            420,
        ).astype(int)
        part["simultaneous_zone_claims"] = np.clip(
            np.round(part["simultaneous_zone_claims"] + rng.normal(cfg["fraud_shift"] * 8, 1.8, len(part))),
            0,
            18,
        ).astype(int)
        part["zone_depth_score"] = np.clip(part["zone_depth_score"] + rng.normal(0, 0.08, len(part)), 0.05, 0.98).round(4)
        part["gps_jitter_perfect"] = np.clip(pd.to_numeric(part["gps_jitter_perfect"], errors="coerce").fillna(0) + rng.normal(0, 0.06, len(part)), 0, 1).round(6)
        fraud_prob = np.clip(0.035 + cfg["fraud_shift"] + 0.015 * (part["simultaneous_zone_claims"] > 6) + 0.01 * (part["days_since_onboard"] < 35), 0.01, 0.25)
        flips = rng.random(len(part)) < fraud_prob
        part.loc[flips, "is_fraud"] = 1
        part.loc[flips, "is_fraudster"] = 1
        out_parts.append(part)

    out = pd.concat(out_parts, ignore_index=True)
    out["claim_date"] = out["claim_date"].dt.strftime("%Y-%m-%d")
    out["claim_id"] = [f"CLM{i:07d}" for i in range(1, len(out) + 1)]
    return out


def main() -> None:
    base_workers = pd.read_csv(WORKER_CSV)
    base_claims = pd.read_csv(CLAIMS_CSV)
    workers = expand_workers(base_workers)
    claims = expand_claims(base_claims, workers)
    workers.to_csv(WORKER_CSV, index=False)
    claims.to_csv(CLAIMS_CSV, index=False)
    print(f"Expanded {WORKER_CSV} to {len(workers):,} rows across {workers['city'].nunique()} cities")
    print(workers["city"].value_counts().to_dict())
    print(f"Expanded {CLAIMS_CSV} to {len(claims):,} rows across {claims['city'].nunique()} cities")
    print(claims["city"].value_counts().to_dict())


if __name__ == "__main__":
    main()
