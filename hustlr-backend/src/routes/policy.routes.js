const express = require("express");
const crypto = require("crypto");
const { supabase } = require("../config/supabase");
const { PLAN_CONFIG } = require("../config/constants");
const mlService = require("../services/ml-service");
const router = express.Router();
const { getShadowSummary } = require("../services/shadow-policy-service");
const { requireSession } = require("../middleware/session-auth");

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MOCK_ID_RE = /^(DEMO_|demo-|mock-)/;
const ALLOW_MOCK_POLICY_SYNC = String(
  process.env.ALLOW_MOCK_POLICY_SYNC || "",
).toLowerCase() === "true";

function toSyntheticUuid(seed) {
  const hex = crypto.createHash("md5").update(seed).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function resolveBackendUserId(rawUserId) {
  const source = String(rawUserId || "").trim();
  if (UUID_RE.test(source)) {
    return {
      dbUserId: source,
      isSynthetic: false,
      externalUserId: source,
    };
  }

  if (ALLOW_MOCK_POLICY_SYNC && MOCK_ID_RE.test(source)) {
    return {
      dbUserId: toSyntheticUuid(`mock-user:${source}`),
      isSynthetic: true,
      externalUserId: source,
    };
  }

  return null;
}

async function ensureSyntheticUserExists({
  dbUserId,
  externalUserId,
  planTier = "standard",
}) {
  const slug = String(externalUserId || "demo-user").toLowerCase();
  const tail = dbUserId.replace(/-/g, "").slice(0, 10);

  const { data: existing } = await supabase
    .from("users")
    .select("id")
    .eq("id", dbUserId)
    .maybeSingle();
  if (existing?.id) return;

  const { error: insertError } = await supabase.from("users").insert([
    {
      id: dbUserId,
      name: `Demo ${slug.slice(0, 16)}`,
      phone: `mock-${tail}`,
      zone: planTier === "full" ? "Adyar" : "Velachery",
      city: "Chennai",
      platform: "Demo",
      iss_score: 60,
      days_active: 14,
      active_days_last_30: 14,
      onboarding_complete: true,
    },
  ]);
  if (insertError) throw insertError;
}

// GET /policies/shadow/:user_id — live shadow payout estimate from disruption_events
router.get("/shadow/:user_id", async (req, res) => {
  try {
    const days = Math.min(
      90,
      Math.max(1, parseInt(req.query.days || "14", 10)),
    );
    const out = await getShadowSummary(req.params.user_id, days);
    if (out.error === "User not found") return res.status(404).json(out);
    if (out.error) return res.status(400).json(out);
    res.json(out);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post("/create", async (req, res) => {
  try {
    const { user_id, plan_tier, payment_source } = req.body;
    const isExternalPayment = payment_source === 'razorpay';
    const userRef = resolveBackendUserId(user_id);

    // ───  VALIDATION 1: Plan tier exists ────────────────────────────────────
    if (!PLAN_CONFIG[plan_tier]) {
      return res.status(400).json({
        error: "invalid_plan_tier",
        message: `Plan tier '${plan_tier}' does not exist. Valid options: basic, standard, full.`,
      });
    }

    // ─── VALIDATION 2: Mock IDs (offline onboarding) are not valid UUIDs ────
    if (!userRef) {
      return res.status(400).json({
        error: "invalid_user_id",
        message:
          "Invalid user_id. Use a live UUID, or enable ALLOW_MOCK_POLICY_SYNC=true for demo IDs.",
      });
    }
    const dbUserId = userRef.dbUserId;
    if (userRef.isSynthetic) {
      await ensureSyntheticUserExists({
        dbUserId,
        externalUserId: userRef.externalUserId,
        planTier: plan_tier,
      });
    }

    // Fetch user profile. Use broad select to avoid runtime failures when
    // schema varies (some deployments use `days_active` instead of
    // `active_days_last_30`).
    const { data: user, error: userError } = await supabase
      .from("users")
      .select("*")
       .eq("id", dbUserId)
      .single();
    if (userError) throw userError;

    const { ACTIVITY_LOADING } = require("../config/constants");
    const activeActivity =
      Number(user.active_days_last_30 ?? user.days_active ?? 0) || 0;
    const activityKey =
      activeActivity >= 20
        ? "above_20_days"
        : activeActivity >= 7
          ? "between_7_20"
          : activeActivity >= 5
            ? "below_7_days"
            : "below_5_days";

    // ─── UNDERWRITING: Workers with < 5 days -> Lower Tier (Basic only) ───
    if (activeActivity < 5 && plan_tier !== 'basic') {
      return res.status(403).json({
        error: "tier_restricted",
        message: "As a new partner (under 5 active days), you are only eligible for the Basic Shield plan. Complete more deliveries to unlock Standard and Full Shield.",
        active_days: activeActivity,
      });
    }

    // Skip activity check for external Razorpay payments (to avoid blocking demo/hackathon flow)
    if (!isExternalPayment && !ACTIVITY_LOADING[activityKey]) {
      return res.status(402).json({
        error: "insufficient_activity",
        message: `Minimum 7 days activity required. You have ${activeActivity} days. Please come back after working more days.`,
        activity_days: activeActivity,
      });
    }

    // Calculate premium via Python ML service
    const currentMonth = new Date().getMonth();
    const isMonsoonSeason = currentMonth >= 9; // Oct–Dec (0-indexed: 9, 10, 11)

    let premiumResult;
    try {
      premiumResult = await mlService.getPremium({
        plan_tier,
        zone: user.zone,
        iss_score: user.iss_score || 50,
        activity_loading: ACTIVITY_LOADING[activityKey] || 1.0,
        is_monsoon_season: isMonsoonSeason,
        previous_premium: 0,
      });
    } catch (mlError) {
      console.warn(
        `[Policy] ML premium fallback for user ${dbUserId}: ${mlError.message || mlError}`,
      );
      const fallbackBase =
        PLAN_CONFIG[plan_tier].weekly_premium_paise / 100;
      premiumResult = {
        base_premium: fallbackBase,
        zone_adjustment: 0,
        final_premium: fallbackBase,
      };
    }


    // Ensure premium is a rounded integer for DB (paise to rupees)
    let finalPremium = Math.round(
      premiumResult.final_premium ||
        PLAN_CONFIG[plan_tier].weekly_premium_paise / 100,
    );

    // SAFETY CLAMP: Prevent DB constraint violations until SQL patch is applied
    // basic: 30-40, standard: 45-55, full: 70-85
    if (plan_tier === "basic") finalPremium = Math.min(40, Math.max(30, finalPremium));
    if (plan_tier === "standard") finalPremium = Math.min(55, Math.max(45, finalPremium));
    if (plan_tier === "full") finalPremium = Math.min(85, Math.max(70, finalPremium));

    // ─── QUARTERLY LOCK: Enforce upgrade-only within the commitment period ────
    const TIER_RANK = { basic: 1, standard: 2, full: 3 };
    const { data: existingPolicy } = await supabase
      .from("policies")
      .select("id, plan_tier, coverage_end, status")
      .eq("user_id", dbUserId)
      .eq("status", "active")
      .maybeSingle();

    if (existingPolicy) {
      const existingRank = TIER_RANK[existingPolicy.plan_tier] ?? 0;
      const newRank = TIER_RANK[plan_tier] ?? 0;
      const commitmentEnd = new Date(existingPolicy.coverage_end);
      const now = new Date();
      const isInCommitmentPeriod = commitmentEnd > now;

      if (isInCommitmentPeriod && newRank <= existingRank) {
        const planLabel = existingPolicy.plan_tier.charAt(0).toUpperCase() + existingPolicy.plan_tier.slice(1);
        const daysLeft = Math.ceil((commitmentEnd - now) / (1000 * 60 * 60 * 24));
        return res.status(403).json({
          error: "quarterly_lock",
          message: `You are in a 91-day commitment period for your ${planLabel} Shield plan. Downgrading is not permitted — you can upgrade to a higher tier at any time. Your current plan ends in ${daysLeft} day(s).`,
          commitment_end: existingPolicy.coverage_end,
          days_remaining: daysLeft,
          current_tier: existingPolicy.plan_tier,
          requested_tier: plan_tier,
        });
      }
    }

    // Deactivate any existing active policy (upgrade path or post-commitment new purchase)
    await supabase
      .from("policies")
      .update({ status: "cancelled" })
      .eq("user_id", dbUserId)
      .eq("status", "active");


    const { data: policy, error: policyError } = await supabase
      .from("policies")
      .insert([
        {
          user_id: dbUserId,
          plan_tier,
          base_premium: Math.round(
            premiumResult.base_premium ||
              PLAN_CONFIG[plan_tier].weekly_premium_paise / 100,
          ),
          zone_adjustment: Math.round(premiumResult.zone_adjustment || 0),
          iss_adjustment: 0,
          weekly_premium: finalPremium,
          max_weekly_payout: PLAN_CONFIG[plan_tier].weekly_cap_paise / 100,
          max_daily_payout: PLAN_CONFIG[plan_tier].max_daily_payout_paise / 100,
          status: "active",
        },
      ])
      .select()
      .single();
    if (policyError) throw policyError;

    if (isExternalPayment) {
      // ── External payment (Razorpay): credit the wallet to record the payment ──
      // This keeps wallet history accurate without blocking activation
      try {
        await supabase.from("wallet_transactions").insert([
          {
            user_id: dbUserId,
            amount: finalPremium,
            type: "credit",
            category: "razorpay_topup",
            description: `Razorpay payment for ${plan_tier} Shield`,
            reference: `razorpay_policy_${policy.id}`,
          },
        ]);
      } catch (err) {
        // Non-fatal — wallet credit log is best-effort
        console.warn("[Policy] Failed to log Razorpay credit:", err.message);
      }
    } else {
      // ── Internal wallet payment: check balance BEFORE debiting ──────────────
      const { data: walletBal } = await supabase
        .from("wallet_balances")
        .select("balance")
         .eq("user_id", dbUserId)
        .maybeSingle();

      const currentBalance = walletBal?.balance ?? 0;
      if (currentBalance < finalPremium) {
        // Insufficient funds — suspend instead of crashing
        await supabase
          .from("policies")
          .update({ status: "suspended" })
          .eq("id", policy.id);
        console.warn(
          `[Policy] Insufficient balance for ${user_id}: ₹${currentBalance} < ₹${finalPremium}. Policy suspended.`,
        );
        return res.status(402).json({
          error: "insufficient_balance",
          message: `Wallet balance ₹${currentBalance} is below required premium ₹${finalPremium}. Please top up to activate coverage.`,
          policy_status: "suspended",
          policy_id: policy.id,
        });
      }

      // Deduct the final premium from the user's wallet
      await supabase.from("wallet_transactions").insert([
        {
          user_id: dbUserId,
          amount: finalPremium,
          type: "debit",
          category: "premium",
          description: `Premium for ${plan_tier} Shield`,
          reference: `policy_${policy.id}`,
        },
      ]);
    }

    console.log(
      `[Policy] Created policy ${policy.id} (source: ${payment_source || 'wallet'}). Premium: ₹${finalPremium}`,
    );

    res.json({
      policy,
      user_ref: {
        source_user_id: user_id,
        stored_user_id: dbUserId,
        synthetic: userRef.isSynthetic,
      },
      premium_breakdown: {
        base_premium: premiumResult.base_premium || 49,
        zone_adjustment: premiumResult.zone_adjustment || 0,
        iss_adjustment: 0,
        monsoon_surcharge_pct: 0,
        monsoon_surcharge: 0,
        forward_risk_pct: 0,
        forward_risk_surcharge: 0,
        final_with_surcharge: finalPremium,
      },
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});


router.get("/:user_id", async (req, res) => {
  try {
    const userRef = resolveBackendUserId(req.params.user_id);
    if (!userRef)
      return res.status(200).json({ policy: null, history: [] });
    const dbUserId = userRef.dbUserId;
    const { data: policy, error } = await supabase
      .from("policies")
      .select("*")
       .eq("user_id", dbUserId)
      .eq("status", "active")
      .maybeSingle();
    if (error) throw error;
    const { data: history, error: historyError } = await supabase
      .from("policies")
      .select("*")
       .eq("user_id", dbUserId)
      .order("created_at", { ascending: false });
    if (historyError) throw historyError;
    res.json({ policy, history: history || [] });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.patch("/:id/upgrade", async (req, res) => {
  try {
    const { id } = req.params;
    const { new_plan_tier, risk_score = 0.5 } = req.body;

    const { data: existingPolicy, error: policyFetchError } = await supabase
      .from("policies")
      .select("user_id, plan_tier")
      .eq("id", id)
      .single();
    if (policyFetchError) throw policyFetchError;

    const { data: user, error: userError } = await supabase
      .from("users")
      .select("zone, iss_score")
      .eq("id", existingPolicy.user_id)
      .single();
    if (userError) throw userError;

    const premiumResult = await mlService.getPremium({
      plan_tier: new_plan_tier,
      zone: user.zone,
      iss_score: 50,
      previous_premium: existingPolicy.weekly_premium || 0,
    });

    const { data: updated_policy, error: updateError } = await supabase
      .from("policies")
      .update({
        plan_tier: new_plan_tier,
        base_premium: premiumResult.base_premium || 49,
        zone_adjustment: premiumResult.zone_adjustment || 0,
        iss_adjustment: 0,
        weekly_premium: premiumResult.final_premium,
        max_weekly_payout: PLAN_CONFIG[new_plan_tier]?.max_payout || 150,
      })
      .eq("id", id)
      .select()
      .single();

    if (updateError) throw updateError;

    res.json({
      updated_policy,
      premium_breakdown: {
        base_premium: premiumResult.base_premium || 49,
        zone_adjustment: premiumResult.zone_adjustment || 0,
        iss_adjustment: 0,
        final_premium: premiumResult.final_premium,
        monsoon_surcharge_pct: 0,
        monsoon_surcharge: 0,
        forward_risk_pct: 0,
        forward_risk_surcharge: 0,
        final_with_surcharge: premiumResult.final_premium,
      },
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ADD RIDER - with tier-lock validation
router.post("/riders/add", requireSession, async (req, res) => {
  const { policy_id, rider_type, premium_per_week } = req.body;

  try {
    // 1. Check tier eligibility
    const { data: policy } = await supabase
      .from("policies")
      .select("plan_tier, commitment_end")
      .eq("id", policy_id)
      .single();

    if (!policy) {
      return res.status(404).json({ error: "Policy not found" });
    }

    const requiresFull = ["cyclone_cover", "traffic_congestion"];
    const requiresStandard = [
      "internet_blackout",
      "curfew_strike",
      "accident_blockspot",
    ];

    if (requiresFull.includes(rider_type) && policy.plan_tier !== "full") {
      return res.status(403).json({
        error: `The ${rider_type} rider requires the Full Shield plan.`,
      });
    }

    if (requiresStandard.includes(rider_type) && policy.plan_tier === "basic") {
      return res.status(403).json({
        error: `The ${rider_type} rider requires at least the Standard Shield plan.`,
      });
    }

    // 2. Insert the rider, locking its end date to the policy's quarterly end date
    const blackoutEnd = new Date(
      Date.now() + 72 * 60 * 60 * 1000,
    ).toISOString();
    const { data: rider, error } = await supabase
      .from("riders")
      .insert({
        policy_id,
        rider_type,
        premium_per_week: premium_per_week || 0,
        effective_to: policy.commitment_end, // Inherited directly from the parent policy
        blackout_until: blackoutEnd, // 72-hour anti-gaming blackout
        start_date: new Date().toISOString().split("T")[0],
        end_date: policy.commitment_end,
        blackout_end: blackoutEnd,
        status: "active",
      })
      .select();

    if (error) return res.status(500).json({ error: error.message });
    res
      .status(200)
      .json({ success: true, rider: rider[0], blackout_until: blackoutEnd });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// REMOVE RIDER
router.delete("/:id/riders/:riderId", async (req, res) => {
  try {
    const { id, riderId } = req.params;

    const { data: rider, error: riderError } = await supabase
      .from("riders")
      .update({ status: "cancelled" })
      .eq("id", riderId)
      .eq("policy_id", id)
      .select()
      .single();

    if (riderError) throw riderError;

    if (!rider) {
      return res.status(404).json({ error: "Rider not found" });
    }

    res.json({
      rider,
      message: "Rider cancelled successfully",
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET POLICY RIDERS
router.get("/:id/riders", async (req, res) => {
  try {
    const { id } = req.params;

    const { data: riders, error } = await supabase
      .from("riders")
      .select("*")
      .eq("policy_id", id)
      .eq("status", "active")
      .order("created_at", { ascending: false });

    if (error) throw error;

    res.json({ riders });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// RENEW POLICY - quarterly renewal system
router.post("/:id/renew", requireSession, async (req, res) => {
  const { id } = req.params;
  const userId = req.authUserId;

  try {
    // 1. Fetch current policy and ensure they own it
    const { data: policy, error: fetchErr } = await supabase
      .from("policies")
      .select("*")
      .eq("id", id)
      .eq("user_id", userId)
      .single();

    if (fetchErr || !policy)
      return res.status(404).json({ error: "Policy not found" });
    if (policy.status !== "active")
      return res
        .status(400)
        .json({ error: "Only active policies can be renewed" });

    // 2. Lock Wallet & Deduct Premium Safely (Using the DB constraints we built)
    const { error: walletErr } = await supabase
      .from("wallet_transactions")
      .insert({
        user_id: userId,
        amount: policy.weekly_premium,
        type: "debit",
        category: "premium",
        description: "Quarterly policy renewal deduction",
      });

    if (walletErr) {
      // Our DB constraint caught an insufficient balance
      await supabase
        .from("policies")
        .update({ status: "suspended" })
        .eq("id", id);
      return res
        .status(402)
        .json({ error: "Insufficient funds. Policy suspended." });
    }

    // 3. Extend the Commitment by 91 days
    const newCommitmentEnd = new Date(policy.commitment_end);
    newCommitmentEnd.setDate(newCommitmentEnd.getDate() + 91);

    const { data: updatedPolicy, error: updateErr } = await supabase
      .from("policies")
      .update({
        commitment_end: newCommitmentEnd.toISOString().split("T")[0],
        updated_at: new Date().toISOString(),
      })
      .eq("id", id)
      .select();

    if (updateErr) throw updateErr;

    // 4. Log the audit trail
    await supabase.from("renewal_history").insert({
      user_id: userId,
      policy_id: id,
      old_commitment_end: policy.commitment_end,
      new_commitment_end: newCommitmentEnd.toISOString().split("T")[0],
      weekly_premium: policy.weekly_premium,
      renewal_type: "manual",
      renewed_at: new Date().toISOString(),
    });

    res.status(200).json({ success: true, policy: updatedPolicy[0] });
  } catch (err) {
    res
      .status(500)
      .json({ error: "Failed to renew policy", details: err.message });
  }
});

// GET RENEWAL HISTORY
router.get("/:id/renewal-history", async (req, res) => {
  try {
    const { id } = req.params;

    const { data: history, error } = await supabase
      .from("renewal_history")
      .select("*")
      .eq("policy_id", id)
      .order("renewed_at", { ascending: false });

    if (error) throw error;

    res.json({ history });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET ELIGIBLE RIDERS FOR PLAN TIER
router.get("/riders/available/:planTier", async (req, res) => {
  try {
    const { planTier } = req.params;

    const allRiders = [
      {
        type: "cyclone_cover",
        name: "Cyclone Cover",
        description: "Coverage for cyclone-related disruptions",
        required_tier: "full",
      },
      {
        type: "internet_blackout",
        name: "Internet Blackout",
        description: "Coverage for internet service disruptions",
        required_tier: "standard",
      },
      {
        type: "curfew_strike",
        name: "Curfew & Strike",
        description: "Coverage for curfew and strike disruptions",
        required_tier: "standard",
      },
      {
        type: "accident_blockspot",
        name: "Accident Blockspot",
        description: "Coverage for traffic accident disruptions",
        required_tier: "standard",
      },
      {
        type: "traffic_congestion",
        name: "Traffic Congestion",
        description: "Coverage for severe traffic congestion",
        required_tier: "full",
      },
      {
        type: "election_day",
        name: "Election Day",
        description: "Coverage for election-related disruptions",
        required_tier: "basic",
      },
    ];

    const availableRiders = allRiders.filter((rider) => {
      switch (planTier) {
        case "basic":
          return rider.required_tier === "basic";
        case "standard":
          return ["basic", "standard"].includes(rider.required_tier);
        case "full":
          return true; // All riders available
        default:
          return false;
      }
    });

    res.json({
      available_riders: availableRiders,
      plan_tier: planTier,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
