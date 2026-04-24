const axios = require("axios");

const ML_URL = process.env.ML_SERVICE_URL;
const TIMEOUT = 4000;

// ── Fraud Scoring ──────────────────────────────────────────

async function getFraudScore(data) {
  if (!ML_URL) {
    console.warn("[ML] ML_SERVICE_URL not set — using local fallback");
    return _localFraudFallback(data);
  }

  try {
    const res = await axios.post(
      `${ML_URL}/fraud-score`,
      {
        worker_id: data.worker_id || "unknown",
        zone_id: data.zone_id || "adyar",
        claim_timestamp: new Date().toISOString(),
        feature_vector: {
          // Node.js native fields
          zone_match: data.zone_match ?? 0.85,
          gps_jitter: data.gps_jitter ?? 0.1,
          accelerometer_match: data.accel_match ?? 0.9,
          wifi_home_ssid: data.wifi_home ?? false,
          days_since_onboarding: data.days_active ?? 30,
          // Extended fields when available
          claim_latency_seconds: data.latency_seconds ?? 120,
          simultaneous_zone_claims: data.zone_claim_count ?? 1,
          zone_depth_score: data.depth_score ?? 0.75,
          is_mock_location_ever: data.is_mock_location ?? false,
          orders_completed_during_disruption: data.orders_during ?? 0,
          device_shared_with_n_accounts: data.device_share_count ?? 1,
        },
      },
      { timeout: TIMEOUT },
    );

    // Map Python response to Node.js expected shape
    const d = res.data;
    const rawScore = d.anomaly_score ?? 0;
    const fps = Math.round(rawScore * 100);

    return {
      fraud_score: fps,
      status: fps >= 80 ? "FLAGGED" : fps >= 50 ? "REVIEW" : "CLEAN",
      action:
        fps >= 80 ? "HUMAN_REVIEW" : fps >= 50 ? "SOFT_HOLD" : "AUTO_APPROVE",
      top_features: d.top_features || [],
      poisson_p_value: d.poisson_p_value ?? null,
      model_used: d.model_version || "isolation_forest_v3",
      source: "ml-service",
    };
  } catch (e) {
    console.error("[ML] /fraud-score failed:", e.message, "— using fallback");
    return _localFraudFallback(data);
  }
}

// ── ISS Score ──────────────────────────────────────────────

async function getISSScore(data) {
  if (!ML_URL) return _localISSFallback(data);

  try {
    const res = await axios.post(
      `${ML_URL}/iss`,
      {
        zone_flood_risk: data.zone_flood_risk ?? 0.6,
        avg_daily_income: data.avg_daily_income ?? 600,
        disruption_freq_12mo: data.disruption_freq ?? 8,
        platform_tenure_weeks: data.tenure_weeks ?? 4,
        city: data.city ?? "Chennai",
      },
      { timeout: TIMEOUT },
    );

    return {
      iss_score: res.data.iss_score,
      tier: res.data.tier,
      recommendation: res.data.recommendation,
      model_used: res.data.model_used,
      source: "ml-service",
    };
  } catch (e) {
    console.error("[ML] /iss failed:", e.message, "— using fallback");
    return _localISSFallback(data);
  }
}

// ── Premium Calculation ────────────────────────────────────

async function getPremium(data) {
  if (!ML_URL) return _localPremiumFallback(data);

  try {
    const res = await axios.post(
      `${ML_URL}/premium`,
      {
        plan_tier: data.plan_tier ?? "standard",
        zone: data.zone ?? "Adyar Dark Store Zone",
        iss_score: data.iss_score ?? 62,
        activity_loading: data.activity_loading ?? 1.0,
        previous_premium: data.previous_premium ?? 0,
        is_monsoon_season: data.is_monsoon_season ?? false,
      },
      { timeout: TIMEOUT },
    );

    return {
      plan_tier: res.data.plan_tier,
      base_premium: res.data.base_premium,
      zone_adjustment: res.data.zone_adjustment,
      activity_adjustment: res.data.activity_adjustment || 0,
      monsoon_adjustment: res.data.monsoon_adjustment || 0,
      final_premium: res.data.final_premium,
      note: res.data.note,
      source: "ml-service",
    };
  } catch (e) {
    console.error("[ML] /premium failed:", e.message, "— using fallback");
    return _localPremiumFallback(data);
  }
}

// ── Forecast ───────────────────────────────────────────────

async function getForecast(zone) {
  if (!ML_URL) return null;

  const zoneKey = zone
    .toLowerCase()
    .replace(" dark store zone", "")
    .replace(/ /g, "_");

  try {
    const res = await axios.get(
      `${ML_URL}/forecast/${encodeURIComponent(zoneKey)}`,
      { timeout: 30000 },
    );
    return res.data;
  } catch (e) {
    console.error("[ML] /forecast failed:", e.message);
    return null;
  }
}

// ── Work Advisor (ESI + advisory copy) ───────────────────

function _clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}

