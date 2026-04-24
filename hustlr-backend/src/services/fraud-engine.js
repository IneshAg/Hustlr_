'use strict';
/**
 * fraud-engine.js — updated per ML Blueprint v1.0
 * ================================================
 * Changes from blueprint:
 *  - Decision threshold lowered 0.50 → 0.42 (FNR target <12%)
 *  - 3-tier alert zones: AUTO_APPROVE / MANUAL_REVIEW / AUTO_FLAG
 *  - Compound signal boost: velocityJump + accelMismatch ≥ 0.7
 *  - Network Trust Score: 4-component weighted ensemble
 *  - Conditional high-res telemetry snapshot (trust < 0.70 only)
 *  - H3 Geospatial Precision for zone matching (GigGuard integration)
 */

const mlService = require('./ml-service');
const h3Service = require('./h3-service');

// ── Thresholds ────────────────────────────────────────────────────────────────
const FRAUD_THRESHOLDS = {
  AUTO_APPROVE:   0.42,   // was 0.30 — improves FNR from 18% → <12%
  MANUAL_REVIEW:  0.65,   // borderline band: human ops queue
  AUTO_FLAG:      0.65,   // auto-reject above this
};

// ── Network Trust Score weights (Arjun Iyer architecture) ────────────────────
const NETWORK_WEIGHTS = {
  timingAdvance:     0.30,
  cellIdConsistency: 0.30,
  rsrqJitter:        0.25,
  handoffPattern:    0.15,
};

/**
 * calculateH3ZoneMatch — H3-based zone matching for precise geospatial verification.
 * Returns a score between 0-1 indicating how well the worker location matches the zone.
 * Uses H3 hexagonal grid at resolution 8 (~0.74 km² per hex).
 */
function calculateH3ZoneMatch(workerLat, workerLng, zoneId, city = 'Chennai') {
  if (!workerLat || !workerLng || !zoneId) {
    return 0.5; // Neutral score if data missing
  }

  try {
    // Check if worker is in zone using H3
    const isInZone = h3Service.isWorkerInZone(workerLat, workerLng, zoneId, city);
    
    if (isInZone) {
      // Calculate zone depth score for fine-grained matching
      const depthScore = h3Service.calculateZoneDepthScore(workerLat, workerLng, zoneId, city);
      return depthScore;
    } else {
      // Worker not in zone - calculate distance penalty
      const zoneCenter = h3Service.ZONE_CENTERS[zoneId.toLowerCase()];
      if (zoneCenter) {
        const h3Distance = h3Service.h3Distance(
          workerLat, workerLng,
          zoneCenter.lat, zoneCenter.lng,
          city
        );
        // Penalize based on H3 distance (0-10 hexes)
        const penalty = Math.min(h3Distance / 10, 1.0);
        return Math.max(0, 1.0 - penalty);
      }
    }
    
    return 0.5; // Default neutral score
  } catch (e) {
    console.warn('[FraudEngine] H3 zone match calculation failed:', e.message);
    return 0.5; // Fallback to neutral score
  }
}

/**
 * routeClaim — 3-tier routing replacing the old binary approve/reject.
 * @param {number} fraudScore 0–1
 * @returns {'AUTO_APPROVE'|'MANUAL_REVIEW'|'AUTO_FLAG'}
 */
function routeClaim(fraudScore) {
  if (fraudScore < FRAUD_THRESHOLDS.AUTO_APPROVE)  return 'AUTO_APPROVE';
  if (fraudScore < FRAUD_THRESHOLDS.MANUAL_REVIEW) return 'MANUAL_REVIEW';
  return 'AUTO_FLAG';
}

/**
 * applyCompoundSignalBoost — velocity jump + accelerometer mismatch together
 * is near-certain GPS spoofing (both required, not either).
 */
function applyCompoundSignalBoost(baseScore, velocityJump, accelMismatch) {
  if (velocityJump === true && accelMismatch >= 0.7) {
    return Math.min(baseScore + 0.25, 1.0);
  }
  return baseScore;
}

/**
 * computeNetworkTrustScore — 4-signal weighted ensemble.
 * Score < 0.70 → triggers conditional high-res telemetry snapshot.
 */
