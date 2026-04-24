import os
import time
import requests
import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime
from prophet import Prophet
from scipy.stats import norm

MODEL_PATH = Path(__file__).parent.parent / "models" / "trained" / "prophet_chennai.pkl"
MODELS_DIR = Path(__file__).parent.parent / "models" / "trained"


def fetch_open_meteo_historical() -> pd.DataFrame:
    """
    Fetch 2018-2024 daily rainfall data for Chennai via Open-Meteo Historical Archive API.
    Lat: 13.0827, Lng: 80.2707
    """
    url = (
        "https://archive-api.open-meteo.com/v1/archive?"
        "latitude=13.0827&longitude=80.2707&"
        "start_date=2018-01-01&end_date=2024-12-31&"
        "daily=precipitation_sum&timezone=Asia/Kolkata"
    )
    
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        dates = data["daily"]["time"]
        precip = data["daily"]["precipitation_sum"]
        
        df = pd.DataFrame({
            "ds": pd.to_datetime(dates),
            "y": precip
        })
    except requests.exceptions.RequestException as e:
        print(f"[Prophet] Open-Meteo API failed: {e}. Using offline synthetic fallback data.")
        # Offline fallback data: Generate dates from 2018 to 2024
        dates = pd.date_range(start="2018-01-01", end="2024-12-31", freq="D")
        
        # Create a synthetic precipitation pattern (peaks during monsoon)
        month = dates.month
        # Monsoon base probability
        is_monsoon = (month >= 6) & (month <= 12)
        
        # Generate random precipitation with higher chance/amount during monsoon
        np.random.seed(42)
        precip = np.where(
            is_monsoon,
            np.random.exponential(scale=5.0, size=len(dates)) * np.random.choice([0, 1], size=len(dates), p=[0.7, 0.3]),
            np.random.exponential(scale=1.0, size=len(dates)) * np.random.choice([0, 1], size=len(dates), p=[0.95, 0.05])
        )
        
        df = pd.DataFrame({
            "ds": dates,
            "y": precip
        })
    
    # Fill any NaNs with 0
    df["y"] = df["y"].fillna(0)
    
    return df

def add_regressors(df: pd.DataFrame) -> pd.DataFrame:
    """Add all external regressors required by the trained Prophet model."""
    # ── Static / approximated regressors ──────────────────────────────────
    df["festival_multiplier"]   = 1.0
    df["precipitation_mm"]      = 0.0
    df["temperature_c"]         = 32.0   # generic baseline
    df["traffic_profile_index"] = 0.5

    dom = df["ds"].dt.day
    # 1 = corporate payday (1–5), 2 = informal payday (7–10), 0 = none
    df["salary_week_flag"] = np.where(
        (dom >= 1) & (dom <= 5), 1,
        np.where((dom >= 7) & (dom <= 10), 2, 0)
    )

    # ── FIX: regressors registered in train_model() but previously missing ─
    # is_monsoon: June–September (months 6–9) — peak rainfall window
    month = df["ds"].dt.month
    df["is_monsoon"]       = ((month >= 6) & (month <= 9)).astype(int)
    # is_cyclone_season: Oct–Dec — Bay of Bengal cyclone window
    df["is_cyclone_season"] = ((month >= 10) & (month <= 12)).astype(int)

    return df

def train_model():
    """
    Train and save the Prophet model using real historical precipitation data.
    """
    print("[Prophet] Fetching historical IMD data via Open-Meteo fallback...")
    df = fetch_open_meteo_historical()
    df = add_regressors(df)
    
    print("[Prophet] Training model...")
    model = Prophet(
        yearly_seasonality=True,
        weekly_seasonality=False,
        changepoint_prior_scale=0.1
    )
    
    model.add_regressor("is_monsoon")
    model.add_regressor("is_cyclone_season")
    
    model.fit(df)
    
    # Ensure directory exists
    MODEL_PATH.parent.mkdir(exist_ok=True)
    import joblib
    joblib.dump(model, MODEL_PATH)
    print(f"[Prophet] Model saved to {MODEL_PATH}")

def load_model():
    import joblib
    if not MODEL_PATH.exists():
        train_model()
    return joblib.load(MODEL_PATH)

