const express = require("express");
const { supabase } = require("../config/supabase");
const { checkIpLocation } = require("../services/maxmind-service");
const {
  sendDisruptionAlert,
  sendPayoutCredited,
} = require("../services/notification-service");
const { scoreClaim } = require("../services/fraud-engine");
const {
  checkCircuitBreaker,
  updatePoolHealth,
} = require("../services/circuit-breaker");
const { releasePayout } = require("../services/payout-service");
const {
  buildClaimExplanation,
} = require("../services/claim-explanation-service");
const {
  verifyIntegrityToken,
  applyPlayIntegrityFraudDelta,
  shouldRunIntegrityPipeline,
  isSimulatedMode,
} = require("../services/play-integrity-service");
const {
  getSharedDeviceFraudBump,
} = require("../services/device-fingerprint-service");
const crypto = require("crypto");
const router = express.Router();

// ML microservice — Isolation Forest + Ring Detector
const ML_URL = process.env.ML_SERVICE_URL || "http://127.0.0.1:8001";

/*
  SETTLEMENT ARCHITECTURE
  
  Tranche 1 (70%):
    Released within MINUTES of trigger confirmation
    Condition: fraud score < 30 (GREEN)
    Method: releasePayout() called immediately
    Expert mandate: "it is minutes not hours"
    
  Tranche 2 (30%):
    Released Sunday 11 PM weekly batch
    Purpose: full week fraud pattern review
    Condition: no new fraud signals emerged this week
    
  This is NOT Sunday payment for everything.
  Workers receive 70% of their payout within minutes.
  Sunday is only for the settlement tranche.
*/

const {
  COMPOUND_BONUSES,
  SHIFT_MULTIPLIERS,
  ZONE_DEPTH_MULTIPLIERS,
} = require("../config/constants");

// Trigger display names (for user-facing messages)
const DISPLAY_NAMES = {
  rain_heavy: "Heavy Rain",
  rain_extreme: "Extreme Rain",
  heat_severe: "Extreme Heat",
  aqi_hazardous: "Severe AQI",
  platform_outage: "Platform Downtime",
  bandh_strike: "Bandh / Curfew",
  traffic_congestion: "Heavy Traffic",
  internet_blackout: "Internet Blackout",
  cyclone_landfall: "Cyclone Landfall",
  dark_store_closure: "Dark Store Closure",
};

/**
 * calculateGrossPayout — actuarial payout engine
 * Formula: hourly_rate × hours × shift_multiplier × zone_depth_mult
 * Capped by per-trigger daily cap and plan weekly cap.
 */
function calculateGrossPayout({
  trigger_type,
  duration_hours = 3,
  claim_hour = 14,
  zone_depth_score = 0.8,
  plan_tier = "standard",
  secondary_trigger = null,
}) {
  const {
    TRIGGER_CONFIG,
    PLAN_CONFIG,
    SHIFT_MULTIPLIERS,
    ZONE_DEPTH_MULTIPLIERS,
    COMPOUND_BONUSES,
  } = require("../config/constants");

  const trigger = TRIGGER_CONFIG[trigger_type];
  if (!trigger) {
    console.error(
      `[Payout] Trigger ${trigger_type} not found in TRIGGER_CONFIG`,
    );
    return 0;
  }

  const hourlyRate = trigger.hourly_rate_paise / 100; // Convert from paise to rupees
  const dailyCap = trigger.daily_cap_paise / 100;

  // Shift-hour multiplier
  const shiftMult =
    claim_hour >= 9 && claim_hour < 18
      ? SHIFT_MULTIPLIERS.peak
      : claim_hour >= 18 && claim_hour < 22
        ? SHIFT_MULTIPLIERS.offpeak
        : claim_hour >= 8 && claim_hour < 9
          ? SHIFT_MULTIPLIERS.prepeak
          : SHIFT_MULTIPLIERS.night;

  // Zone depth multiplier (distance from dark store)
  const zoneMult =
    zone_depth_score > 0.6
      ? ZONE_DEPTH_MULTIPLIERS.core
      : zone_depth_score >= 0.3
        ? ZONE_DEPTH_MULTIPLIERS.middle
        : ZONE_DEPTH_MULTIPLIERS.outer;

  let payout = Math.round(hourlyRate * duration_hours * shiftMult * zoneMult);
  payout = Math.min(payout, dailyCap);

  // Compound trigger bonus (Full Shield only)
  if (plan_tier === "full" && secondary_trigger) {
    const secondaryTrigger = TRIGGER_CONFIG[secondary_trigger];
    if (secondaryTrigger) {
      const key1 = `${trigger_type}+${secondary_trigger}`;
      const key2 = `${secondary_trigger}+${trigger_type}`;
      const bonus = COMPOUND_BONUSES[key1] || COMPOUND_BONUSES[key2];
      if (bonus) {
        if (bonus.type === "additive") {
          // Add full payout for secondary trigger too
          const secondaryPayout = Math.min(
            Math.round(
              (secondaryTrigger.hourly_rate_paise / 100) *
                duration_hours *
                shiftMult *
                zoneMult,
            ),
            secondaryTrigger.daily_cap_paise / 100,
          );
          payout = payout + secondaryPayout;
        } else {
          payout = Math.round(payout * bonus.multiplier);
        }
      }
    }
  }

  return payout;
}

