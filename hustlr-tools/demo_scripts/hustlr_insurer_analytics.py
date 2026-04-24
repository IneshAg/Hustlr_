"""
hustlr_insurer_analytics.py
M7 Prophet → Insurer Dashboard Predictive Metrics
Phase 3 — Scale & Optimise | Code Crafters | DEVTrails 2026
Requires:
  - Fitted Prophet model (from hustlr_hybrid_engine.py dataset)
  - hustlr_10yr_dataset.csv (for zone-level weather lookup)
  - policy_config.json (premium per worker per hour, claim trigger amounts)
"""
import numpy as np
import pandas as pd
from prophet import Prophet
from dataclasses import dataclass
from typing import Optional
# ── Policy Config ──────────────────────────────────────────────────────────
# These numbers are illustrative for the demo. Replace with Guidewire policy data.
POLICY = {
    "premium_inr_per_worker_per_hour": 4.50,     # ₹ 4.50/hr collected per active worker
    "payout_heavy_rain_inr":           450.0,    # ₹ 450 per 1-hour heavy_rain disruption
    "payout_heatwave_inr":             350.0,    # ₹ 350 per heatwave hour
    "active_workers_per_zone":         85,        # avg workers enrolled per zone
    "rain_suppressor_demand":          0.70,      # demand drops to 70% in heavy rain
    "rain_claim_conversion_rate":      0.65,      # 65% of workers in rain zones file claims
}
@dataclass
class ZoneForecast:
    zone_id:             str
    city:                str
    period_start:        pd.Timestamp
    period_end:          pd.Timestamp
    predicted_demand:    float     # units (from Prophet yhat)
    predicted_precip_mm: float     # mm/hr average over period
    supply_gap_ratio:    float     # fraction of expected demand that won't be met
    expected_claims:     int       # estimated number of claims to be filed
    expected_claims_inr: float     # ₹  total payout liability
    expected_premiums:   float     # ₹  total premiums for same period
    predicted_loss_ratio:float     # claims / premiums
    risk_band:           str       # "GREEN" | "AMBER" | "RED"
# ── Loss Ratio Calculator ─────────────────────────────────────────────────
def compute_zone_loss_ratio(
    zone_id:        str,
    city:           str,
    forecast_df:    pd.DataFrame,  # Prophet output: ds, yhat, yhat_lower, yhat_upper + regressors
    hours_ahead:    int = 168,     # 7 days = 168 hours
) -> ZoneForecast:
    """
    For a given zone's 7-day Prophet forecast, compute loss ratio.
    forecast_df must contain:
      - ds:         datetime (hourly)
      - yhat:       log(demand) — inverse-transform to get demand_units
      - precip_mm:  forecasted precipitation (from regressor)
      - salary_week_flag: (0,1,2) payday cycle
    """
    future_slice = forecast_df.head(hours_ahead).copy()
    period_start = future_slice["ds"].iloc[0]
    period_end   = future_slice["ds"].iloc[-1]
    # Inverse-transform: Prophet trained on log(demand_units)
    future_slice["demand_units"] = np.exp(future_slice["yhat"])
    # Identify high-rain hours (precip_mm > 5.0 → heavy_rain threshold)
    if "precip_mm" in future_slice.columns:
        rain_hours = future_slice["precip_mm"] > 5.0
    else:
        # Fallback: infer from demand suppression pattern
        avg_demand = future_slice["demand_units"].mean()
        rain_hours = future_slice["demand_units"] < (avg_demand * 0.75)
    n_rain_hours = int(rain_hours.sum())
    n_total_hrs  = len(future_slice)
    # ── Supply Gap Computation ─────────────────────────────────────────────
    # Gap = how much demand is lost due to rain (workers stop delivering)
    nominal_demand = future_slice["demand_units"].mean() / POLICY["rain_suppressor_demand"]
    actual_demand  = future_slice["demand_units"].mean()
    supply_gap     = max(0.0, (nominal_demand - actual_demand) / nominal_demand)
    # ── Claims Liability ───────────────────────────────────────────────────
    # During each rain hour: n_workers × claim_conversion → payout
    expected_claimants = int(
        POLICY["active_workers_per_zone"]
        * POLICY["rain_claim_conversion_rate"]
        * n_rain_hours
    )
    claims_cost = expected_claimants * POLICY["payout_heavy_rain_inr"]
    # ── Premium Revenue ────────────────────────────────────────────────────
    # Premiums collected every hour regardless of weather
    premium_revenue = (
        POLICY["active_workers_per_zone"]
        * POLICY["premium_inr_per_worker_per_hour"]
        * n_total_hrs
    )
    # ── Loss Ratio ─────────────────────────────────────────────────────────
    loss_ratio = claims_cost / max(premium_revenue, 1.0)
    # ── Risk Band ──────────────────────────────────────────────────────────
    if loss_ratio < 0.70:
        risk_band = "GREEN"
    elif loss_ratio < 0.90:
        risk_band = "AMBER"
    else:
        risk_band = "RED"
    return ZoneForecast(
        zone_id             = zone_id,
        city                = city,
        period_start        = period_start,
        period_end          = period_end,
        predicted_demand    = round(actual_demand, 2),
        predicted_precip_mm = round(float(future_slice.get("precip_mm", pd.Series([0])).mean()), 2),
        supply_gap_ratio    = round(supply_gap, 4),
        expected_claims     = expected_claimants,
        expected_claims_inr = round(claims_cost, 2),
        expected_premiums   = round(premium_revenue, 2),
        predicted_loss_ratio= round(loss_ratio, 4),
        risk_band           = risk_band,
    )
