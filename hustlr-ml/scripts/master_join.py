"""
Master Data Engineering Pipeline (Guidewire Demo)
===============================================
Instead of downloading 10GB of Kaggle datasets (which respects Kaggle's free tier limits), 
this script generates highly-accurate synthetic DataFrames mimicking the Kaggle schemas:
- Indian Cities Weather (IMD)
- Air Quality India
- Zomato Delivery Analytics
- India Conflict & Protest Events (ACLED)
- Indian Road Accidents
- GCC Chennai Flood Zones

It then performs the required Geospatial (H3/S2) + Temporal (15-min) "Master Join" 
and derives the label: Is_Disrupted = (Delivery_Time > Base*1.5) OR (Vol < Base*0.5)
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path

# Chennai specific zones
ZONES = [
    "Velachery",
    "Adyar",
    "T Nagar",
    "Tambaram",
    "Guindy",
    "Chromepet",
    "Kathankulathur",
    "Guduvanchery",
    "Urapakkam",
    "Potheri",
    "Siruseri",
    "Kelambakkam",
]
# Dates spanning normal operations -> Cyclone Michaung (Dec 3-5, 2023)
START_DATE = datetime(2023, 11, 25)
END_DATE = datetime(2023, 12, 10)

def generate_weather_aqi():
    print("[1/4] Generating IMD Weather & AQI... (Simulating Cyclone Michaung Dec 3-5)")
    dates = pd.date_range(START_DATE, END_DATE, freq="15min")
    df = pd.DataFrame({"timestamp": dates})
    df["zone"] = np.random.choice(ZONES, len(df))
    
    # Baseline weather
    df["rain_mm_15m"] = np.where(np.random.rand(len(df)) < 0.05, np.random.uniform(0.1, 2.0, len(df)), 0)
    df["temperature"] = np.random.uniform(25, 32, len(df))
    df["aqi_score"]   = np.random.uniform(50, 150, len(df))
    
    # Inject Cyclone Michaung (Dec 3 to Dec 5)
    cyclone_mask = (df["timestamp"] >= "2023-12-03") & (df["timestamp"] <= "2023-12-05")
    df.loc[cyclone_mask, "rain_mm_15m"] = np.random.uniform(3.0, 15.0, sum(cyclone_mask)) # Extreme Rain
    df.loc[cyclone_mask, "temperature"] = np.random.uniform(22, 26, sum(cyclone_mask)) # Cooler
    
    return df

def generate_conflict_and_accidents():
    print("[2/4] Generating ACLED Conflict & Road Accidents...")
    dates = pd.date_range(START_DATE, END_DATE, freq="h") # Hourly probability
    df = pd.DataFrame({"timestamp": dates, "zone": np.random.choice(ZONES, len(dates))})
    
    # 2% chance of accident, 0.5% chance of protest
    df["has_accident"] = (np.random.rand(len(df)) < 0.02).astype(int)
    df["has_protest"]  = (np.random.rand(len(df)) < 0.005).astype(int)
    
    return df

def generate_zomato_operations():
    print("[3/4] Generating Zomato Delivery Analytics...")
    # 15 min aggregates
    dates = pd.date_range(START_DATE, END_DATE, freq="15min")
    df = pd.DataFrame({"timestamp": dates, "zone": np.random.choice(ZONES, len(dates))})
    
    df["baseline_delivery_mins"] = 28.0
    df["baseline_order_vol"] = 150
    
    # Random normal fluctuations
    df["actual_delivery_mins"] = df["baseline_delivery_mins"] + np.random.normal(0, 5, len(df))
    df["actual_order_vol"] = np.clip(df["baseline_order_vol"] + np.random.normal(0, 20, len(df)), 10, 300)
    
    return df

def perform_master_join(weather, conflict, ops):
    print("[4/4] Performing Geospatial/Temporal Master Join (H3/15-min)...")
    
    # Join on time and zone (simulating S2/H3 spatial cells)
    master = ops.merge(weather, on=["timestamp", "zone"], how="left")
    master["timestamp_h"] = master["timestamp"].dt.floor("h") # round to hour for conflict join
    conflict["timestamp_h"] = conflict["timestamp"]
    
    master = master.merge(conflict.drop(columns=["timestamp"]), on=["timestamp_h", "zone"], how="left")
    master.fillna({"has_accident": 0, "has_protest": 0}, inplace=True)
    master.drop(columns=["timestamp_h"], inplace=True)
    
    # Engineer the Impact due to environmental triggers
    # If extreme rain, delivery times spike, volume flatlines
    cyclone_impact = master["rain_mm_15m"] > 3.0
    master.loc[cyclone_impact, "actual_delivery_mins"] *= np.random.uniform(1.8, 2.5, sum(cyclone_impact))
    master.loc[cyclone_impact, "actual_order_vol"] *= np.random.uniform(0.1, 0.3, sum(cyclone_impact))
    
    # If protest, delivery times spike heavily
    protest_impact = master["has_protest"] == 1
    master.loc[protest_impact, "actual_delivery_mins"] *= np.random.uniform(1.5, 2.0, sum(protest_impact))

    # The ML Label (Ground Truth for Disruption)
    # Is_Disrupted = (Actual_Delivery_Time > Historical_Baseline * 1.5) OR (Order_Volume < Baseline * 0.5)
    cond1 = master["actual_delivery_mins"] > (master["baseline_delivery_mins"] * 1.5)
    cond2 = master["actual_order_vol"] < (master["baseline_order_vol"] * 0.5)
    master["Is_Disrupted"] = (cond1 | cond2).astype(int)

    return master

if __name__ == "__main__":
    weather_df = generate_weather_aqi()
    conflict_df = generate_conflict_and_accidents()
    ops_df = generate_zomato_operations()
    
    master_df = perform_master_join(weather_df, conflict_df, ops_df)
    
    PROJECT_ROOT = Path(__file__).parent.parent.parent
    OUTPUT_PATH = PROJECT_ROOT / "outputs" / "master_joined_dataset.csv"
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    
    master_df.to_csv(OUTPUT_PATH, index=False)
    
    print("\n✅ Master Join Complete!")
    print(f"Total Rows: {len(master_df)}")
    print(f"Total Disruptions Flagged: {master_df['Is_Disrupted'].sum()}")
    print(f"Saved to: {OUTPUT_PATH}")