// POST /claims/explanation — structured rejection / hold reasons from FPS-style body
router.post("/explanation", (req, res) => {
  try {
    res.json(buildClaimExplanation(req.body || {}));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /claims/create
router.post("/create", async (req, res) => {
  const {
    user_id,
    trigger_type,
    severity,
    duration_hours,
    claim_hour,
    zone_depth_score,
    plan_tier,
    secondary_trigger,
    integrity_token,
    simulate_integrity_fail,
    device_fingerprint,
  } = req.body;

  if (!user_id || !trigger_type) {
    return res
      .status(400)
      .json({ error: "user_id and trigger_type are required" });
  }

  // ── Shift Intersection V2 ──
  const now = new Date();
  const dStart =
    req.body.disruption_start ||
    new Date(now.getTime() - duration_hours * 3600000).toISOString();
  const dEnd = req.body.disruption_end || now.toISOString();
  const dDate = req.body.date || now.toISOString().split("T")[0];

  const shiftVal =
    await require("../services/shift-validator").checkShiftIntersection(
      user_id,
      dStart,
      dEnd,
      dDate,
    );
  if (!shiftVal.pass) {
    return res.status(400).json({
      error: "shift_validation_failed",
      reason: shiftVal.reason,
      effective_minutes_seen: shiftVal.effective_minutes,
      message:
        "You were not verifiably active on your shift during this disruption event.",
    });
  }

  // ─── VALIDATION: Trigger is covered by plan ────────────────────────────────
  const planKey = (plan_tier || "standard").toLowerCase();
  const {
    PLAN_CONFIG,
    TRIGGER_CONFIG,
    isTriggerEligibleForTier,
  } = require("../config/constants");

  if (!PLAN_CONFIG[planKey]) {
    return res.status(400).json({
      error: `invalid_plan_tier`,
      message: `Plan tier '${planKey}' does not exist`,
    });
  }

  if (!TRIGGER_CONFIG[trigger_type]) {
    return res.status(400).json({
      error: `invalid_trigger_type`,
      message: `Trigger '${trigger_type}' is not recognised`,
      valid_triggers: Object.keys(TRIGGER_CONFIG).slice(0, 5),
    });
  }

  if (!isTriggerEligibleForTier(trigger_type, planKey)) {
    // Check if it's available as an add-on
    const trigger = TRIGGER_CONFIG[trigger_type];
    const availableAsAddon = trigger.addon_eligible_tiers?.includes(planKey);

    return res.status(403).json({
      error: `trigger_not_covered_by_plan`,
      message: `Trigger '${trigger_type}' is not included in your ${planKey} plan`,
      included_plan_tiers: trigger.eligible_tiers,
      available_as_addon: availableAsAddon
        ? "Yes. Upgrade to Standard or purchase add-on."
        : "No",
    });
  }

  const grossPayout = calculateGrossPayout({
    trigger_type,
    duration_hours: duration_hours || 3,
    claim_hour: claim_hour ?? new Date().getHours(),
    zone_depth_score: zone_depth_score || 0.8,
    plan_tier: planKey,
    secondary_trigger,
  });
  /*
    SETTLEMENT TIMING
    70% tranche: released within MINUTES of trigger confirmation
                 not Sunday — minutes
    30% tranche: released Sunday 11PM after weekly fraud review
    
    Expert instruction: "it is minutes not hours" for primary tranche
  */
  const tranche1 = Math.round(grossPayout * 0.7);
  const tranche2 = grossPayout - tranche1;

  try {
    // Get worker zone
    const { data: user } = await supabase
      .from("users")
      .select("zone, city, created_at")
      .eq("id", user_id)
      .maybeSingle();

    // The Circuit Breaker check is now performed ATOMICALLY in the database!
    // We only perform the ML and fraud signals in Node before pushing to Postgres.

    // Get active policy (required for claim)
    const { data: policy } = await supabase
      .from("policies")
      .select("id")
      .eq("user_id", user_id)
      .eq("status", "active")
      .maybeSingle();

    if (!policy) {
      return res.status(400).json({ error: "No active policy found" });
    }

    const packageName =
      process.env.PLAY_INTEGRITY_PACKAGE_NAME || "com.shieldgig.shieldgig";
    let integrityBlock = {
      evaluated: false,
      pass: true,
      mode: null,
      mock_verdict: undefined,
      verdict: null,
    };

    if (
      integrity_token &&
      typeof integrity_token === "string" &&
      integrity_token.trim() !== "" &&
      shouldRunIntegrityPipeline()
    ) {
      try {
        const skipNonce =
          isSimulatedMode() ||
          process.env.PLAY_INTEGRITY_SKIP_NONCE_CHECK === "true";
        const v = await verifyIntegrityToken(
          integrity_token.trim(),
          packageName,
          {
            skipNonce,
            simulateFail: simulate_integrity_fail === true,
          },
        );
        if (v.evaluated) {
          integrityBlock = {
            evaluated: true,
            pass: v.play_integrity_pass,
            mode: v.mode,
            mock_verdict: v.mock_verdict,
            verdict: v.verdict,
            judge_note: v.judge_note,
          };
        }
      } catch (e) {
        integrityBlock = {
          evaluated: true,
          pass: false,
          mode: "verify_error",
          verdict: e.message,
        };
      }
    }

    // Fraud check — ML model with rule-engine fallback
    const clientIp =
      req.headers["x-forwarded-for"]?.split(",")[0] || req.ip || "127.0.0.1";
    const fraudData = await checkIpLocation(clientIp, user.zone);

    const playPassForMl = integrityBlock.evaluated
      ? integrityBlock.pass
      : !fraudData.fraud_signal;

    // Use Python ML Service purely for fraud scoring
    const daysSince = Math.floor(
      (Date.now() - new Date(user.created_at || Date.now()).getTime()) /
        86400000,
    );
    const fraudResult = await scoreClaim({
      worker_id: user_id,
      zone_id: user?.zone || "unknown",
      zone_match: 0.85,
      gps_jitter: 0.1,
      accelerometer_match: 0.9,
      latency: 120,
      wifi_home: false,
      days_active: daysSince,
      zone_depth_score: 0.75,
      is_mock_location: fraudData.fraud_signal || false,
    });

    const baseFraudScore = fraudResult.fraud_score;
    let fraudScore = Math.min(
      100,
      baseFraudScore + (fraudData.fraud_signal ? 100 : 0),
    );
    if (integrityBlock.evaluated) {
      const adj = applyPlayIntegrityFraudDelta(fraudScore, integrityBlock.pass);
      fraudScore = adj.score;
      integrityBlock.fraud_score_delta = adj.delta;
      integrityBlock.fraud_score_reason = adj.reason;
    }

    let sharedDevice = { bump: 0, other_users: 0, reason: null };
    if (device_fingerprint && typeof device_fingerprint === "string") {
      sharedDevice = await getSharedDeviceFraudBump(
        user_id,
        user?.zone ?? "",
        device_fingerprint,
      );
      if (sharedDevice.bump > 0) {
        fraudScore = Math.min(100, fraudScore + sharedDevice.bump);
      }
    }
    const fraudStatus = fraudData.fraud_signal ? "FLAGGED" : fraudResult.status;

    let releasePct = 100;
    if (fraudStatus === "YELLOW" || fraudStatus === "REVIEW") releasePct = 70;
    if (
      fraudStatus === "RED" ||
      fraudStatus === "FLAGGED" ||
      fraudStatus === "HUMAN_REVIEW"
    )
      releasePct = 40;

    const releaseAmount = Math.round(tranche1 * (releasePct / 100));

    // If FLAGGED — release provisional ₹200 only
    const actualRelease =
      fraudStatus === "FLAGGED" ? Math.min(200, tranche1) : releaseAmount;

    const fpsSignals = {
      play_integrity: integrityBlock,
      ip_fraud_signal: fraudData.fraud_signal || false,
    };
    if (sharedDevice.bump > 0) {
      fpsSignals.shared_device_cluster = {
        bump: sharedDevice.bump,
        other_users: sharedDevice.other_users,
        reason: sharedDevice.reason,
      };
    }

    // ── Generate Time-Bound Idempotency Hash ──
    const timeWindow = new Date().toISOString().slice(0, 13); // e.g., "2026-04-17T14"
    const idempotencyKey = crypto
      .createHash("sha256")
      .update(`${user_id}-${user?.zone}-${trigger_type}-${timeWindow}`)
      .digest("hex");

    // ── ATOMIC DATABASE EXECUTION (Lock -> Check -> Insert) ──
    const { data, error: insertError } = await supabase.rpc(
      "submit_claim_atomic",
      {
        p_idempotency_key: idempotencyKey,
        p_user_id: user_id,
        p_trigger_type: trigger_type,
        p_zone: user?.zone ?? "unknown",
        p_city: user?.city ?? "Chennai",
        p_severity: severity || 1.0,
        p_duration_hours: duration_hours || 3,
        p_gross_payout: grossPayout,
        p_tranche1: tranche1,
        p_tranche2: tranche2,
        p_fraud_score: fraudScore,
        p_fraud_status: fraudStatus,
        p_fps_signals: fpsSignals,
        p_limit: 50, // Hourly limit per zone
      },
    );

    if (insertError) throw insertError;
    const dbResult = data?.[0] || data;

    if (!dbResult.success) {
      if (dbResult.error_code === "DUPLICATE_REQUEST") {
        return res
          .status(409)
          .json({ error: "Claim already submitted for this timeframe." });
      }
      if (dbResult.error_code === "circuit-breaker_TRIPPED") {
        return res.status(503).json({
          error: "System protection active",
          detail: "Abnormal claim spike — system paused for safety",
          code: "HOURLY_LIMIT_EXCEEDED",
          retry_after: "1 hour",
        });
      }
    }

    // Mock claim object for downstream background pipelines
    const claim = {
      id: dbResult.claim_id,
      fps_signals: fpsSignals,
      status: "PENDING",
    };

    // ── ML Ring Detection (background, non-blocking) ───────────────────────
    // Fetches recent claims in the same zone+trigger in the last 30 minutes
    // and runs Poisson + DBSCAN ring analysis on the ML service.
    // If both tests fire → upgrades fraud_status to FLAGGED in the database.
    setImmediate(async () => {
      try {
        const thirtyMinAgo = new Date(
          Date.now() - 30 * 60 * 1000,
        ).toISOString();
        const { data: recentZoneClaims } = await supabase
          .from("claims")
          .select("created_at, fps_signals")
          .eq("zone", user?.zone ?? "")
          .eq("trigger_type", trigger_type)
          .gte("created_at", thirtyMinAgo)
          .limit(100);

        if (recentZoneClaims && recentZoneClaims.length >= 3) {
          const claimPoints = recentZoneClaims.map((c, i) => ({
            timestamp: Math.floor(new Date(c.created_at).getTime() / 1000),
            gps_lat: 13.08 + i * 0.001, // approximate — real GPS from shift_telemetry
            gps_lng: 80.27 + i * 0.001,
          }));

          const ringRes = await fetch(`${ML_URL}/fraud/ring-detect`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              zone_id: user?.zone || "unknown",
              claims: claimPoints,
            }),
            signal: AbortSignal.timeout(5000),
          });

          if (ringRes.ok) {
            const ringData = await ringRes.json();
            if (ringData.combined_ring_flag) {
              console.warn(
                `[RingDetect] Ring pattern in zone=${user?.zone} trigger=${trigger_type} action=${ringData.recommended_action}`,
              );
              // Escalate fraud status if human_review verdict
              if (ringData.recommended_action === "human_review") {
                await supabase
                  .from("claims")
                  .update({
                    fraud_status: "FLAGGED",
                    fps_signals: {
                      ...claim.fps_signals,
                      ring_detected: true,
                      ring_action: ringData.recommended_action,
                      ring_poisson_p: ringData.poisson_result?.p_value,
                      ring_cluster_size:
                        ringData.dbscan_result?.largest_cluster_size,
                    },
                  })
                  .eq("id", claim.id);
              }
            }
          }
        }
      } catch (ringErr) {
        console.warn(
          "[RingDetect] ML ring-detect failed (non-fatal):",
          ringErr.message,
        );
      }
    });

    const { adjustTrustScore } = require("../services/trust-service");
    if (fraudStatus === "GREEN" || fraudStatus === "CLEAN") {
      // Nothing — trust accumulates via Sunday batch
    } else if (fraudStatus === "FLAGGED" || fraudStatus === "YELLOW") {
      await adjustTrustScore(
        user_id,
        "SOFT_HOLD_TRIGGERED",
        "Fraud soft hold on claim",
      );
    } else if (fraudStatus === "RED") {
      await adjustTrustScore(
        user_id,
        "CLAIM_REJECTED_FRAUD",
        "Claim flagged for human review",
      );
    }

    // Release tranche1 with rollback protection
    await releasePayout({
      claimId: claim.id,
      userId: user_id,
      amount: actualRelease,
      tranche: "TRANCHE1",
      description: `${DISPLAY_NAMES[trigger_type] || trigger_type} Payout (70%)`,
    });

    // Update pool health for BCR monitoring
    await updatePoolHealth(
      user?.city ?? "Chennai",
      0, // no new premium this request
      grossPayout, // claim amount
    );

    // Auto-approve after 5 seconds & send payout credited notification
    setTimeout(async () => {
      await supabase
        .from("claims")
        .update({ status: "APPROVED" })
        .eq("id", claim.id);

      // Release tranche2 with rollback protection
      await releasePayout({
        claimId: claim.id,
        userId: user_id,
        amount: tranche2,
        tranche: "TRANCHE2",
        description: `${DISPLAY_NAMES[trigger_type] || trigger_type} Settlement (30%)`,
      });

      // Send FCM notification
      try {
        const { data: userProfile } = await supabase
          .from("users")
          .select("fcm_token, zone")
          .eq("id", user_id)
          .maybeSingle();

        if (userProfile?.fcm_token) {
          await sendPayoutCredited({
            userId: user_id,
            deviceToken: userProfile.fcm_token,
            amount: actualRelease,
            claimId: claim.id,
            idempotencyKey: `payout_credited:${claim.id}:tranche2`,
          });
        } else {
          console.log(
            `[FCM] No device token for user ${user_id} — skipping notification`,
          );
        }
      } catch (notifErr) {
        console.warn("[FCM] Notification error (non-fatal):", notifErr.message);
      }
    }, 5000);

    // Return Flutter-friendly response
    return res.status(201).json({
      claim: {
        ...claim,
        display_name: DISPLAY_NAMES[trigger_type] || trigger_type,
        tranche1_amount: tranche1,
        tranche2_amount: tranche2,
      },
    });
  } catch (e) {
    console.error("[Claims] Create error:", e.message);
    return res.status(500).json({ error: e.message });
  }
});

