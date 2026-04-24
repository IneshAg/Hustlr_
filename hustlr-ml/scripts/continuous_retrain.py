"""
continuous_retrain.py — MLOps script for Continuous Batch Retraining (Phase 4).

This script simulates the MLOps pipeline that fetches real telemetry and claim 
data from the live Supabase database, blends it with synthetic data (to prevent 
cold-start forgetting), retrains the IsolationForest anomaly detection model, 
and горячего-loads (hot-swaps) the .pkl file for the FastAPI service.

Run this as a weekly cron job.
"""

import os
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json

import pandas as pd
from supabase import create_client, Client
from dotenv import load_dotenv

# Add the parent directory to the path so we can import fraud_model
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fraud_model import (
    MODEL_PATH,
    CONTAMINATION_RATE,
    RANDOM_STATE,
    generate_training_data,
    prepare_features,
)
from sklearn.ensemble import IsolationForest
import joblib

# Load environment variables
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'hustlr-backend', '.env'))

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
TARGET_SAMPLES = 50_000
REAL_DATA_WEIGHT = 0.5  # Max 50% of the training set can be real data until we scale

def fetch_real_claims(supabase: Client, days=30) -> pd.DataFrame:
    """Fetch the last 30 days of real claims from the production database."""
    print(f"[MLOps] Fetching real claim telemetry from past {days} days...")
    
    past_date = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    
    # In a real pipeline, we'd paginate. Limiting to 100k here.
    res = supabase.table('claims').select(
        'id, user_id, zone, created_at, trigger_type, fps_signals, users!claims_user_id_fkey(created_at)'
    ).gte('created_at', past_date).limit(100_000).execute()
    
    data = res.data
    if not data:
        print("[MLOps] No real claims found in this window. Using synthetic baseline.")
        return pd.DataFrame()
        
    print(f"[MLOps] Fetched {len(data)} real claim events.")
    
    # Transform raw DB rows into the expected Feature Schema
    rows = []
    
    # Sort data to easily calculate simultaneous claims
    data.sort(key=lambda x: x['created_at'])
    
    for record in data:
        claim_ts = int(datetime.fromisoformat(record['created_at'].replace('Z', '+00:00')).timestamp())
        
        user_data = record.get('users', {})
        if isinstance(user_data, list):
            user_data = user_data[0] if user_data else {}
            
        user_created_at = user_data.get('created_at')
        if user_created_at:
            install_ts = int(datetime.fromisoformat(user_created_at.replace('Z', '+00:00')).timestamp())
            app_install_days = install_ts // 86400
            days_since_onboard = (claim_ts - install_ts) // 86400
        else:
            app_install_days = 19400
            days_since_onboard = 30
            
        # Parse signals (device hash approximations for the model)
        fps_signals = record.get('fps_signals') or {}
        device_hash = str(record['user_id'])  # Approximate hash using UUID
        hardware_hash = str(record['user_id'])
        
        if isinstance(fps_signals, str):
            try:
                fps_signals = json.loads(fps_signals)
            except:
                pass
                
        if isinstance(fps_signals, dict) and 'shared_device_cluster' in fps_signals:
            # If they are part of a cluster, we can simulate an anomaly
            device_hash = "CLUSTER_" + device_hash
            
        rows.append({
            "zone_grid_id": record.get('zone', 'TN_UNKNOWN'),
            "unix_timestamp": claim_ts,
            "simultaneous_claims_zone_15min": 1, # Will be calculated below
            "device_subnet_hash": device_hash,
            "device_hardware_id_hash": hardware_hash,
            "app_install_timestamp_days": max(0, app_install_days),
            "days_since_onboarding": max(0, days_since_onboard),
            "referral_chain_depth": 0, # Assuming 0 for now as it's not in DB
            "claim_latency_seconds": 300, # Approx 5 mins standard latency
            "orders_during_disruption_window": 0, # Genuine workers stop taking orders
        })
        
    df = pd.DataFrame(rows)
    
    # Calculate rolling simultaneous claims per zone
    df['datetime'] = pd.to_datetime(df['unix_timestamp'], unit='s')
    df = df.sort_values('datetime')
    
    def count_recent(group):
        # Count rows in the rolling 15 min window for this zone
        rolling_count = group.rolling('15min', on='datetime')['zone_grid_id'].count()
        return rolling_count
        
    df['simultaneous_claims_zone_15min'] = df.groupby('zone_grid_id', group_keys=False).apply(count_recent).values
    df = df.drop(columns=['datetime'])
    
    return df

def run_pipeline():
    print("=== Hustlr Phase 4 Continuous Batch Retraining Pipeline ===")
    
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("[MLOps] WARNING: Supabase credentials not found. Generating purely synthetic model.")
        df_real = pd.DataFrame()
    else:
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
        df_real = fetch_real_claims(supabase, days=30)
        
    # Generate the baseline synthetic dataset
    print("[MLOps] Generating synthetic baseline to prevent cold-start forgetting...")
    df_synth = generate_training_data(n_samples=TARGET_SAMPLES)
    
    if df_real.empty:
        df_final = df_synth
        print(f"[MLOps] Proceeding with {len(df_final)} synthetic samples.")
    else:
        # Blend the real data with synthetic data
        n_real = len(df_real)
        max_real_allowed = int(TARGET_SAMPLES * REAL_DATA_WEIGHT)
        
        if n_real > max_real_allowed:
            print(f"[MLOps] Downsampling {n_real} real samples to {max_real_allowed} limit.")
            df_real_subset = df_real.sample(n=max_real_allowed, random_state=RANDOM_STATE)
        else:
            df_real_subset = df_real
            
        n_synth_needed = TARGET_SAMPLES - len(df_real_subset)
        df_synth_subset = df_synth.sample(n=n_synth_needed, random_state=RANDOM_STATE)
        
        df_final = pd.concat([df_real_subset, df_synth_subset], ignore_index=True)
        # Shuffle
        df_final = df_final.sample(frac=1, random_state=RANDOM_STATE).reset_index(drop=True)
        print(f"[MLOps] Blended Dataset: {len(df_real_subset)} real ({len(df_real_subset)/TARGET_SAMPLES*100:.1f}%) + {n_synth_needed} synthetic.")

    X = prepare_features(df_final)
    
    print(f"[MLOps] Training new Isolation Forest on {len(X):,} samples...")
    model = IsolationForest(
        n_estimators=200,
        max_samples=256,
        contamination=CONTAMINATION_RATE,
        random_state=RANDOM_STATE,
        n_jobs=-1,
    )
    model.fit(X)
    
    # Save safely with atomic rename
    temp_path = MODEL_PATH.with_name(MODEL_PATH.name + ".tmp")
    
    joblib.dump(
        {
            "model": model,
            "trained_at": datetime.now(timezone.utc).isoformat(),
            "n_samples": len(X),
            "real_samples_included": len(df_real) if not df_real.empty else 0,
            "contamination": CONTAMINATION_RATE,
            "threshold": 0.65, # Keep constant to not break downstream logic
            "feature_version": "1.0.0",
        },
        temp_path,
    )
    
    # Atomic replace (hot swap in production without taking down the FastAPI worker)
    os.replace(temp_path, MODEL_PATH)
    print(f"[MLOps] Hot-swap complete: New model deployed to {MODEL_PATH}")
    print("=== Retraining Pipeline Complete ===")

if __name__ == "__main__":
    run_pipeline()
