const { PLAN_CONFIG, ZONE_RISK, MONSOON_SURCHARGE } = require('../config/constants');

/*
  Premium calculation — README canonical rules:

  1. Base premium = plan tier advertised price (₹35 / ₹49 / ₹79)
  2. Zone adjustment = ±10% based on flood/risk zone profile
  3. ISS adjustment  = small discount for high-ISS (low-risk) workers
  4. Activity loading = +8% if worker has only 7–20 active days (less behavioral baseline)
  5. Monsoon surcharge = +22% if policy purchased Oct–Dec (rain trigger freq rises 12% → 32%)
  6. Hard clamp: final premium never drifts >±20% from advertised base (README guardrail)

  BCR guardrails (enforced by circuit-breaker.js, NOT here):
    BCR > 0.80  → auto +15% + enrollment pause
    BCR < 0.45  → auto -10% (fairness obligation)
*/
function calculatePremium(plan_tier, iss_score, zone, {
  active_days_last_30 = 25,   // default = experienced worker, standard rate
  force_date = null,           // override Date for testing
} = {}) {
  const plan = PLAN_CONFIG[plan_tier];
  if (!plan) {
    throw new Error(`Invalid plan tier: ${plan_tier}`);
  }
  const base = plan.base;

  // ── Zone adjustment (±10% of base, based on flood risk profile) ─────────────
  const zone_risk = ZONE_RISK[(zone || '').toLowerCase()] || 0.5;
  const zone_adjustment = Math.round(base * (zone_risk - 0.5) * 0.1);

  // ── ISS adjustment (small discount for low-risk workers) ─────────────────────
  const iss_adjustment = iss_score != null
    ? Math.round(((iss_score - 75) / 100) * base * 0.5)
    : 0;

  // ── Activity loading (+8% for workers with 7–20 active days) ─────────────────
  // < 7 days → declined (enforced in worker.routes.js / claims.routes.js)
  // 7–20 days → +8% loading (less behavioral baseline for fraud detection)
  // > 20 days → standard rate
  let activity_loading = 0;
  let activity_note = 'standard_rate';
  if (active_days_last_30 < 7) {
    // Should have been declined at onboarding — flag for audit
    activity_loading = 0;
    activity_note = 'declined_insufficient_activity';
  } else if (active_days_last_30 <= 20) {
    activity_loading = Math.round(base * 0.08);
    activity_note = '+8%_loading_7_to_20_days';
  }

  // ── Monsoon season surcharge (+22% Oct–Dec) ──────────────────────────────────
  const now = force_date ? new Date(force_date) : new Date();
  const month = now.getMonth() + 1; // 1-indexed
  const is_monsoon_season = month >= 10 && month <= 12;
  const monsoon_surcharge = is_monsoon_season
    ? Math.round(base * MONSOON_SURCHARGE)   // +22% = ₹7–₹17 depending on plan
    : 0;

  // ── Step 1: Weekly Drift Guardrail (max ±20% from advertised base) ─────────────
  // Monsoon surcharge is NOT subject to this weekly drift clamp.
  // Only zone + ISS + activity adjustments are restricted to ±20% per week.
  const adjustments_before_monsoon = zone_adjustment + iss_adjustment + activity_loading;
  const maxDrift = Math.round(base * 0.2);
  const clamped_adjustments = Math.max(-maxDrift, Math.min(maxDrift, adjustments_before_monsoon));
  
  // Calculate the premium before applying the absolute ceiling
  let final_premium = base + clamped_adjustments + monsoon_surcharge;

  // ── Step 2: Absolute Policy Boundary (min 0.7x and max 2.0x of base) ───────────
  // No matter what combination of surcharges and penalties occur, 
  // the premium can NEVER exceed these absolute limits.
  const minPremium = Math.round(base * 0.7);
  const maxPremium = Math.round(base * 2.0);
  
  final_premium = Math.max(minPremium, Math.min(maxPremium, final_premium));

  return {
    base_premium: base,
    zone_adjustment: zone_adjustment,
    iss_adjustment: iss_adjustment,
    activity_loading: activity_loading,
    activity_note: activity_note,
    monsoon_surcharge: monsoon_surcharge,
    is_monsoon_season: is_monsoon_season,
    risk_adjustment: 0,
    final_premium: final_premium,
    weekly_cap: plan.max_payout,
    daily_cap: plan.daily_cap,
    multiplier: plan.multiplier,
    breakdown_label: `₹${base} base + ₹${zone_adjustment} zone + ₹${iss_adjustment} ISS + ₹${activity_loading} activity + ₹${monsoon_surcharge} monsoon = ₹${final_premium}/wk`,
  };
}

module.exports = { calculatePremium };