# ── Supply Gap Warning System ──────────────────────────────────────────────
def generate_supply_gap_warnings(
    zone_forecasts: list,
    gap_threshold: float = 0.30,
) -> pd.DataFrame:
    """
    Filter zones where supply_gap_ratio > threshold.
    These are zones where demand will significantly exceed available supply —
    an insurer signal to pre-position emergency worker incentives or reinsurance.
    """
    warnings = [
        {
            "zone_id":          z.zone_id,
            "city":             z.city,
            "supply_gap_pct":   round(z.supply_gap_ratio * 100, 1),
            "predicted_rain_mm":z.predicted_precip_mm,
            "loss_ratio":       z.predicted_loss_ratio,
            "risk_band":        z.risk_band,
            "recommended_action": (
                "ACTIVATE_SURGE_INCENTIVE" if z.supply_gap_ratio > 0.50
                else "MONITOR_CLOSELY"
            ),
        }
        for z in zone_forecasts
        if z.supply_gap_ratio > gap_threshold
    ]
    return pd.DataFrame(warnings).sort_values("supply_gap_pct", ascending=False)
# ── Portfolio Loss Ratio Summary ───────────────────────────────────────────
def portfolio_summary(zone_forecasts: list) -> dict:
    """
    Aggregate loss ratio across all zones → single portfolio metric.
    This is the headline number on the Insurer Dashboard.
    """
    total_claims   = sum(z.expected_claims_inr for z in zone_forecasts)
    total_premiums = sum(z.expected_premiums    for z in zone_forecasts)
    portfolio_lr   = total_claims / max(total_premiums, 1.0)
    red_zones   = [z for z in zone_forecasts if z.risk_band == "RED"]
    amber_zones = [z for z in zone_forecasts if z.risk_band == "AMBER"]
    return {
        "portfolio_loss_ratio": round(portfolio_lr, 4),
        "total_claims_inr":     round(total_claims, 2),
        "total_premiums_inr":   round(total_premiums, 2),
        "zones_analysed":       len(zone_forecasts),
        "red_zone_count":       len(red_zones),
        "amber_zone_count":     len(amber_zones),
        "red_zones":            [z.zone_id for z in red_zones],
        "insurer_alert":        portfolio_lr > 0.90,
        "reinsurance_trigger":  portfolio_lr > 1.10,  # catastrophic event signal
    }