ZONE_MODEL_MAP = {
    "adyar":          "model7_prophet_adyar.pkl",
    "velachery":      "model7_prophet_velachery.pkl",
    "tambaram":       "model7_prophet_tambaram.pkl",
    "t_nagar":        "model7_prophet_t_nagar.pkl",
    "anna_nagar":     "model7_prophet_anna_nagar.pkl",
    "porur":          "model7_prophet_porur.pkl",
    "sholinganallur": "model7_prophet_sholinganallur.pkl",
    "guindy":         "model7_prophet_guindy.pkl",
    "perambur":       "model7_prophet_perambur.pkl",
    "chromepet":      "model7_prophet_chromepet.pkl",
}

def _normalize_zone_key(zone_id: str) -> str:
    """
    Convert any zone string to the key used in ZONE_MODEL_MAP.
    'Adyar Dark Store Zone' ??? 'adyar'
    'adyar' ??? 'adyar'
    'ADYAR' ??? 'adyar'
    """
    return (zone_id
        .lower()
        .replace(" dark store zone", "")
        .replace(" ", "_")
        .replace("-", "_")
        .strip())

def load_zone_model(zone_id: str):
    """
    Load the Prophet model for a given zone.
    Falls back to Adyar if zone not found.
    Falls back to fresh training if no pkl exists.
    """
    import joblib
    key      = _normalize_zone_key(zone_id)
    filename = ZONE_MODEL_MAP.get(key, "model7_prophet_adyar.pkl")
    path     = MODELS_DIR / filename

    if path.exists():
        try:
            model = joblib.load(path)
            print(f"[Prophet] Loaded {filename} for zone '{zone_id}'")
            return model
        except Exception as e:
            print(f"[Prophet] Failed to load {filename}: {e}")

    # Fallback ??? try Adyar as generic Chennai model
    adyar_path = MODELS_DIR / "model7_prophet_adyar.pkl"
    if adyar_path.exists():
        print(f"[Prophet] Zone '{zone_id}' not found ??? using Adyar fallback")
        return joblib.load(adyar_path)

    chennai_path = MODELS_DIR / "prophet_chennai.pkl"
    if chennai_path.exists():
        print(f"[Prophet] Zone '{zone_id}' not found ??? using Chennai generic fallback")
        return joblib.load(chennai_path)

    # Last resort ??? train fresh (slow, only on first cold start)
    print(f"[Prophet] No pkl found ??? training fresh model for '{zone_id}'")
    return load_model()

def generate_forecast(zone_id: str, days: int = 7) -> dict:
    """
    Generate forecast for the next `days`.
    Compute disruption_probability using Normal CDF on yhat boundaries.
    """
    model = load_zone_model(zone_id)
    
    future = model.make_future_dataframe(periods=days, freq='D')
    future = add_regressors(future)
    
    forecast = model.predict(future)
    
    # Slice the last `days` segment representing the future
    future_forecast = forecast.tail(days)
    
    results = []
    for _, row in future_forecast.iterrows():
        # Inverse transform the log predictions back to linear demand units
        yhat       = float(np.exp(row["yhat"]))
        yhat_upper = float(np.exp(row["yhat_upper"]))
        yhat_lower = float(np.exp(row["yhat_lower"]))
        
        # Sigma derived from 80% CI interval (z=1.28)
        sigma = (yhat_upper - yhat_lower) / (2 * 1.28)
        
        # We classify disruption based on a severe drop in predicted demand vs normal.
        # Demand threshold for disruption flags (hypothetical low volume threshold).
        baseline_demand = 50.0  # Approx baseline
        
        prob = 0.0
        if sigma > 0:
            # Probability that demand falls below extremely low levels (e.g. 15 units)
            prob = norm.cdf(15.0, loc=yhat, scale=sigma)
        else:
            prob = 1.0 if yhat < 15.0 else 0.0
            
        prob = float(np.clip(prob, 0.0, 1.0))
        
        trigger = "none"
        if prob > 0.05:
            trigger = "heavy_rain"  # or generic 'disruption'
            if prob > 0.3:
                trigger = "extreme_rain"
                
        results.append({
            "date": row["ds"].strftime("%Y-%m-%d"),
            "predicted_demand_units": round(yhat, 2),
            "disruption_probability": round(prob, 4),
            "trigger_type": trigger,
            "expected_payout_standard_shield": 40.0 if trigger != "none" else 0.0
        })
        
    return {
        "zone_id": zone_id,
        "forecasts": results
    }