function _localWorkAdvisorFallback(data = {}) {
  const rainChance = Number(data.tomorrow_rain_chance_pct ?? 0);
  const rainMm = Number(data.tomorrow_rain_mm ?? 0);
  const aqi = Number(data.aqi ?? 50);
  const mlRisk = Number(data.ml_tomorrow_risk ?? 0);
  const activeDisruptions = Number(data.active_disruption_count ?? 0);

  const riskScore = _clamp(
    rainChance * 0.45 +
      _clamp(rainMm * 2.2, 0, 35) +
      _clamp((aqi - 50) * 0.08, 0, 20) +
      _clamp(mlRisk * 35, 0, 35) +
      _clamp(activeDisruptions * 8, 0, 24),
    0,
    100,
  );

  const esi = _clamp(Math.round(100 - riskScore), 0, 100);
  const estimatedLoss = Math.round(_clamp(180 + riskScore * 7, 180, 1200));
  const suggestedPremium = esi >= 80 ? 35 : esi >= 60 ? 49 : 79;
  const missedAmount = Math.round(_clamp(estimatedLoss * 1.2, 250, 1800));

  if (esi >= 80) {
    return {
      earning_stability_index: esi,
      stability_band: "GREEN",
      stability_band_label: "High Stability",
      headline:
        "Your earnings are consistent, but sudden weather changes could still disrupt your peak windows.",
      coverage_nudge:
        "Protect your strong run — even high earners face unexpected disruptions.",
      suggest_activate_coverage: false,
      recommended_shift_windows: [
        { label: "Morning", time: "7 AM – 11 AM", demand: "High" },
        { label: "Evening", time: "6 PM – 9 PM", demand: "Peak" },
      ],
      model_used: "rule_engine_work_advisor_v1",
      _source: "local_fallback",
      risk_score: riskScore,
      estimated_loss: estimatedLoss,
    };
  }

  if (esi >= 60) {
    return {
      earning_stability_index: esi,
      stability_band: "AMBER",
      stability_band_label: "Moderate Stability",
      headline:
        "There is a moderate chance of weather or platform issues coming up that might dip your earnings.",
      coverage_nudge: `Estimated disruption impact is around ₹${estimatedLoss}. A ₹${suggestedPremium}/week plan may help reduce this risk. Terms apply.`,
      suggest_activate_coverage: true,
      recommended_shift_windows: [
        { label: "Late Morning", time: "10 AM – 1 PM", demand: "Medium" },
        { label: "Evening", time: "5 PM – 8 PM", demand: "High" },
      ],
      model_used: "rule_engine_work_advisor_v1",
      _source: "local_fallback",
      risk_score: riskScore,
      estimated_loss: estimatedLoss,
    };
  }

  return {
    earning_stability_index: esi,
    stability_band: "RED",
    stability_band_label: "Low Stability",
    headline:
      "There is a higher likelihood of severe weather or outages in your zone, which may affect earnings.",
    coverage_nudge: `Recent disruption patterns suggest potential impact around ₹${missedAmount}. Coverage options start at ₹35/week. Terms apply.`,
    suggest_activate_coverage: true,
    recommended_shift_windows: [
      { label: "Mid-morning", time: "9 AM – 12 PM", demand: "Medium" },
      { label: "Evening", time: "6 PM – 9 PM", demand: "High" },
    ],
    model_used: "rule_engine_work_advisor_v1",
    _source: "local_fallback",
    risk_score: riskScore,
    estimated_loss: estimatedLoss,
  };
}

async function getWorkAdvisor(data) {
  if (!ML_URL) return _localWorkAdvisorFallback(data);

  try {
    const res = await axios.post(`${ML_URL}/work-advisor`, data, {
      timeout: TIMEOUT,
    });
    const d = res.data || {};
    return {
      earning_stability_index: Number(d.earning_stability_index ?? d.esi ?? 60),
      stability_band: d.stability_band ?? "AMBER",
      stability_band_label: d.stability_band_label ?? "Moderate Stability",
      headline:
        d.headline ??
        "There is a moderate chance of weather or platform issues coming up that might dip your earnings.",
      coverage_nudge:
        d.coverage_nudge ??
        "Estimated disruption impact is around ₹600. A ₹49/week plan may help reduce this risk. Terms apply.",
      suggest_activate_coverage: Boolean(d.suggest_activate_coverage ?? true),
      recommended_shift_windows: Array.isArray(d.recommended_shift_windows)
        ? d.recommended_shift_windows
        : [],
      model_used: d.model_used || "ml-service-work-advisor",
      _source: "ml-service",
    };
  } catch (e) {
    console.warn("[ML] /work-advisor failed:", e.message, "— using fallback");
    return _localWorkAdvisorFallback(data);
  }
}

// ── Fallbacks ─────────────────────────────────────────────
// These are called when ML service is unreachable.
// They use deterministic logic — NOT random numbers.

