/*
  ACTUARIAL DECISION FRAMEWORK — Tier Allocation Governed by 3 Laws
  
  Law 1: Correlation Risk — What % of zone's workers claim simultaneously?
  Law 2: Multiplier Limit — Daily Cap ÷ Weekly Premium ≤ 6.9× (pool survival)
  Law 3: Gaming Vulnerability — Can a worker manipulate telemetry to force false claim?
  
  TIER ALLOCATIONS (CORRECTED):
  
  Basic Shield (₹35/wk, ₹210 weekly cap, ₹100 daily cap, 6.0× multiplier):
    • HIGH frequency, LOW severity triggers
    • Independent events (no correlation)
    • 100% automated (zero manual claims)
    • NO add-ons
    • Triggers: rain_heavy, heat_severe only
  
  Standard Shield (₹49/wk, ₹340 weekly cap, ₹150 daily cap, 6.9× multiplier):
    • MODERATE frequency, MEDIUM severity
    • Operational triggers (require ISS validation)
    • Manual claims enabled
    • Optional add-ons: bandh_curfew (+₹15/wk), internet_blackout (+₹12/wk)
    • Triggers: 3 base + 2 optional add-ons
    • NO Cyclone, NO Extreme Rain, NO Traffic (too high correlation/frequency)
  
  Full Shield (₹79/wk, ₹500 weekly cap, ₹250 daily cap, 6.3× multiplier):
    • LOW frequency, HIGH severity catastrophes
    • 100% zone correlation events
    • Manual claims enabled
    • Compound multipliers enabled (1.0–1.3×)
    • Claim-free cashback: 10% after 4 clean weeks
    • Triggers: ALL, including cyclone_landfall, rain_extreme, traffic_congestion
*/

const PLAN_CONFIG = {
  basic: {
    weekly_premium_paise: 3500, // ₹35/week
    weekly_cap_paise: 21000, // ₹210/week (6.0× premium)
    max_daily_payout_paise: 10000, // ₹100/day (hard limit)
    manual_claims: false,
    compound_multipliers: false,
    cashback_enabled: false,
    name: "Basic Shield",
    description: "Heavy rain + extreme heat cover",
    base_triggers: ["rain_heavy", "heat_severe"],
    addon_triggers: [], // NO add-ons for Basic
  },
  standard: {
    weekly_premium_paise: 4900, // ₹49/week
    weekly_cap_paise: 34000, // ₹340/week (6.9× premium)
    max_daily_payout_paise: 15000, // ₹150/day
    manual_claims: true,
    compound_multipliers: false,
    cashback_enabled: false,
    name: "Standard Shield",
    description: "3 base triggers + 2 optional add-ons",
    base_triggers: ["rain_heavy", "heat_severe", "aqi_hazardous"],
    addon_triggers: ["bandh_strike", "internet_blackout"], // Available as quarterly add-ons
    banned_triggers: ["cyclone_landfall", "rain_extreme", "traffic_congestion"], // Explicitly forbidden
  },
  full: {
    weekly_premium_paise: 7900, // ₹79/week
    weekly_cap_paise: 50000, // ₹500/week (6.3× premium, absolute hard ceiling)
    max_daily_payout_paise: 25000, // ₹250/day
    manual_claims: true,
    compound_multipliers: true, // Enables 1.0–1.3× acceleration
    cashback_enabled: true, // 10% after 4 clean weeks
    name: "Full Shield",
    description: "All 9 triggers + compound + cashback",
    base_triggers: "all", // All triggers included
    addon_triggers: [], // All triggers already included
  },
};