function computeNetworkTrustScore(networkSignals = {}) {
  const {
    timingAdvance     = 0.5,
    cellIdConsistency = 0.5,
    rsrqJitter        = 0.5,
    handoffPattern    = 0.5,
  } = networkSignals;

  const score = (
    timingAdvance     * NETWORK_WEIGHTS.timingAdvance     +
    cellIdConsistency * NETWORK_WEIGHTS.cellIdConsistency +
    rsrqJitter        * NETWORK_WEIGHTS.rsrqJitter        +
    handoffPattern    * NETWORK_WEIGHTS.handoffPattern
  );
  return Math.min(Math.max(score, 0), 1);
}

/**
 * collectTripTelemetry — privacy-preserving conditional snapshot.
 * High-res IMU / battery data only collected when trust < 0.70.
 */
async function collectTripTelemetry(tripId, networkSignals = {}) {
  const trustScore = computeNetworkTrustScore(networkSignals);

  const baseRecord = {
    tripIdHash:          _sha256Placeholder(tripId),
    networkTrustScore:   trustScore,
    velocityJumpFlag:    await _detectVelocityJump(tripId),
    timestamp:           new Date().toISOString(),
  };

  // Conditional high-res snapshot — ONLY when suspicious
  if (trustScore < 0.70) {
    return {
      ...baseRecord,
      imuAccelMismatch: await _getImuAccelDelta(tripId),
      batteryTempC:     await _getBatteryTemp(tripId),
      snapshotTrigger:  'trust_score_below_threshold',
    };
  }

  return baseRecord;
}

/**
 * scoreClaim — main entry point (backwards-compatible with existing callers).
 * Wraps mlService.getFraudScore and applies new routing + compound boosts.
 * Integrates H3 zone matching when USE_H3_ZONE_MATCH is enabled.
 */
async function scoreClaim(claimData) {
  // Determine zone ID
  const zoneId = (claimData.zone_id || 'adyar')
    .toLowerCase()
    .replace(/ /g, '_')
    .replace(' dark store zone', '');
  
  const city = claimData.city || 'Chennai';

  // Calculate H3 zone match if enabled and lat/lng provided
  let h3ZoneMatch = null;
  if (process.env.USE_H3_ZONE_MATCH === 'true' && claimData.lat && claimData.lng) {
    h3ZoneMatch = calculateH3ZoneMatch(claimData.lat, claimData.lng, zoneId, city);
  }

  const fraudResult = await mlService.getFraudScore({
    worker_id:        claimData.worker_id,
    zone_id:          zoneId,
    gps_jitter:       claimData.gps_jitter             ?? 0.10,
    zone_match:       h3ZoneMatch ?? claimData.zone_match ?? 0.85,
    accel_match:      claimData.accelerometer_match     ?? 0.90,
    wifi_home:        claimData.wifi_home               ?? false,
    days_active:      claimData.days_active             ?? 30,
    depth_score:      claimData.zone_depth_score        ?? 0.75,
    is_mock_location: claimData.is_mock_location        ?? false,
    latency_seconds:  claimData.latency                 ?? 120,
    zone_claim_count: claimData.zone_claim_count        ?? 1,
  });

  // Apply compound signal boost before routing
  let score = fraudResult?.fps_score ?? fraudResult?.anomaly_score ?? 0;
  score = applyCompoundSignalBoost(
    score,
    claimData.velocity_jump        ?? false,
    claimData.accelerometer_mismatch ?? 0,
  );

  const result = {
    ...fraudResult,
    fps_score:  score,
    action:     routeClaim(score),
    trust_tier: score < 0.42 ? 'GREEN' : score < 0.65 ? 'YELLOW' : 'RED',
  };

  // Add H3 zone match info if calculated
  if (h3ZoneMatch !== null) {
    result.h3_zone_match = h3ZoneMatch;
    result.zone_match_source = 'h3';
  }

  return result;
}

// ── Stubs for device telemetry helpers (implemented in device-fingerprint-service) ──
function _sha256Placeholder(str) { return `hash_${str}`; }
async function _detectVelocityJump(tripId) { return false; }       // noqa
async function _getImuAccelDelta(tripId)   { return null; }        // noqa
async function _getBatteryTemp(tripId)     { return null; }        // noqa

module.exports = {
  scoreClaim,
  routeClaim,
  applyCompoundSignalBoost,
  computeNetworkTrustScore,
  collectTripTelemetry,
  calculateH3ZoneMatch,
  FRAUD_THRESHOLDS,
};