function _localFraudFallback(data) {
  let score = 10; // start clean

  if ((data.gps_jitter ?? 0.1) < 0.000001) score += 80;
  if ((data.days_active ?? 30) < 14) score += 20;
  if (data.wifi_home ?? false) score += 20;
  if ((data.zone_claim_count ?? 1) > 50) score += 35;

  const hour = new Date().getHours();
  if (hour < 8 || hour > 22) score += 15;

  score = Math.min(100, score);

  return {
    fraud_score: score,
    status: score >= 80 ? "FLAGGED" : score >= 50 ? "REVIEW" : "CLEAN",
    action:
      score >= 80 ? "HUMAN_REVIEW" : score >= 50 ? "SOFT_HOLD" : "AUTO_APPROVE",
    source: "local_fallback",
    model_used: "rule_engine_v2",
  };
}

function _localISSFallback(data) {
  let score = 100;
  score -= (data.zone_flood_risk ?? 0.6) * 20;
  score -= Math.min(data.disruption_freq ?? 8, 15);
  score += Math.min((data.avg_daily_income ?? 600) / 200, 10);
  score += Math.min((data.tenure_weeks ?? 4) / 10, 8);
  score = Math.max(0, Math.min(100, Math.round(score)));

  const tier =
    score >= 70
      ? "GREEN"
      : score >= 50
        ? "AMBER"
        : score >= 30
          ? "AMBER_LOW"
          : "RED";

  return {
    iss_score: score,
    tier,
    recommendation: score >= 70 ? "basic" : score >= 40 ? "standard" : "full",
    model_used: "rule_engine_local",
    source: "local_fallback",
  };
}

function _localPremiumFallback(data) {
  const { PLAN_CONFIG, MONSOON_SURCHARGE } = require("../config/constants");

  const planKey = data.plan_tier ?? "standard";
  const plan = PLAN_CONFIG[planKey];

  if (!plan) {
    console.warn(`[ML] Plan tier '${planKey}' not found in PLAN_CONFIG`);
    return {
      plan_tier: planKey,
      base_premium: 49,
      zone_adjustment: 0,
      activity_adjustment: 0,
      monsoon_adjustment: 0,
      final_premium: 49,
      note: "Plan not found — using standard fallback",
      source: "local_fallback",
    };
  }

  // Base premium in rupees
  let basePremium = plan.weekly_premium_paise / 100;

  // Zone adjustment (fixed zone offsets)
  let zoneAdj = 0;
  const zone = data.zone || "";
  if (zone.includes("Adyar") || zone.includes("adyar")) zoneAdj = 5;
  else if (zone.includes("Velachery") || zone.includes("velachery"))
    zoneAdj = 7;
  else if (zone.includes("Tambaram") || zone.includes("tambaram")) zoneAdj = 4;

  // Activity loading adjustment (8% penalty for 7–20 day workers)
  const activityLoading = data.activity_loading ?? 1.0;
  const activityAdj = Math.round((activityLoading - 1.0) * basePremium);

  // Monsoon surcharge (22% Oct–Dec)
  let monsoonAdj = 0;
  if (data.is_monsoon_season === true) {
    monsoonAdj = Math.round(basePremium * MONSOON_SURCHARGE);
  }

  const finalPremium = basePremium + zoneAdj + activityAdj + monsoonAdj;

  return {
    plan_tier: planKey,
    base_premium: basePremium,
    zone_adjustment: zoneAdj,
    activity_adjustment: activityAdj,
    monsoon_adjustment: monsoonAdj,
    final_premium: Math.round(finalPremium),
    note: `Actuarial premium: base ${basePremium} + zone ${zoneAdj} + activity ${activityAdj} + monsoon ${monsoonAdj}`,
    source: "local_fallback",
  };
}

// ── Health Check ───────────────────────────────────────────
async function isMlOnline() {
  if (!ML_URL) return false;
  try {
    const res = await axios.get(`${ML_URL}/health`, { timeout: 2000 });
    return res.data?.status === "ok";
  } catch (e) {
    return false;
  }
}

// ── GNN Fraud Ring Detection ─────────────────────────────────
async function getGNNFraudRings(zoneId, workers, fraudThreshold = 0.7) {
  if (!ML_URL) {
    console.warn(
      "[ML] ML_SERVICE_URL not set — GNN fraud detection unavailable",
    );
    return { fraud_rings_detected: 0, rings: [], risk_level: "LOW" };
  }

  try {
    const res = await axios.post(
      `${ML_URL}/fraud/gnn-ring-detect`,
      {
        zone_id: zoneId,
        workers: workers,
        fraud_threshold: fraudThreshold,
      },
      { timeout: 10000 },
    );

    return {
      zone_id: res.data.zone_id,
      total_workers: res.data.total_workers,
      fraud_rings_detected: res.data.fraud_rings_detected,
      rings: res.data.rings,
      risk_level: res.data.risk_level,
      latency_ms: res.data.latency_ms,
      source: "ml_gnn_service",
    };
  } catch (e) {
    console.error("[ML] /fraud/gnn-ring-detect failed:", e.message);
    return {
      fraud_rings_detected: 0,
      rings: [],
      risk_level: "LOW",
      error: e.message,
    };
  }
}

module.exports = {
  getFraudScore,
  getISSScore,
  getPremium,
  getForecast,
  getWorkAdvisor,
  isMlOnline,
  getGNNFraudRings,
};
