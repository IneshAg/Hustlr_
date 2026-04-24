/*
  DATA TRUST HIERARCHY
  
  Expert instruction: GPS is least reliable.
  Government APIs have highest trust.
  GPS alone NEVER triggers a payout.
  
  Combined trust score >= 0.75 required to auto-approve.
  Single source, even government, requires corroboration.
*/

const TRUST_SCORES = {
  IMD_OFFICIAL: 1.0, // Tier 1 — Government
  NDMA_ADVISORY: 1.0, // Tier 1 — Government
  TRAI_REGISTRY: 0.9, // Tier 1 — Government telecom
  PLATFORM_ORDER_LOG: 0.85, // Tier 2 — Platform (Zepto API)
  NEWS_CORROBORATED: 0.7, // Tier 2 — Verified news (generic)
  NEWSAPI_CORROBORATED: 0.7, // Tier 2 — Verified news
  TOMORROWIO_LIVE: 0.78, // Tier 2 — Premium weather intelligence
  OPENWEATHER_LIVE: 0.75, // Tier 2 — Trusted third party
  WEATHERAPI_LIVE: 0.75, // Tier 2 — Trusted third party
  AQICN_LIVE: 0.7, // Tier 2 — Trusted third party
  TOMTOM_LIVE: 0.7, // Tier 2 — Live traffic intelligence
  OPENROUTESERVICE_LIVE: 0.6, // Tier 3 — Route-based inferred traffic
  CELL_TOWER: 0.6, // Tier 3 — Telecom (inferred)
  OOKLA_SPEED: 0.55, // Tier 3 — Third party speed
  DEVICE_GPS: 0.3, // Tier 4 — Lowest trust
  DEVICE_ACCEL: 0.25, // Tier 4 — Lowest trust
  DEVICE_BATTERY: 0.2, // Tier 4 — Lowest trust
};

const MIN_COMBINED_TRUST = 0.75;

function calculateCombinedTrust(activeSources) {
  if (!activeSources || activeSources.length === 0) return 0;

  // Not additive — uses highest source + partial credit for others
  const sorted = activeSources
    .map((s) => TRUST_SCORES[s] ?? 0)
    .sort((a, b) => b - a);

  const primary = sorted[0] ?? 0;
  const secondary = sorted.slice(1).reduce((sum, s) => sum + s * 0.3, 0);

  return Math.min(primary + secondary, 1.0);
}

function isTrustSufficient(activeSources) {
  const score = calculateCombinedTrust(activeSources);
  return {
    sufficient: score >= MIN_COMBINED_TRUST,
    score: Math.round(score * 100) / 100,
    sources: activeSources,
    threshold: MIN_COMBINED_TRUST,
  };
}

module.exports = {
  TRUST_SCORES,
  calculateCombinedTrust,
  isTrustSufficient,
};
