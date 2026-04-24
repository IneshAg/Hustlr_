from __future__ import annotations

import math
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd

from external_city_data_utils import city_environment_penalty

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATASETS_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "datasets"
WORKER_CSV = DATASETS_DIR / "worker_profiles.csv"
CLAIMS_CSV = DATASETS_DIR / "claims_fraud.csv"
RANDOM_STATE = 42
REFERENCE_DATE = pd.Timestamp("2026-01-01")
EXTERNAL_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "external_data"
CITY_ENV_PRIORS = {
    "Chennai": -1.2,
    "Mumbai": -1.5,
    "Bengaluru": -0.7,
    "Kolkata": -1.0,
}


def _stable_uniform(ids: pd.Series, salt: str) -> np.ndarray:
    hashed = pd.util.hash_pandas_object(ids.astype(str) + salt, index=False).to_numpy(dtype="uint64")
    return (hashed % 1_000_003) / 1_000_003.0


def rebuild_worker_scores(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    onboard = pd.to_datetime(out["onboard_date"], errors="coerce")
    tenure_months = ((REFERENCE_DATE - onboard).dt.days.fillna(180).clip(lower=30) / 30.4).to_numpy()

    u1 = _stable_uniform(out["worker_id"], ":latent1")
    u2 = _stable_uniform(out["worker_id"], ":latent2")
    worker_latent = (u1 - 0.5) * 10.0
    worker_noise = (u2 - 0.5) * 4.0

    zone_codes = out["zone"].astype("category").cat.codes.to_numpy()
    zone_wave = np.sin((zone_codes + 1) * 0.9) * 1.5
    seasonal_tenure = np.sin((tenure_months % 12) / 12.0 * 2 * math.pi) * 1.8

    if "city" in out.columns:
        env_term = out["city"].astype(str).map(load_city_environment_term).fillna(-0.8).to_numpy()
    else:
        env_term = np.full(len(out), load_city_environment_term("Chennai"))

    income_term = 12.5 * np.tanh((out["avg_daily_income"].to_numpy() - 575.0) / 210.0)
    flood_term = -24.0 * out["zone_flood_risk"].to_numpy()
    disruption_term = -12.0 * np.log1p(out["disruption_freq_12mo"].to_numpy()) / np.log(20)
    claims_term = -2.3 * np.power(out["claims_history_penalty"].to_numpy(), 0.98)
    bandh_term = -0.55 * out["bandh_freq_zone"].to_numpy()
    outage_term = -1.2 * out["platform_outage_per_mo"].to_numpy()
    coastal_term = -2.8 * out["coastal_zone"].astype(float).to_numpy()
    tenure_term = 7.2 * np.tanh((tenure_months - 18.0) / 18.0)

    nonlinear_bonus = np.where(
        (out["avg_daily_income"].to_numpy() > 700) & (out["claims_history_penalty"].to_numpy() <= 2),
        3.5,
        0.0,
    )
    fragility_penalty = np.where(
        (out["zone_flood_risk"].to_numpy() > 0.55) & (out["disruption_freq_12mo"].to_numpy() > 16),
        -5.0,
        0.0,
    )

    score = (
        66.0
        + income_term
        + flood_term
        + disruption_term
        + claims_term
        + bandh_term
        + outage_term
        + coastal_term
        + tenure_term
        + seasonal_tenure
        + zone_wave
        + env_term
        + worker_latent
        + worker_noise
        + nonlinear_bonus
        + fragility_penalty
    )
    score = np.clip(np.round(score), 18, 96).astype(int)

    out["iss_score"] = score
    out["recommended_tier"] = np.select(
        [score < 38, score < 62],
        ["Full Shield", "Standard Shield"],
        default="Basic Shield",
    )

    base_premium = np.select(
        [score < 38, score < 62],
        [79, 49],
        default=29,
    )
    premium_risk = np.where(out["zone_flood_risk"].to_numpy() > 0.45, 6, 0)
    premium_disruption = np.where(out["disruption_freq_12mo"].to_numpy() > 18, 4, 0)
    out["weekly_premium"] = (base_premium + premium_risk + premium_disruption).astype(int)
    return out


@lru_cache(maxsize=None)
def load_city_environment_term(city: str) -> float:
    bonus = CITY_ENV_PRIORS.get(str(city), -0.8)
    return bonus + city_environment_penalty(str(city))


def sync_claim_scores(worker_df: pd.DataFrame, claims_df: pd.DataFrame) -> pd.DataFrame:
    out = claims_df.copy()
    score_map = worker_df.set_index("worker_id")["iss_score"]
    out["iss_score"] = out["worker_id"].map(score_map).fillna(out["iss_score"]).astype(int)
    return out


def main() -> None:
    worker_df = pd.read_csv(WORKER_CSV)
    claims_df = pd.read_csv(CLAIMS_CSV)

    worker_new = rebuild_worker_scores(worker_df)
    claims_new = sync_claim_scores(worker_new, claims_df)

    worker_new.to_csv(WORKER_CSV, index=False)
    claims_new.to_csv(CLAIMS_CSV, index=False)

    print(f"Updated {WORKER_CSV}")
    print(
        "ISS summary:",
        {
            "mean": round(float(worker_new["iss_score"].mean()), 2),
            "std": round(float(worker_new["iss_score"].std()), 2),
            "min": int(worker_new["iss_score"].min()),
            "max": int(worker_new["iss_score"].max()),
        },
    )
    print(f"Synced ISS scores into {CLAIMS_CSV}")


if __name__ == "__main__":
    main()
