"""
m3_fraud_detector.py
Hustlr M3++ Composite Fraud Detection Engine
Phase 3 — Scale & Optimise | Code Crafters | DEVTrails 2026
Risk Score: 0.0 (clean) → 1.0 (certain fraud)
Thresholds: < 0.30 AUTO_APPROVE | 0.30–0.59 MANUAL_REVIEW | ≥ 0.60 AUTO_REJECT
"""
import math
import numpy as np
import pandas as pd
from dataclasses import dataclass, field
from typing import Optional
# ── Constants ──────────────────────────────────────────────────────────────
VELOCITY_SOFT_THRESHOLD   = 50.0    # km/h — suspicious
VELOCITY_HARD_THRESHOLD   = 80.0    # km/h — likely spoof
VELOCITY_IMPOSSIBLE       = 200.0   # km/h — instant reject
GPS_MOTION_THRESHOLD_M    = 10.0    # metres per second — GPS says "moving"
IMU_STATIC_THRESHOLD      = 1.2     # m/s² RMS — IMU says "static"
BATTERY_LOW_TEMP          = 30.0    # °C below = cold emulator signal
BATTERY_HIGH_TEMP         = 55.0    # °C above = thermal runaway (emulator bug)
BATTERY_SESSION_MIN       = 30.0    # minutes before heat check applies
RAIN_CLAIM_PRECIP_NONE    = 1.0     # mm — claimed rain but logged dry
RAIN_CLAIM_PRECIP_LIGHT   = 5.0     # mm — claimed heavy rain but logged light
RISK_THRESHOLDS = {
    "AUTO_APPROVE":  0.30,
    "MANUAL_REVIEW": 0.60,
    "AUTO_REJECT":   0.60,   # ≥ 0.60 → auto reject
}
@dataclass
class ClaimTelemetry:
    """Single claim's telemetry bundle passed to the detector."""
    claim_id:           str
    worker_id:          str
    disruption_type:    str           # "heavy_rain" | "heatwave" | "internet_blackout" | ...
    claim_timestamp:    pd.Timestamp
    gps_pings:          list          # list of (lat, lon, timestamp) tuples
    imu_acc_rms:        list          # list of float: accelerometer RMS per 1-second window
    battery_temps_c:    list          # list of float: battery temp readings during session
    session_duration_m: float         # session length in minutes
    claim_lat:          float
    claim_lon:          float
@dataclass
class FraudDecision:
    claim_id:     str
    risk_score:   float
    decision:     str
    flags:        list = field(default_factory=list)
    details:      dict = field(default_factory=dict)