// ── TRIGGER CONFIGURATION ────────────────────────────────────────────────────
// Every trigger has: hourly rate, daily cap, and tier eligibility
// Tier eligibility is ENFORCED: a trigger outside the tier's list will be REJECTED
const TRIGGER_CONFIG = {
  rain_heavy: {
    hourly_rate_paise: 4000, // ₹40/hr
    daily_cap_paise: 12000, // ₹120/day
    frequency_per_year: 8, // 8× annually
    eligible_tiers: ["basic", "standard", "full"],
    description: "Heavy rain 64.5–115mm/hr",
  },
  heat_severe: {
    hourly_rate_paise: 4500, // ₹45/hr
    daily_cap_paise: 13000, // ₹130/day (Basic hits ₹100 cap first)
    frequency_per_year: 5,
    eligible_tiers: ["basic", "standard", "full"],
    description: "Heat wave ≥43°C (IMD)",
  },
  aqi_hazardous: {
    hourly_rate_paise: 3500, // ₹35/hr
    daily_cap_paise: 10000, // ₹100/day
    frequency_per_year: 3,
    eligible_tiers: ["standard", "full"],
    description: "Severe pollution AQI >200",
  },
  aqi_very_unhealthy: {
    hourly_rate_paise: 3200, // ₹32/hr
    daily_cap_paise: 9500, // ₹95/day
    frequency_per_year: 4,
    eligible_tiers: ["standard", "full"],
    description: "Very unhealthy AQI 151–200",
  },
  platform_outage: {
    hourly_rate_paise: 5000, // ₹50/hr
    daily_cap_paise: 14000, // ₹140/day
    frequency_per_year: 6,
    eligible_tiers: ["standard", "full"], // ISS-validated only
    description: "App outage >60% failure rate",
  },
  dark_store_closure: {
    hourly_rate_paise: 4000, // ₹40/hr
    daily_cap_paise: 12000, // ₹120/day
    frequency_per_year: 2,
    eligible_tiers: ["standard", "full"],
    description: "Hub/dark store closure",
  },
  rain_extreme: {
    hourly_rate_paise: 6500, // ₹65/hr
    daily_cap_paise: 20000, // ₹200/day
    frequency_per_year: 2,
    eligible_tiers: ["full"], // FULL SHIELD ONLY — corrected from legacy Standard Shield+ label
    description: "Cyclone band ≥115.6mm (catastrophic)",
  },
  cyclone_landfall: {
    hourly_rate_paise: 8000, // ₹80/hr
    daily_cap_paise: 25000, // ₹250/day
    frequency_per_year: 0.4,
    eligible_tiers: ["full"], // FULL SHIELD ONLY
    description: "Cyclone landfall Cat 1–5",
  },
  traffic_congestion: {
    hourly_rate_paise: 3000, // ₹30/hr
    daily_cap_paise: 8000, // ₹80/day
    frequency_per_year: 10, // Highest frequency
    eligible_tiers: ["full"], // FULL SHIELD ONLY (too much volume)
    description: "Heavy traffic congestion",
  },
  bandh_strike: {
    hourly_rate_paise: 5500, // ₹55/hr
    daily_cap_paise: 15000, // ₹150/day
    frequency_per_year: 3,
    eligible_tiers: ["full"], // Base for Full
    addon_eligible_tiers: ["standard"], // But available as Standard add-on (+₹15/wk)
    description: "Bandh/strike/curfew",
  },
  internet_blackout: {
    hourly_rate_paise: 4500, // ₹45/hr
    daily_cap_paise: 11000, // ₹110/day
    frequency_per_year: 2,
    eligible_tiers: ["full"], // Base for Full
    addon_eligible_tiers: ["standard"], // But available as Standard add-on (+₹12/wk)
    description: "Internet/connectivity blackout",
  },
};

// ── ADD-ON CONFIGURATION (Standard-only, quarterly) ──────────────────────────
const ADDON_CONFIG = {
  bandh_curfew_addon: {
    eligible_base_tiers: ["standard"], // STANDARD ONLY
    weekly_cost_paise: 1500, // +₹15/week
    commitment_weeks: 13, // Quarterly lock-in
    unlocks_trigger: "bandh_strike",
    description: "Bandh/curfew coverage (+₹15/wk)",
  },
  internet_blackout_addon: {
    eligible_base_tiers: ["standard"], // STANDARD ONLY
    weekly_cost_paise: 1200, // +₹12/week
    commitment_weeks: 13,
    unlocks_trigger: "internet_blackout",
    description: "Internet blackout add-on (+₹12/wk)",
  },
  // NOTE: NO add-ons for Basic. NO add-ons for Full (everything already included).
};

// Validation: tier order for checks
const PLAN_TIER_RANK = {
  basic: 1,
  standard: 2,
  full: 3,
};

const TRIGGER_TYPE_MAP = {
  // Canonical (already correct)
  rain_heavy: "rain_heavy",
  rain_moderate: "rain_heavy",
  rain_light: "rain_heavy",
  rain_extreme: "rain_extreme",
  heat_severe: "heat_severe",
  heat_stress: "heat_severe",
  aqi_hazardous: "aqi_hazardous",
  aqi_very_unhealthy: "aqi_hazardous",
  platform_outage: "platform_outage",
  dark_store_closure: "dark_store_closure",
  bandh_strike: "bandh_strike",
  bandh: "bandh_strike",
  internet_blackout: "internet_blackout",
  traffic_congestion: "traffic_congestion",
  cyclone_landfall: "cyclone_landfall",
  // Title-case / spaced variants from external APIs
  "Heavy Rain": "rain_heavy",
  "Extreme Rain": "rain_extreme",
  "Platform Outage": "platform_outage",
  "Extreme Heat": "heat_severe",
  Heatwave: "heat_severe",
  "Bandh Strike": "bandh_strike",
  "Internet Blackout": "internet_blackout",
  "Cyclone Landfall": "cyclone_landfall",
  "Severe AQI": "aqi_hazardous",
  "Dark Store Closure": "dark_store_closure",
};

