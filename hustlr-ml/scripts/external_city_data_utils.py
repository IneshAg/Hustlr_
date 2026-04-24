from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[2]
EXTERNAL_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "external_data"

CITY_FILE_SLUG = {
    "Chennai": "chennai",
    "Mumbai": "mumbai",
    "Bangalore": "bengaluru",
    "Bengaluru": "bengaluru",
    "Kolkata": "kolkata",
    "Tier2": None,
    "Tier 1": "chennai",
}


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def city_slug(city: str) -> str | None:
    return CITY_FILE_SLUG.get(str(city), str(city).strip().lower() or None)


def load_city_air_frame(city: str) -> pd.DataFrame:
    slug = city_slug(city)
    if not slug:
        return pd.DataFrame()
    path = EXTERNAL_DIR / f"{slug}_openmeteo_air_quality_2024_2025.json"
    if not path.is_file():
        return pd.DataFrame()
    payload = _load_json(path)
    hourly = pd.DataFrame(payload.get("hourly", {})).copy()
    if hourly.empty or "time" not in hourly.columns:
        return pd.DataFrame()
    hourly = hourly.rename(columns={"time": "ds"})
    hourly["ds"] = pd.to_datetime(hourly["ds"], errors="coerce")
    try:
        hourly["ds"] = hourly["ds"].dt.tz_localize(None)
    except TypeError:
        pass
    if "european_aqi" in hourly.columns:
        hourly["european_aqi"] = pd.to_numeric(hourly["european_aqi"], errors="coerce")
    return hourly


def load_city_weather_frame(city: str) -> pd.DataFrame:
    slug = city_slug(city)
    if not slug:
        return pd.DataFrame()
    path = EXTERNAL_DIR / f"{slug}_openmeteo_weather_2024_2025.json"
    if not path.is_file():
        return pd.DataFrame()
    payload = _load_json(path)
    daily = pd.DataFrame(payload.get("daily", {}))
    if daily.empty or "time" not in daily.columns:
        return pd.DataFrame()
    daily["date"] = pd.to_datetime(daily["time"], errors="coerce")
    for col in ("precipitation_sum", "rain_sum", "temperature_2m_mean"):
        if col in daily.columns:
            daily[col] = pd.to_numeric(daily[col], errors="coerce")
    return daily


def recent_city_aqi_default(city: str, fallback: float = 70.0) -> float:
    frame = load_city_air_frame(city)
    if frame.empty or "european_aqi" not in frame.columns:
        return fallback
    vals = frame["european_aqi"].dropna().astype(float).tolist()
    if not vals:
        return fallback
    tail = vals[-24:] if len(vals) >= 24 else vals
    return float(round(sum(tail) / len(tail), 2))


def city_environment_penalty(city: str) -> float:
    weather = load_city_weather_frame(city)
    air = load_city_air_frame(city)
    penalty = 0.0
    if not weather.empty:
        precip = weather.get("precipitation_sum")
        if precip is not None:
            penalty -= min(float(precip.dropna().mean()) / 20.0, 2.2)
    if not air.empty and "european_aqi" in air.columns:
        vals = air["european_aqi"].dropna().astype(float)
        if not vals.empty:
            penalty -= min(float(vals.mean()) / 120.0, 1.8)
    return penalty
