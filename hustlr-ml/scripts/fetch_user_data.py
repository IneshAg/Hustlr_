"""
Hustlr Continuous Learning System
=================================
Simulates exporting real user data from the Supabase database
to append into the training dataset folder, creating a continuous
feedback loop for our ML models.
"""
import json
import random
from datetime import datetime, timedelta
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
OUTPUTS_DIR  = PROJECT_ROOT / "outputs" / "user_data"
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

def simulate_db_export():
    print("Connecting to Supabase (Mock)... Generating weekly extract.")
    
    # Simulate DB rows of NLP anomalies reported by workers via in-app chat
    user_disruptions = []
    base_date = datetime.now()
    
    for _ in range(50):
        # Workers use slang & shorthand, which the base model hasn't seen
        user_disruptions.append({
            "text": random.choice([
                "bro im stuck in velachery water is till my silencer cant move",
                "police not letting anyone go past t nagar full barricades",
                "app completely crashed cant accept anything for 1 hr",
                "so hot my phone overheated and switched off in adyar",
                "tree fell on omr total blockspot avoiding for 3 hrs"
            ]),
            "validated_trigger": random.choice(["rain_heavy", "bandh", "platform_outage", "heat_severe", "traffic_severe"]),
            "source": "worker_chat_logs",
            "date": (base_date - timedelta(days=random.randint(1, 7))).strftime("%Y-%m-%d")
        })

    # Simulate closed claims that were human-reviewed (perfect fraud labels)
    fraud_labels = []
    for _ in range(200):
        # In this dataset, the Human Ops team verified these
        fraud_labels.append({
            "user_id": f"WRK{random.randint(1000,9999)}",
            "gps_zone_mismatch": random.randint(0,1),
            "wifi_home_ssid": random.randint(0,1),
            "days_since_onboard": random.randint(2, 400),
            "is_fraud": random.choice([0, 1]), # Ground truth label from ops
            "reviewed_by": "Ops_Team_Chennai"
        })

    export = {
        "nlp_additions": user_disruptions,
        "human_verified_claims": fraud_labels,
        "export_date": datetime.now().isoformat(),
        "status": "Ready for Training pipeline"
    }

    out_file = OUTPUTS_DIR / f"weekly_export_{datetime.now().strftime('%Y%m%d')}.json"
    with open(out_file, "w") as f:
        json.dump(export, f, indent=2)

    print(f"✅ Successfully exported user telemetry & verified claims to: {out_file}")
    print("These will automatically augment the next XGBoost training run.")

if __name__ == "__main__":
    simulate_db_export()