function isTriggerEligibleForTier(triggerType, planTier) {
  const trigger = TRIGGER_CONFIG[triggerType];
  if (!trigger) return false;
  return trigger.eligible_tiers.includes(planTier);
}

function isTriggerAvailableAsAddon(triggerType, planTier) {
  const trigger = TRIGGER_CONFIG[triggerType];
  if (!trigger || !trigger.addon_eligible_tiers) return false;
  return trigger.addon_eligible_tiers.includes(planTier);
}

function getWeeklyCap(planTier) {
  const plan = PLAN_CONFIG[planTier || "basic"];
  return plan ? plan.weekly_cap_paise : 0;
}

function getMaxDailyPayout(planTier) {
  const plan = PLAN_CONFIG[planTier || "basic"];
  return plan ? plan.max_daily_payout_paise : 0;
}

function sanitizeTriggerType(rawInput) {
  if (!rawInput) return "platform_outage";
  const direct = TRIGGER_TYPE_MAP[rawInput];
  if (direct) return direct;
  const normalised = rawInput.toLowerCase().replace(/[ -]+/g, "_");
  return TRIGGER_TYPE_MAP[normalised] ?? normalised;
}

module.exports = {
  PLAN_CONFIG,
  TRIGGER_CONFIG,
  ADDON_CONFIG,
  PLAN_TIER_RANK,
  // Exports for backward compatibility
  HOURLY_RATES: Object.entries(TRIGGER_CONFIG).reduce((acc, [key, val]) => {
    acc[key] = Math.round(val.hourly_rate_paise / 100);
    return acc;
  }, {}),
  DAILY_CAPS: Object.entries(TRIGGER_CONFIG).reduce((acc, [key, val]) => {
    acc[key] = Math.round(val.daily_cap_paise / 100);
    return acc;
  }, {}),
  TIER_FACTORS: {
    basic: 1.0,
    standard: 1.0,
    full: 1.0,
  },
  TRIGGER_FREQUENCY: {
    rain_heavy: 8,
    rain_extreme: 2,
    heat_severe: 5,
    aqi_hazardous: 3,
    platform_outage: 6,
    bandh_strike: 3,
    traffic_congestion: 10,
    internet_blackout: 2,
    cyclone_landfall: 0.4,
  },
  COMPOUND_BONUSES: {
    "rain_heavy+platform_outage": {
      multiplier: 1.0,
      type: "additive",
      note: "100% of both rates simultaneously",
    },
    "cyclone_landfall+bandh_strike": {
      multiplier: 1.2,
      type: "multiplicative",
      note: "120% on cyclone rate — cap still ₹500",
    },
    "heat_severe+aqi_hazardous": {
      multiplier: 1.1,
      type: "multiplicative",
      note: "110% on higher rate — cap still ₹500",
    },
    "rain_extreme+internet_blackout": {
      multiplier: 1.3,
      type: "multiplicative",
      note: "Catastrophic — 130% accelerates to ₹500 cap faster. NO cap lift.",
    },
  },
  SHIFT_MULTIPLIERS: {
    peak: 1.0,
    offpeak: 0.75,
    prepeak: 0.5,
    night: 0.0,
  },
  ZONE_DEPTH_MULTIPLIERS: {
    core: 1.0,
    middle: 0.7,
    outer: 0.3,
  },
  ACTIVITY_LOADING: {
    above_20_days: 1.0,
    between_7_20: 1.08,
    below_7_days: 1.15,
    below_5_days: 1.25, // Higher loading for very low activity
  },
  MONSOON_SURCHARGE: 0.22,
  REINSURANCE_TRIGGER: 4.0,
  WEEKLY_INCOME_ESTIMATE: 2940,
  AVG_DAILY_INCOME: 420,
  ZONE_RISK: {
    adyar: 0.72,
    korattur: 0.45,
    t_nagar: 0.68,
    anna_nagar: 0.41,
    velachery: 0.65,
    tambaram: 0.55,
    porur: 0.5,
    chromepet: 0.52,
    sholinganallur: 0.58,
    guindy: 0.48,
    kattankulathur: 0.44,
  },
  TRIGGER_TYPE_MAP,
  isTriggerEligibleForTier,
  isTriggerAvailableAsAddon,
  getWeeklyCap,
  getMaxDailyPayout,
  sanitizeTriggerType,
};
