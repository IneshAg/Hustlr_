import json
from prophet_model import forecast
from datetime import date, timedelta

PLAN_COVERAGE = {
    "Basic": ["platform_outage", "bandh"],
    "Standard": ["platform_outage", "bandh", "heavy_rain", "heatwave"],
    "Full": ["platform_outage", "bandh", "heavy_rain", "heatwave", "extreme_rain"]
}

PLAN_CAPS = {
    "Basic": 210,
    "Standard": 340,
    "Full": 500
}

TRIGGERS = ["heavy_rain", "extreme_rain", "platform_outage", "bandh", "heatwave"]

# Standard threshold where probability > 0.60 triggers a nudge
NUDGE_THRESHOLD = 0.60

def run_wednesday_nudge(today: date, zone: str, worker_plan_tier: str):
    """
    Called on Wednesdays to forecast the upcoming weekend (next 72 hours).
    Returns a list of nudge payloads.
    """
    nudges = []
    
    covered_triggers = PLAN_COVERAGE.get(worker_plan_tier, [])
    
    for trig in TRIGGERS:
        # Forecast 3 days ahead (72 hours)
        fcst = forecast(trig, zone, forecast_horizon_days=3)
        
        # Check if any day exceeds probability threshold
        high_risk_days = fcst[fcst['probability_above_threshold'] > NUDGE_THRESHOLD]
        
        if not high_risk_days.empty:
            peak_day = high_risk_days.iloc[0]
            pred_date = peak_day['ds'].strftime("%Y-%m-%d")
            prob = peak_day['probability_above_threshold']
            
            trigger_display = trig.replace('_', ' ').title()
            
            if trig in covered_triggers:
                payout = PLAN_CAPS.get(worker_plan_tier, 0)
                msg_cov = f"{trigger_display} expected {pred_date} in your zone. You're covered ? {worker_plan_tier} Shield active. Estimated payout: up to ?{payout}."
                msg_unins = ""
            else:
                # Find the minimum tier that covers this
                req_tier = "Full"
                for t, cov in PLAN_COVERAGE.items():
                    if trig in cov:
                        req_tier = t
                        break
                payout = PLAN_CAPS.get(req_tier, 0)
                msg_cov = ""
                msg_unins = f"{trigger_display} expected {pred_date}. {req_tier} Shield would protect up to ?{payout}. Coverage starts next Monday ? activate quarterly plan now."
                
            payload = {
                "zone": zone,
                "trigger_type": trig,
                "predicted_date": pred_date,
                "probability": float(round(prob, 3)),
                "estimated_payout": payout,
                "message_covered": msg_cov,
                "message_uninsured": msg_unins
            }
            nudges.append(payload)
            
    return nudges
