"use strict";
/**
 * nlp-service.js — NLP M4 improvements per ML Blueprint v1.0
 * ===========================================================
 * Adds:
 *  - Source credibility weighting (IMD/NDMA trusted more than worker chat)
 *  - 3-band confidence gating (AUTOMATED_ACTION / HUMAN_REVIEW / DEFAULT_WATCH)
 *  - Cross-model compound confirmation (M4 severity=3 + M6 ACCIDENT_BLACKSPOT)
 */

"use strict";

// ── Source credibility weights ────────────────────────────────────────────────
// Prevents a sarcastic worker tweet from triggering bcr emergency protocols
// when official IMD sources show Green.
const SOURCE_WEIGHTS = {
  IMD: 1.15, // Trusted government meteorological source
  NDMA: 1.15, // National Disaster Management Authority
  news: 1.05, // Verified news outlets (NewsAPI articles)
  worker: 0.9, // In-app worker reports (potential bias/sarcasm)
  unknown: 1.0, // Default when source not specified
};

/**
 * applySourceCredibilityWeight — multiply model confidence by source trust factor.
 * Caps at 1.0 so IMD can't push a 0.9 → >1.0.
 * @param {number} modelConfidence 0–1
 * @param {string} source e.g. 'IMD' | 'worker' | 'news'
 * @returns {number} adjusted confidence 0–1
 */
function applySourceCredibilityWeight(modelConfidence, source = "unknown") {
  const weight = SOURCE_WEIGHTS[source] ?? SOURCE_WEIGHTS.unknown;
  return Math.min(modelConfidence * weight, 1.0);
}

/**
 * routeAlert — 3-band confidence gating.
 *
 *  ≥ 0.72  → AUTOMATED_ACTION  (trigger insurance pipeline immediately)
 *  ≥ 0.55  → HUMAN_REVIEW_QUEUE (ops team validates before triggering)
 *  < 0.55  → DEFAULT_WATCH      (log only, default to severity 1)
 *
 * @param {number} confidence 0–1 (after source weighting)
 * @param {number} severity 1–3
 * @returns {{ action: string, severity: number }}
 */
function routeAlert(confidence, severity = 1) {
  if (confidence >= 0.72) {
    return { action: "AUTOMATED_ACTION", severity };
  }
  if (confidence >= 0.55) {
    return { action: "HUMAN_REVIEW_QUEUE", severity: Math.max(severity, 2) };
  }
  // Safe fallback — watch mode, do not trigger payout
  return { action: "DEFAULT_WATCH", severity: 1 };
}

/**
 * checkCompoundConfirmation — cross-model escalation rule.
 *
 * If M4 NLP severity=3 AND M6 ACCIDENT_BLACKSPOT fire in the same zone
 * within 30 minutes → ESCALATE_EMERGENCY regardless of individual confidence.
 *
 * This handles the Tamil Nadu cyclone + traffic gridlock compound event.
 */
function checkCompoundConfirmation(
  m4Severity,
  m6Classification,
  m4Timestamp,
  m6Timestamp,
  zoneMatch = false,
) {
  if (!zoneMatch) return null;

  const timeDiffMs = Math.abs(new Date(m4Timestamp) - new Date(m6Timestamp));
  const within30Min = timeDiffMs < 30 * 60 * 1000;

  if (
    m4Severity === 3 &&
    m6Classification === "ACCIDENT_BLACKSPOT" &&
    within30Min
  ) {
    return "ESCALATE_EMERGENCY";
  }
  return null;
}

/**
 * classifyDisruptionText — high-level helper used by disruption-cron.js.
 * Calls the ML service /nlp endpoint and applies source weighting + routing.
 *
 * @param {string} text
 * @param {object} opts
 * @param {string} opts.source  'IMD' | 'news' | 'worker'
 * @param {boolean} opts.requireDualSource
 * @param {object} opts.sources  e.g. { imd: 0.9, openweather: 0.5 }
 * @returns {Promise<object>}
 */
async function classifyDisruptionText(text, opts = {}) {
  const { source = "unknown", requireDualSource = false, sources = {} } = opts;

  try {
    const mlUrl = process.env.ML_SERVICE_URL || "http://127.0.0.1:8001";
    const resp = await fetch(`${mlUrl}/nlp`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text,
        require_dual_source: requireDualSource,
        sources,
      }),
    });

    if (!resp.ok) throw new Error(`ML /nlp returned ${resp.status}`);

    const result = await resp.json();
    const rawConf = result.confidence ?? 0;
    const adjConf = applySourceCredibilityWeight(rawConf, source);
    const severity =
      result.hourly_rate_inr >= 60 ? 3 : result.hourly_rate_inr >= 45 ? 2 : 1;
    const { action } = routeAlert(adjConf, severity);

    return {
      ...result,
      confidence: adjConf,
      raw_confidence: rawConf,
      source_weight: SOURCE_WEIGHTS[source] ?? 1.0,
      alert_action: action,
      severity,
    };
  } catch (err) {
    return {
      trigger: "normal",
      confidence: 0,
      fires: false,
      alert_action: "DEFAULT_WATCH",
      severity: 1,
      error: err.message,
    };
  }
}

module.exports = {
  applySourceCredibilityWeight,
  routeAlert,
  checkCompoundConfirmation,
  classifyDisruptionText,
  SOURCE_WEIGHTS,
};
