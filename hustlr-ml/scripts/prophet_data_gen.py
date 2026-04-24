#!/usr/bin/env python3
"""
prophet_data_gen.py
====================
Synthetic Training Dataset Generator — Hustlr M7 Prophet Model
ML-DATASET-BLUEPRINT-v1.0 | Code Crafters | Guidewire DEVTrails 2026

Generates ~3.9M rows of demand data across 150 H3 zones (2022–2024, hourly).
All multipliers are applied MULTIPLICATIVELY per expert panel consensus.

Dependencies: pandas, numpy (stdlib: datetime, random)
Runtime target: < 5 minutes on modern hardware
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import sys

# ─────────────────────────────────────────────────────────
# GLOBAL CONFIG
# ─────────────────────────────────────────────────────────
RANDOM_SEED   = 42
N_ZONES       = 150
START_DATE    = "2022-01-01"
END_DATE      = "2024-12-31"
OUTPUT_FILE   = "hustlr-ml/outputs/datasets/prophet_training.csv"
CHUNK_ROWS    = 200_000          # rows per CSV write chunk (memory management)

np.random.seed(RANDOM_SEED)
random.seed(RANDOM_SEED)


# ─────────────────────────────────────────────────────────
# STAGE 0: ZONE REGISTRY
# ─────────────────────────────────────────────────────────

CITY_ZONE_MAP = (
    ["Mumbai"]    * 40 +
    ["Chennai"]   * 40 +
    ["Bangalore"] * 35 +
    ["Tier2"]     * 35
)

CITY_BASE_DEMAND = {
    "Mumbai":    85.0,
    "Chennai":   60.0,
    "Bangalore": 70.0,
    "Tier2":     30.0,
}

def generate_zone_ids(n_zones: int) -> list:
    rng = np.random.default_rng(RANDOM_SEED)
    zones = []
    for i in range(n_zones):
        hex_body = rng.integers(0, 16, size=13)
        hex_str  = "89" + "".join(format(x, "x") for x in hex_body) + "fff"
        city     = CITY_ZONE_MAP[i]
        zone_noise = rng.uniform(0.85, 1.15)
        zones.append({
            "zone_id":    hex_str,
            "city_type":  city,
            "base_scale": CITY_BASE_DEMAND[city] * zone_noise,
        })
    return zones


# ─────────────────────────────────────────────────────────
# STAGE 1: BASE DEMAND
# ─────────────────────────────────────────────────────────

HOURLY_PROFILE = np.array([
    0.10, 0.07, 0.05, 0.04, 0.04, 0.06,
    0.18, 0.42, 0.65, 0.70, 0.68, 0.75,
    0.95, 1.00, 0.88, 0.78, 0.82, 0.90,
    0.98, 1.00, 0.95, 0.85, 0.70, 0.45,
])

DAILY_PROFILE = np.array([0.88, 0.90, 0.92, 0.95, 1.00, 1.05, 0.98])

def base_demand(hour: np.ndarray, dow: np.ndarray, base_scale: float) -> np.ndarray:
    h_factor = HOURLY_PROFILE[hour]
    d_factor = DAILY_PROFILE[dow]
    noise    = np.random.normal(1.0, 0.08, size=len(hour))
    noise    = np.clip(noise, 0.80, 1.20)
    return base_scale * h_factor * d_factor * noise


# ─────────────────────────────────────────────────────────
# STAGE 2A: FESTIVAL MULTIPLIERS
# ─────────────────────────────────────────────────────────

DIWALI_DATES = {
    2022: datetime(2022, 10, 24),
    2023: datetime(2023, 11, 12),
    2024: datetime(2024, 10, 31),
}
DIWALI_PEAK      = {2022: 4.5, 2023: 4.3, 2024: 4.7}
DIWALI_RAMP_DAYS = 7

IPL_SEASONS = [
    (datetime(2022, 3, 26), datetime(2022, 5, 29)),
    (datetime(2023, 3, 31), datetime(2023, 5, 28)),
    (datetime(2024, 3, 22), datetime(2024, 5, 26)),
]
IPL_HOURS = set(range(18, 24))

def build_festival_lookup(timestamps: pd.DatetimeIndex):
    n = len(timestamps)
    fest_mult = np.ones(n, dtype=np.float32)
    ipl_flag  = np.zeros(n, dtype=bool)

    dates_only = timestamps.normalize()
    hours      = timestamps.hour

    for year, anchor in DIWALI_DATES.items():
        peak      = DIWALI_PEAK[year]
        anchor_pd = pd.Timestamp(anchor, tz="Asia/Kolkata")
        for delta in range(-DIWALI_RAMP_DAYS, DIWALI_RAMP_DAYS + 1):
            target_day = anchor_pd + pd.Timedelta(days=delta)
            mask = (dates_only == target_day)
            if mask.any():
                t_weight = max(0.0, 1.0 - abs(delta) / (DIWALI_RAMP_DAYS + 1))
                m = 0.8 + (peak - 0.8) * t_weight
                if delta > 0:
                    m = 0.8 + (m - 0.8) * 0.7
                fest_mult[mask] = np.float32(round(m, 4))

    for ipl_start, ipl_end in IPL_SEASONS:
        s_pd = pd.Timestamp(ipl_start, tz="Asia/Kolkata")
        e_pd = pd.Timestamp(ipl_end,   tz="Asia/Kolkata")
        date_mask = (dates_only >= s_pd) & (dates_only <= e_pd)
        unique_dates = pd.DatetimeIndex(dates_only[date_mask].unique())
        rng_match = np.random.RandomState(RANDOM_SEED)
        match_days = set(
            d for d in unique_dates
            if rng_match.random() < 0.60
        )
        combined_mask = np.array([
            (dates_only[i] in match_days) and (hours[i] in IPL_HOURS)
            for i in range(n)
        ], dtype=bool)
        ipl_flag[combined_mask] = True

    fest_mult = np.clip(fest_mult, 0.8, 5.0)
    return fest_mult, ipl_flag


# ─────────────────────────────────────────────────────────
# STAGE 2B: WEATHER SIMULATION
# ─────────────────────────────────────────────────────────

MONSOON_PROFILE = {
    "Mumbai":    {6: (12, 6), 7: (18, 8), 8: (16, 7), 9: (10, 5)},
    "Chennai":   {10: (8, 4), 11: (12, 6), 12: (9, 5)},
    "Bangalore": {5: (4, 2), 6: (6, 3), 7: (8, 4), 8: (7, 3), 9: (6, 3), 10: (5, 2)},
    "Tier2":     {7: (5, 3), 8: (6, 3), 9: (4, 2)},
}

TEMP_PARAMS = {
    "Mumbai":    (30.0, 5.0, -1),
    "Chennai":   (32.0, 4.0,  0),
    "Bangalore": (25.0, 4.5,  0),
    "Tier2":     (28.0, 7.0,  1),
}

def weather_for_zone(timestamps: pd.DatetimeIndex, city: str):
    n      = len(timestamps)
    precip = np.zeros(n, dtype=np.float32)
    months = timestamps.month
    doy    = timestamps.day_of_year.to_numpy()
    hours  = timestamps.hour.to_numpy()

    monsoon = MONSOON_PROFILE.get(city, {})
    for m, (daily_mean, _) in monsoon.items():
        mask = (months == m)
        if mask.any():
            hourly_mean = daily_mean / 24.0
            vals = np.random.gamma(0.5, hourly_mean / 0.5, size=mask.sum())
            vals = np.clip(vals, 0, 200)
            day_hour_mask = (hours[mask] >= 10) & (hours[mask] <= 17)
            vals[day_hour_mask] *= 0.6
            precip[mask] = vals.astype(np.float32)

    t_mean, t_amp, t_phase = TEMP_PARAMS[city]
    t_annual  = t_mean + t_amp * np.sin(2 * np.pi * (doy - 90 + t_phase * 30) / 365)
    t_diurnal = 2.0 * np.sin(2 * np.pi * (hours - 4) / 24)
    temp      = np.clip((t_annual + t_diurnal + np.random.normal(0, 0.5, n)), 15.0, 45.0).astype(np.float32)
    return precip, temp


# ─────────────────────────────────────────────────────────
# STAGE 2C: TRAFFIC PROFILE
# ─────────────────────────────────────────────────────────

TRAFFIC_HOURLY = np.array([
    0.20, 0.18, 0.15, 0.14, 0.15, 0.22,
    0.38, 0.75, 0.88, 0.85, 0.70, 0.55,
    0.50, 0.52, 0.55, 0.60, 0.82, 0.90,
    0.95, 0.92, 0.85, 0.70, 0.50, 0.30,
])

def traffic_index(hours: np.ndarray, city: str, is_metro_zone: bool = False) -> np.ndarray:
    idx = TRAFFIC_HOURLY[hours]
    if city == "Tier2":
        idx = idx * 0.60
    elif city == "Bangalore":
        idx = np.where(hours >= 20, idx * 1.10, idx)
    if is_metro_zone and city == "Chennai":
        peak_mask = ((hours >= 7) & (hours <= 10)) | ((hours >= 16) & (hours <= 20))
        idx = np.where(peak_mask, np.minimum(idx + 0.10, 1.0), idx)
    noise = np.random.uniform(-0.03, 0.03, size=len(hours))
    return np.clip(idx + noise, 0.0, 1.0).astype(np.float32)


# ─────────────────────────────────────────────────────────
# STAGE 2D: PAYDAY CYCLE
# ─────────────────────────────────────────────────────────

def payday_arrays(days_of_month: np.ndarray):
    flag = np.zeros(len(days_of_month), dtype=np.int8)
    mult = np.ones(len(days_of_month), dtype=np.float32)
    corp_mask     = (days_of_month >= 1)  & (days_of_month <= 5)
    informal_mask = (days_of_month >= 7)  & (days_of_month <= 10)
    flag[corp_mask]     = 1
    flag[informal_mask] = 2
    mult[corp_mask]     = 1.40
    mult[informal_mask] = 1.25
    return flag, mult


# ─────────────────────────────────────────────────────────
# STAGE 2E: WEATHER DEMAND FACTOR
# ─────────────────────────────────────────────────────────

def weather_demand_factor(precip: np.ndarray, temp: np.ndarray) -> np.ndarray:
    factor = np.ones(len(precip), dtype=np.float32)
    factor[precip > 5.0]  *= 0.70
    factor[temp > 38.0]   *= 1.15
    factor[temp < 20.0]   *= 1.08
    factor[(precip >= 1.0) & (precip <= 5.0)] *= 0.88
    return factor

def traffic_demand_factor(traffic_idx: np.ndarray) -> np.ndarray:
    factor = np.ones(len(traffic_idx), dtype=np.float32)
    factor[traffic_idx > 0.80] *= 0.82
    factor[traffic_idx < 0.25] *= 1.05
    return factor

def ipl_multiplier(ipl_flag: np.ndarray) -> np.ndarray:
    mult = np.ones(len(ipl_flag), dtype=np.float32)
    mult[ipl_flag] = 1.80
    return mult


# ─────────────────────────────────────────────────────────
# MAIN GENERATOR
# ─────────────────────────────────────────────────────────

def generate_dataset() -> None:
    print("=" * 60)
    print("  Hustlr M7 Prophet — Synthetic Dataset Generator")
    print("  ML-DATASET-BLUEPRINT-v1.0")
    print("=" * 60)

    timestamps = pd.date_range(start=START_DATE, end=END_DATE, freq="h", tz="Asia/Kolkata")
    n_ts = len(timestamps)
    print(f"\n[CONFIG] Timestamps : {n_ts:,} hours ({START_DATE} to {END_DATE})")

    zones = generate_zone_ids(N_ZONES)
    print(f"[CONFIG] Zones      : {N_ZONES} (Mumbai:40 Chennai:40 Bangalore:35 Tier2:35)")
    print(f"[CONFIG] Target rows: {n_ts * N_ZONES:,}")
    print(f"[CONFIG] Output     : {OUTPUT_FILE}\n")

    print("[STAGE 2A] Building festival / IPL lookup tables ...")
    fest_mult_arr, ipl_flag_arr = build_festival_lookup(timestamps)
    print(f"          Diwali rows affected : {(fest_mult_arr > 1.0).sum():,}")
    print(f"          IPL evening rows     : {ipl_flag_arr.sum():,}")

    hours_arr   = timestamps.hour.to_numpy(dtype=np.int32)
    dow_arr     = timestamps.day_of_week.to_numpy(dtype=np.int32)
    dom_arr     = timestamps.day.to_numpy(dtype=np.int32)
    salary_flag, payday_mult = payday_arrays(dom_arr)
    ipl_mult_arr = ipl_multiplier(ipl_flag_arr)

    import os
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    # Clear existing file
    open(OUTPUT_FILE, 'w').close()

    header = True
    total_written = 0

    print("\n[STAGE 1–3] Generating zone data...\n")

    for z_idx, zone in enumerate(zones):
        city     = zone["city_type"]
        zone_id  = zone["zone_id"]
        base_sc  = zone["base_scale"]
        is_metro = (city == "Chennai") and (z_idx % 3 == 0)

        b_demand         = base_demand(hours_arr, dow_arr, base_sc)
        precip, temp     = weather_for_zone(timestamps, city)
        w_factor         = weather_demand_factor(precip, temp)
        t_idx            = traffic_index(hours_arr, city, is_metro_zone=is_metro)
        t_factor         = traffic_demand_factor(t_idx)

        demand_final = np.clip(
            b_demand * fest_mult_arr * payday_mult * w_factor * t_factor * ipl_mult_arr,
            0.0, None
        )

        df_zone = pd.DataFrame({
            "ds"                    : timestamps.tz_localize(None),  # Prophet needs naive datetime
            "y"                     : demand_final.round(4),
            "zone_id"               : zone_id,
            "city_type"             : city,
            "festival_multiplier"   : fest_mult_arr.round(4),
            "salary_week_flag"      : salary_flag,
            "ipl_match_flag"        : ipl_flag_arr.astype(np.int8),
            "precipitation_mm"      : precip.round(2),
            "temperature_c"         : temp.round(2),
            "traffic_profile_index" : t_idx.round(4),
            "hour_of_day"           : hours_arr,
            "day_of_week"           : dow_arr,
        })

        for chunk_start in range(0, len(df_zone), CHUNK_ROWS):
            chunk = df_zone.iloc[chunk_start : chunk_start + CHUNK_ROWS]
            chunk.to_csv(OUTPUT_FILE, mode="a", header=header, index=False)
            header = False

        total_written += len(df_zone)
        pct = (z_idx + 1) / N_ZONES * 100
        bar = "#" * int(pct / 2) + "-" * (50 - int(pct / 2))
        print(f"\r  [{bar}] {pct:5.1f}%  Zone {z_idx+1:03d}/{N_ZONES}  ({city})", end="", flush=True)

    print(f"\n\n[DONE] Total rows written : {total_written:,}")
    print(f"[DONE] Output file        : {OUTPUT_FILE}")


def validate_dataset() -> None:
    print("\n[VALIDATE] Running quality checks ...")
    df = pd.read_csv(OUTPUT_FILE, nrows=500_000)

    with open(OUTPUT_FILE, "r") as f:
        row_count = sum(1 for _ in f) - 1
    expected = 26_280 * N_ZONES
    status   = "PASS" if abs(row_count - expected) / expected < 0.02 else "WARN"
    print(f"  Rows: expected ~{expected:,}  |  actual {row_count:,}  [{status}]")

    checks = {
        "festival_multiplier"   : (0.8,  5.0),
        "precipitation_mm"      : (0.0,  200.0),
        "temperature_c"         : (15.0, 45.0),
        "traffic_profile_index" : (0.0,  1.0),
        "hour_of_day"           : (0,    23),
        "day_of_week"           : (0,    6),
    }
    for col, (lo, hi) in checks.items():
        ok = df[col].between(lo, hi).all()
        print(f"  {col:<30} [{lo}, {hi}]  {'PASS' if ok else 'FAIL'}")

    ipl_rate = df["ipl_match_flag"].mean() * 100
    print(f"  IPL flag rate = {ipl_rate:.2f}%  (expected 3–8%)")
    print(f"  Demand stats:\n{df['y'].describe().round(2).to_string()}")
    print("\n[VALIDATE] Complete.")


if __name__ == "__main__":
    generate_dataset()
    validate_dataset()
    print("\n" + "=" * 60)
    print("  prophet_training.csv is ready for Prophet ingestion.")
    print("  Next: python hustlr-ml/scripts/train_model7_prophet.py")
    print("=" * 60)