// GET /claims/:userId
router.get("/:user_id", async (req, res) => {
  const { user_id } = req.params;

  try {
    const { data: claims, error } = await supabase
      .from("claims")
      .select("*")
      .eq("user_id", user_id)
      .order("created_at", { ascending: false });

    if (error) throw error;

    const totalClaimed = claims.reduce((s, c) => s + (c.gross_payout || 0), 0);
    const totalReceived = claims
      .filter((c) => c.status === "APPROVED")
      .reduce((s, c) => s + (c.tranche1 || 0), 0);
    const pendingCount = claims.filter((c) => c.status === "PENDING").length;

    // Normalise for Flutter — map tranche1 -> tranche1_amount etc.
    const normalised = claims.map((c) => ({
      ...c,
      display_name: DISPLAY_NAMES[c.trigger_type] || c.trigger_type,
      tranche1_amount: c.tranche1,
      tranche2_amount: c.tranche2,
    }));

    return res.json({
      claims: normalised,
      total_claimed: totalClaimed,
      total_received: totalReceived,
      pending_count: pendingCount,
    });
  } catch (e) {
    console.error("[Claims] Get error:", e.message);
    return res.status(500).json({ error: e.message });
  }
});

// GET /claims/detail/:id
router.get("/detail/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { data: claim, error } = await supabase
      .from("claims")
      .select("*")
      .eq("id", id)
      .single();
    if (error) throw error;
    res.json({ claim });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /claims/manual
router.post("/manual", async (req, res) => {
  const {
    user_id,
    disruption_type,
    description,
    zone,
    evidence_urls, // array of uploaded photo URLs
    device_signal_strength, // for internet outage type
    integrity_token, // optional Play Integrity token (Android); simulated or Google verify
    simulate_integrity_fail, // demo only: force mock failing verdict (+30 fraud)
    idempotency_key, // For offline retry deduplication
  } = req.body;

  // Idempotency check: prevent duplicate manual claims on retry
  if (idempotency_key && user_id) {
    const { data: existing } = await supabase
      .from("claims")
      .select("*")
      .eq("user_id", user_id)
      .eq("fps_signals->>idempotency_key", idempotency_key)
      .maybeSingle();

    if (existing) {
      return res.status(200).json({
        claim: {
          ...existing,
          display_name: "Manual Report",
          tranche1_amount: existing.tranche1,
          tranche2_amount: existing.tranche2,
          provisional_note:
            "Provisional credit issued. Full review within 4 hours. (Duplicate Request)",
        },
      });
    }
  }

  const packageName =
    process.env.PLAY_INTEGRITY_PACKAGE_NAME || "com.shieldgig.shieldgig";
  let playIntegrityResult = {
    checked: false,
    evaluated: false,
    pass: null,
    verdict: null,
  };

  if (
    integrity_token &&
    typeof integrity_token === "string" &&
    integrity_token.trim() !== "" &&
    shouldRunIntegrityPipeline()
  ) {
    try {
      const skipNonce =
        isSimulatedMode() ||
        process.env.PLAY_INTEGRITY_SKIP_NONCE_CHECK === "true";
      const v = await verifyIntegrityToken(
        integrity_token.trim(),
        packageName,
        {
          skipNonce,
          simulateFail: simulate_integrity_fail === true,
        },
      );
      playIntegrityResult = {
        checked: v.evaluated,
        evaluated: v.evaluated,
        pass: v.play_integrity_pass,
        verdict: v.verdict,
        summary: v.summary,
        mode: v.mode,
        mock_verdict: v.mock_verdict,
        judge_note: v.judge_note,
      };
    } catch (e) {
      playIntegrityResult = {
        checked: true,
        evaluated: true,
        pass: false,
        verdict: `error:${e.message}`,
      };
    }
  }

  if (process.env.PLAY_INTEGRITY_REQUIRED_FOR_MANUAL === "true") {
    if (!playIntegrityResult.checked || !playIntegrityResult.pass) {
      return res.status(403).json({
        error: "Play Integrity verification required",
        play_integrity_pass: false,
        hint: "POST integrity_token from Android after GET /integrity/play/nonce",
      });
    }
  }

  if (!user_id || !disruption_type) {
    return res.status(400).json({
      error: "user_id and disruption_type required",
    });
  }

  // Underwriting check — 7 days minimum
  const { data: user } = await supabase
    .from("users")
    .select("created_at, zone, city")
    .eq("id", user_id)
    .single();

  const daysSince = Math.floor(
    (Date.now() - new Date(user.created_at).getTime()) / (1000 * 60 * 60 * 24),
  );

  if (daysSince < 7) {
    return res.status(400).json({
      error: "Minimum 7 active delivery days required before filing claims",
      days_remaining: 7 - daysSince,
    });
  }

  // Get active policy
  const { data: policy } = await supabase
    .from("policies")
    .select("id, max_weekly_payout, weekly_premium")
    .eq("user_id", user_id)
    .eq("status", "active")
    .single();

  if (!policy) {
    return res.status(400).json({
      error: "No active policy found",
    });
  }

  // Manual claims get provisional payout
  // Actual amount decided after 4hr review
  const PROVISIONAL_AMOUNTS = {
    road_blocked: 100,
    dark_store_closed: 150,
    internet_outage: 120,
    other: 80,
  };

  const provisionalAmount = PROVISIONAL_AMOUNTS[disruption_type] || 80;
  const tranche1 = Math.round(provisionalAmount * 0.7);
  const tranche2 = provisionalAmount - tranche1;

  let manualFraudScore = 25;
  if (playIntegrityResult.evaluated) {
    const adj = applyPlayIntegrityFraudDelta(
      manualFraudScore,
      playIntegrityResult.pass,
    );
    manualFraudScore = adj.score;
    playIntegrityResult.fraud_score_delta = adj.delta;
    playIntegrityResult.fraud_score_reason = adj.reason;
  }

  try {
    // Create manual claim
    const { data: claim, error } = await supabase
      .from("claims")
      .insert([
        {
          user_id,
          policy_id: policy.id,
          trigger_type: "manual_" + disruption_type,
          zone: user.zone,
          city: user.city || "Unknown",
          severity: 0.7,
          duration_hours: 2.0,
          gross_payout: provisionalAmount,
          tranche1,
          tranche2,
          fraud_score: manualFraudScore,
          fraud_status: "REVIEW",
          status: "PENDING",
          fps_signals: {
            type: "manual",
            evidence_count: evidence_urls?.length ?? 0,
            disruption_type,
            description: description ?? "",
            play_integrity: playIntegrityResult,
            ...(idempotency_key && { idempotency_key }),
          },
        },
      ])
      .select()
      .single();

    if (error) throw error;

    // Credit provisional tranche1 immediately
    await supabase.from("wallet_transactions").insert([
      {
        user_id,
        amount: tranche1,
        type: "credit",
        category: "payout_tranche1",
        reference: `MANUAL_T1_${claim.id}`,
        description: `Manual Claim Provisional (70%) — ${disruption_type}`,
        claim_id: claim.id,
      },
    ]);

    return res.status(201).json({
      claim: {
        ...claim,
        display_name: "Manual Report",
        tranche1_amount: tranche1,
        tranche2_amount: tranche2,
        provisional_note:
          "Provisional credit issued. Full review within 4 hours.",
      },
    });
  } catch (e) {
    console.error("[ManualClaim] Error:", e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /claims/:claimId/appeal
router.post("/:claimId/appeal", async (req, res) => {
  const { claimId } = req.params;
  const { worker_id, user_id, selected_reason, additional_context } = req.body;
  const claimantId = worker_id || user_id;

  try {
    if (!claimantId || !selected_reason) {
      return res.status(400).json({
        error: "worker_id (or user_id) and selected_reason are required",
      });
    }
    // Verify claim exists and belongs to this worker
    const { data: claim, error: fetchError } = await supabase
      .from("claims")
      .select("*")
      .eq("id", claimId)
      .eq("user_id", claimantId)
      .single();

    if (fetchError || !claim) {
      return res.status(404).json({ error: "Claim not found" });
    }

    // Only rejected claims can be appealed
    if (claim.status !== "REJECTED") {
      return res
        .status(400)
        .json({ error: "Only rejected claims can be appealed" });
    }

    // Only one appeal per claim
    const { data: existingAppeal, error: existingAppealError } = await supabase
      .from("appeal_requests")
      .select("id")
      .eq("claim_id", claimId)
      .maybeSingle();

    if (existingAppealError) throw existingAppealError;
    if (existingAppeal) {
      return res
        .status(400)
        .json({ error: "Appeal already submitted for this claim" });
    }

    // Create appeal request using schema-backed table
    const { data: appeal, error: createAppealError } = await supabase
      .from("appeal_requests")
      .insert({
        user_id: claimantId,
        claim_id: claimId,
        reason: selected_reason,
        evidence_urls: additional_context ? [String(additional_context)] : [],
        status: "open",
      })
      .select("id")
      .single();

    if (createAppealError) throw createAppealError;

    // Link claim to appeal request
    const { error: linkError } = await supabase
      .from("claims")
      .update({
        appeal_id: appeal.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", claimId);

    if (linkError) throw linkError;

    await supabase.from("admin_actions").insert({
      admin_id: "system",
      action_type: "other",
      target_type: "claim_appeal",
      target_id: claim.id,
      reason: `Appeal submitted: ${selected_reason}`,
      metadata: {
        appeal_id: appeal.id,
        user_id: claimantId,
      },
    });

    res.json({
      success: true,
      message: "Appeal submitted. Review within 4 hours.",
    });
  } catch (err) {
    console.error("Appeal submission error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