# ── Haversine Distance ─────────────────────────────────────────────────────
def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in kilometres."""
    R = 6371.0
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    Δφ = math.radians(lat2 - lat1)
    Δλ = math.radians(lon2 - lon1)
    a = math.sin(Δφ/2)**2 + math.cos(φ1)*math.cos(φ2)*math.sin(Δλ/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
# ── Vector 1: Teleportation / Velocity Check ──────────────────────────────
def check_velocity(pings: list) -> tuple:
    """
    Returns (max_velocity_kmh, risk_delta, flags).
    Pings: [(lat, lon, pd.Timestamp), ...]
    """
    if len(pings) < 2:
        return 0.0, 0.0, []
    max_v = 0.0
    flags = []
    for i in range(1, len(pings)):
        lat1, lon1, t1 = pings[i-1]
        lat2, lon2, t2 = pings[i]
        dist_km = haversine_km(lat1, lon1, lat2, lon2)
        dt_h    = (t2 - t1).total_seconds() / 3600.0
        if dt_h <= 0:
            continue
        v = dist_km / dt_h
        max_v = max(max_v, v)
    risk = 0.0
    if max_v > VELOCITY_IMPOSSIBLE:
        flags.append(f"IMPOSSIBLE_VELOCITY:{max_v:.1f}km/h")
        risk = 1.0  # instant reject signal
    elif max_v > VELOCITY_HARD_THRESHOLD:
        flags.append(f"HARD_VELOCITY_FLAG:{max_v:.1f}km/h>80")
        risk = 0.60
    elif max_v > VELOCITY_SOFT_THRESHOLD:
        flags.append(f"SOFT_VELOCITY_FLAG:{max_v:.1f}km/h>50")
        risk = 0.25
    return max_v, risk, flags
# ── Vector 2: IMU Contradiction Score ─────────────────────────────────────
def check_imu_contradiction(pings: list, imu_rms: list) -> tuple:
    """
    Compare GPS-implied motion windows with IMU RMS.
    Returns (contradiction_ratio, risk_delta, flags).
    """
    if not pings or not imu_rms:
        return 0.0, 0.0, []
    n_windows        = min(len(pings) - 1, len(imu_rms))
    contradiction_ct = 0
    for i in range(n_windows):
        lat1, lon1, t1 = pings[i]
        lat2, lon2, _  = pings[i+1]
        dist_m  = haversine_km(lat1, lon1, lat2, lon2) * 1000
        gps_spd = dist_m / max((pings[i+1][2]-t1).total_seconds(), 0.01)
        gps_moving = gps_spd > GPS_MOTION_THRESHOLD_M
        imu_static  = imu_rms[i] < IMU_STATIC_THRESHOLD
        if gps_moving and imu_static:
            contradiction_ct += 1
    ratio = contradiction_ct / max(n_windows, 1)
    risk  = 0.0
    flags = []
    if ratio > 0.50:
        flags.append(f"IMU_CONTRADICTION:{ratio*100:.0f}%_windows")
        risk = 0.55
    elif ratio > 0.25:
        flags.append(f"IMU_PARTIAL_CONTRADICTION:{ratio*100:.0f}%_windows")
        risk = 0.20
    return ratio, risk, flags
# ── Vector 3: Battery Heat Signature ──────────────────────────────────────
def check_battery_heat(temps: list, session_min: float) -> tuple:
    """
    Returns (avg_temp, risk_delta, flags).
    """
    if not temps or session_min < BATTERY_SESSION_MIN:
        return 0.0, 0.0, []
    avg_temp = float(np.mean(temps))
    risk     = 0.0
    flags    = []
    if avg_temp < BATTERY_LOW_TEMP:
        flags.append(f"COLD_BATTERY:{avg_temp:.1f}°C<30_after_{session_min:.0f}min")
        risk = 0.35
    if avg_temp > BATTERY_HIGH_TEMP:
        flags.append(f"EMULATOR_OVERHEAT:{avg_temp:.1f}°C>55")
        risk += 0.20
    return avg_temp, risk, flags
# ── Vector 4: Weather Cross-Check ─────────────────────────────────────────
def check_weather_claim(
    disruption_type: str,
    claim_lat:  float,
    claim_lon:  float,
    claim_ts:   pd.Timestamp,
    weather_df: pd.DataFrame,   # hustlr_10yr_dataset.csv pre-loaded or slice
) -> tuple:
    """
    Cross-reference claim against logged weather.
    weather_df columns: zone_id, timestamp, precip_mm, temp_c
    Returns (logged_precip, risk_delta, flags).
    """
    flags = []
    risk  = 0.0
    if disruption_type not in ("heavy_rain", "heatwave"):
        return None, 0.0, []
    try:
        import h3
        zone_id = h3.geo_to_h3(claim_lat, claim_lon, resolution=9)
        # Round to nearest hour for lookup
        claim_hour = claim_ts.floor("h")
        row = weather_df[
            (weather_df["zone_id"] == zone_id) &
            (weather_df["timestamp"] == claim_hour)
        ]
    except Exception:
        # h3 not available or zone not in dataset — skip with no flag
        return None, 0.0, ["WEATHER_LOOKUP_UNAVAILABLE"]
    if row.empty:
        return None, 0.0, ["ZONE_NOT_IN_LOG"]
    if disruption_type == "heavy_rain":
        logged_precip = float(row["precip_mm"].values[0])
        if logged_precip < RAIN_CLAIM_PRECIP_NONE:
            flags.append(f"DRY_DAY_CLAIM:logged={logged_precip:.2f}mm")
            risk = 0.75
        elif logged_precip < RAIN_CLAIM_PRECIP_LIGHT:
            flags.append(f"LIGHT_RAIN_CLAIM:logged={logged_precip:.2f}mm")
            risk = 0.30
        return logged_precip, risk, flags
    if disruption_type == "heatwave":
        logged_temp = float(row["temp_c"].values[0])
        if logged_temp < 35.0:
            flags.append(f"MILD_TEMP_CLAIM:logged={logged_temp:.1f}°C")
            risk = 0.50
        return logged_temp, risk, flags
    return None, 0.0, []
# ── Composite Scorer ───────────────────────────────────────────────────────
def score_claim(
    telemetry:  ClaimTelemetry,
    weather_df: Optional[pd.DataFrame] = None,
) -> FraudDecision:
    """
    Run all four detection vectors and combine into composite risk score.
    Vectors are weighted but capped at 1.0 total.
    """
    total_risk = 0.0
    all_flags  = []
    details    = {}
    # Vector 1: Velocity
    max_v, r1, f1 = check_velocity(telemetry.gps_pings)
    total_risk += r1
    all_flags.extend(f1)
    details["max_velocity_kmh"] = round(max_v, 2)
    details["velocity_risk"]    = round(r1, 3)
    # Vector 2: IMU
    imu_ratio, r2, f2 = check_imu_contradiction(
        telemetry.gps_pings, telemetry.imu_acc_rms
    )
    total_risk += r2
    all_flags.extend(f2)
    details["imu_contradiction_ratio"] = round(imu_ratio, 3)
    details["imu_risk"]                = round(r2, 3)
    # Vector 3: Battery Heat
    avg_temp, r3, f3 = check_battery_heat(
        telemetry.battery_temps_c, telemetry.session_duration_m
    )
    total_risk += r3
    all_flags.extend(f3)
    details["avg_battery_temp_c"] = round(avg_temp, 2)
    details["battery_risk"]       = round(r3, 3)
    # Vector 4: Weather Cross-Check
    if weather_df is not None:
        logged_val, r4, f4 = check_weather_claim(
            telemetry.disruption_type,
            telemetry.claim_lat, telemetry.claim_lon,
            telemetry.claim_timestamp, weather_df,
        )
        total_risk += r4
        all_flags.extend(f4)
        details["logged_weather_value"] = logged_val
        details["weather_risk"]         = round(r4, 3)
    # Clamp to [0.0, 1.0]
    final_risk = round(min(total_risk, 1.0), 4)
    if final_risk >= RISK_THRESHOLDS["AUTO_REJECT"]:
        decision = "AUTO_REJECT"
    elif final_risk >= RISK_THRESHOLDS["AUTO_APPROVE"]:
        decision = "MANUAL_REVIEW"
    else:
        decision = "AUTO_APPROVE"
    return FraudDecision(
        claim_id=telemetry.claim_id,
        risk_score=final_risk,
        decision=decision,
        flags=all_flags,
        details=details,
    )
# ── Demo Runner ────────────────────────────────────────────────────────────
if __name__ == "__main__":
    now = pd.Timestamp.now(tz="Asia/Kolkata").floor("h")
    # Simulate a fraudulent claim: GPS teleports, IMU is static, cold device
    fake_claim = ClaimTelemetry(
        claim_id="CLM-DEMO-001",
        worker_id="WKR-8821",
        disruption_type="heavy_rain",
        claim_timestamp=now,
        gps_pings=[
            (13.0827,  80.2707, now),
            (13.0897,  80.2750, now + pd.Timedelta(seconds=5)),   # legit
            (13.1900,  80.3200, now + pd.Timedelta(seconds=10)),  # 15km in 5s = TELEPORT
        ],
        imu_acc_rms=[0.85, 0.72, 0.91],  # all below 1.2 m/s² = static while GPS "moves"
        battery_temps_c=[24.1, 24.3, 24.0, 24.2],  # ice cold = emulator
        session_duration_m=45.0,
        claim_lat=13.0827,
        claim_lon=80.2707,
    )
    result = score_claim(fake_claim, weather_df=None)  # pass loaded df in production
    print(f"\n[M3++] Claim     : {result.claim_id}")
    print(f"[M3++] Risk Score: {result.risk_score:.4f}")
    print(f"[M3++] Decision  : {result.decision}")
    print(f"[M3++] Flags     : {result.flags}")
    print(f"[M3++] Details   : {result.details}")
