from __future__ import annotations

import csv
import io
import json
import os
import ssl
import urllib.parse
import urllib.request
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "external_data"
ENV_FILES = [
    PROJECT_ROOT / "hustlr-backend" / ".env.local",
    PROJECT_ROOT / "hustlr-backend" / ".env",
]

OPENCITY_RAINFALL_URL = (
    "https://newdata.opencity.in/dataset/256d1a20-adf5-4e3a-ae18-27664339117a/"
    "resource/3086f865-a04c-431e-815d-105ae658871f/download/"
    "e5c275eb-a4f2-4412-9677-73654e8f5f4d.csv"
)
CITY_CONFIG = {
    "chennai": {"label": "Chennai", "lat": 13.0827, "lon": 80.2707, "country": "IN"},
    "mumbai": {"label": "Mumbai", "lat": 19.0760, "lon": 72.8777, "country": "IN"},
    "bengaluru": {"label": "Bengaluru", "lat": 12.9716, "lon": 77.5946, "country": "IN"},
    "kolkata": {"label": "Kolkata", "lat": 22.5726, "lon": 88.3639, "country": "IN"},
}
OPENAQ_LOCATIONS_URL = "https://api.openaq.org/v3/locations?country={country}&city={city}&limit=25"
OPENAQ_MEASUREMENTS_URL = (
    "https://api.openaq.org/v3/sensors/{sensor_id}/measurements"
    "?limit=1000&date_from=2024-01-01T00%3A00%3A00Z&date_to=2025-12-31T23%3A59%3A59Z"
)


def read_env_key(name: str) -> str | None:
    for env_path in ENV_FILES:
        if not env_path.is_file():
            continue
        for line in env_path.read_text(encoding="utf-8").splitlines():
            if not line or line.lstrip().startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key.strip() == name:
                return value.strip()
    return os.environ.get(name)


def fetch_text(url: str, headers: dict[str, str] | None = None, insecure_ssl: bool = False) -> str:
    req = urllib.request.Request(url, headers=headers or {"User-Agent": "HustlrML/1.0"})
    context = ssl._create_unverified_context() if insecure_ssl else None
    with urllib.request.urlopen(req, context=context, timeout=60) as resp:
        return resp.read().decode("utf-8")


def save_text(text: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def open_meteo_air_url(lat: float, lon: float) -> str:
    return (
        "https://air-quality-api.open-meteo.com/v1/air-quality"
        f"?latitude={lat}&longitude={lon}"
        "&hourly=pm2_5,pm10,nitrogen_dioxide,sulphur_dioxide,ozone,european_aqi"
        "&start_date=2024-01-01&end_date=2025-12-31&timezone=Asia%2FKolkata"
    )


def open_meteo_weather_url(lat: float, lon: float) -> str:
    return (
        "https://archive-api.open-meteo.com/v1/archive"
        f"?latitude={lat}&longitude={lon}"
        "&start_date=2024-01-01&end_date=2025-12-31"
        "&daily=temperature_2m_mean,precipitation_sum,rain_sum"
        "&timezone=Asia%2FKolkata"
    )


def download_rainfall() -> Path:
    try:
        text = fetch_text(OPENCITY_RAINFALL_URL)
    except Exception:
        text = fetch_text(OPENCITY_RAINFALL_URL, insecure_ssl=True)
    out = RAW_DIR / "chennai_rainfall_1991_2023.csv"
    save_text(text, out)
    return out


def download_open_meteo_air() -> Path:
    merged: dict[str, dict[str, object]] = {}
    for slug, cfg in CITY_CONFIG.items():
        text = fetch_text(open_meteo_air_url(cfg["lat"], cfg["lon"]))
        out = RAW_DIR / f"{slug}_openmeteo_air_quality_2024_2025.json"
        save_text(text, out)
        merged[slug] = json.loads(text)
    merged_out = RAW_DIR / "all_cities_openmeteo_air_quality_2024_2025.json"
    save_text(json.dumps(merged, indent=2), merged_out)
    return merged_out


def download_open_meteo_weather() -> Path:
    merged: dict[str, dict[str, object]] = {}
    for slug, cfg in CITY_CONFIG.items():
        text = fetch_text(open_meteo_weather_url(cfg["lat"], cfg["lon"]))
        out = RAW_DIR / f"{slug}_openmeteo_weather_2024_2025.json"
        save_text(text, out)
        merged[slug] = json.loads(text)
    merged_out = RAW_DIR / "all_cities_openmeteo_weather_2024_2025.json"
    save_text(json.dumps(merged, indent=2), merged_out)
    return merged_out


def download_openaq() -> list[tuple[Path, Path]] | None:
    api_key = read_env_key("OPENAQ_API_KEY")
    if not api_key:
        return None

    headers = {
        "User-Agent": "HustlrML/1.0",
        "X-API-Key": api_key,
    }
    outputs: list[tuple[Path, Path]] = []
    for slug, cfg in CITY_CONFIG.items():
        location_url = OPENAQ_LOCATIONS_URL.format(
            country=urllib.parse.quote(str(cfg["country"])),
            city=urllib.parse.quote(str(cfg["label"])),
        )
        try:
            locations_text = fetch_text(location_url, headers=headers)
        except Exception:
            continue
        locations_out = RAW_DIR / f"openaq_{slug}_locations.json"
        save_text(locations_text, locations_out)

        payload = json.loads(locations_text)
        sensors = []
        for result in payload.get("results", []):
            for sensor in result.get("sensors", []):
                sensor_id = sensor.get("id")
                parameter = ((sensor.get("parameter") or {}).get("name") or "").lower()
                if sensor_id and parameter in {"pm25", "pm10", "no2", "so2", "o3"}:
                    sensors.append((sensor_id, parameter))

        rows: list[dict[str, str | int | float]] = []
        seen = set()
        for sensor_id, parameter in sensors[:10]:
            url = OPENAQ_MEASUREMENTS_URL.format(sensor_id=sensor_id)
            try:
                text = fetch_text(url, headers=headers)
                data = json.loads(text)
            except Exception:
                continue
            for item in data.get("results", []):
                stamp = ((item.get("period") or {}).get("datetimeFrom", {}) or {}).get("utc")
                value = item.get("value")
                if stamp is None or value is None:
                    continue
                key = (sensor_id, stamp)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(
                    {
                        "sensor_id": sensor_id,
                        "parameter": parameter,
                        "timestamp_utc": stamp,
                        "value": value,
                        "city": cfg["label"],
                    }
                )

        measurements_out = RAW_DIR / f"openaq_{slug}_measurements.csv"
        measurements_out.parent.mkdir(parents=True, exist_ok=True)
        with measurements_out.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["city", "sensor_id", "parameter", "timestamp_utc", "value"])
            writer.writeheader()
            writer.writerows(rows)
        outputs.append((locations_out, measurements_out))
    return outputs


def main() -> None:
    print("Downloading external datasets...")
    rain = download_rainfall()
    print(f"Saved rainfall -> {rain}")
    air = download_open_meteo_air()
    print(f"Saved air quality -> {air}")
    weather = download_open_meteo_weather()
    print(f"Saved weather -> {weather}")
    aq = download_openaq()
    if aq is None:
        print("Skipped OpenAQ download: OPENAQ_API_KEY missing")
    else:
        print(f"Saved OpenAQ city bundles -> {len(aq)}")


if __name__ == "__main__":
    main()