# ── Demo: Generate Insurer Dashboard Output ────────────────────────────────
def demo_insurer_dashboard():
    """
    Simulate insurer dashboard output without a live Prophet model.
    In production: load fitted model, call m.predict(future), pass to compute_zone_loss_ratio.
    """
    print("\n" + "═"*65)
    print("  HUSTLR INSURER DASHBOARD — 7-Day Loss Ratio Forecast")
    print("  Powered by M7 Prophet | 150 zones | 2026-04-14 → 2026-04-20")
    print("═"*65)
    # Simulate 5 representative zone forecasts for the demo
    now = pd.Timestamp.now(tz="Asia/Kolkata").floor("h")
    demo_zones = [
        # (zone_id, city, avg_demand, avg_precip, rain_hours_out_of_168)
        ("891e35a3cffffff", "Chennai",   62.4, 9.2,  80),   # NE monsoon tail — high rain
        ("891e35b1cffffff", "Chennai",   58.1, 6.8,  45),   # moderate rain
        ("891f1d48bffffff", "Mumbai",    88.3, 2.1,  12),   # dry week
        ("891f1d59fffffff", "Mumbai",    91.0, 12.4, 110),  # cyclone watch — very high
        ("891e3553cffffff", "Bangalore", 71.2, 3.5,  20),   # light rain
    ]
    forecasts = []
    for zone_id, city, avg_d, avg_p, rain_h in demo_zones:
        # Build synthetic Prophet output slice for demo
        future_range = pd.date_range(now, periods=168, freq="h", tz="Asia/Kolkata")
        yhat_log = np.log(np.random.normal(avg_d, avg_d * 0.05, size=168).clip(1))
        precip   = np.where(
            np.arange(168) < rain_h,
            np.random.uniform(5.5, 15.0, 168),
            np.random.uniform(0.0, 1.0, 168)
        )
        forecast_df = pd.DataFrame({
            "ds":        future_range,
            "yhat":      yhat_log,
            "precip_mm": precip,
        })
        zf = compute_zone_loss_ratio(zone_id, city, forecast_df)
        forecasts.append(zf)
    # Print zone-level table
    print(f"\n{'Zone ID':<20} {'City':<12} {'Loss Ratio':>12} {'Risk':>8} {'Gap%':>7} {'Action'}")
    print("─" * 75)
    for z in forecasts:
        action = "SURGE" if z.supply_gap_ratio > 0.50 else ("WATCH" if z.risk_band == "AMBER" else "OK")
        print(
            f"{z.zone_id:<20} {z.city:<12} "
            f"{z.predicted_loss_ratio:>11.2%} "
            f"{z.risk_band:>8} "
            f"{z.supply_gap_ratio*100:>6.1f}% "
            f"{action}"
        )
    # Portfolio summary
    summary = portfolio_summary(forecasts)
    print(f"\n{'─'*75}")
    print(f"  Portfolio Loss Ratio : {summary['portfolio_loss_ratio']:.2%}")
    print(f"  Total Claims (7d)    : ₹ {summary['total_claims_inr']:,.0f}")
    print(f"  Total Premiums (7d)  : ₹ {summary['total_premiums_inr']:,.0f}")
    print(f"  Red Zones            : {summary['red_zone_count']}")
    print(f"  Insurer Alert        : {'YES — ESCALATE' if summary['insurer_alert'] else 'No'}")
    print(f"  Reinsurance Trigger  : {'YES' if summary['reinsurance_trigger'] else 'No'}")
    # Supply gap warnings
    warnings = generate_supply_gap_warnings(forecasts)
    if not warnings.empty:
        print(f"\n  Supply Gap Warnings (>{30}% unmet demand):")
        for _, row in warnings.iterrows():
            print(
                f"    {row['zone_id']} ({row['city']})  "
                f"Gap: {row['supply_gap_pct']}%  "
                f"Action: {row['recommended_action']}"
            )
    print(f"{'═'*65}\n")
if __name__ == "__main__":
