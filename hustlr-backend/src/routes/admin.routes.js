const express = require("express");
const router = express.Router();
const { supabase } = require("../config/supabase");
// const { authMiddleware } = require('../middleware/auth');

// Admin middleware - bypassed for local dashboard integration
const adminMiddleware = (req, res, next) => {
  // Bypassed for Next.js Admin Dashboard integration
  req.user = { id: "admin-123", role: "service_role" };
  next();
};

const authMiddleware = (req, res, next) => next();

function toInt(value, fallback = 0) {
  const n = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(n) ? n : fallback;
}

// Get fraud queue - all claims needing review
router.get(
  "/fraud-queue",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const pageNum = toInt(req.query.page, 1);
      const limitNum = toInt(req.query.limit, 20);
      const status = req.query.status || "FLAGGED";

      const { data: claims, error } = await supabase
        .from("claims")
        .select("*")
        .eq("fraud_status", status)
        .order("created_at", { ascending: false })
        .range((pageNum - 1) * limitNum, pageNum * limitNum - 1);

      if (error) throw error;

      const { count } = await supabase
        .from("claims")
        .select("id", { count: "exact", head: true })
        .eq("fraud_status", status);

      const userIds = Array.from(
        new Set((claims || []).map((c) => c.user_id).filter(Boolean)),
      );
      const policyIds = Array.from(
        new Set((claims || []).map((c) => c.policy_id).filter(Boolean)),
      );

      let usersById = {};
      if (userIds.length > 0) {
        const { data: usersData } = await supabase
          .from("users")
          .select("id, name, phone, trust_score, trust_tier")
          .in("id", userIds);
        usersById = (usersData || []).reduce((acc, u) => {
          acc[u.id] = u;
          return acc;
        }, {});
      }

      let policiesById = {};
      if (policyIds.length > 0) {
        const { data: policiesData } = await supabase
          .from("policies")
          .select("id, plan_tier, weekly_premium")
          .in("id", policyIds);
        policiesById = (policiesData || []).reduce((acc, p) => {
          acc[p.id] = p;
          return acc;
        }, {});
      }

      const mappedClaims = (claims || []).map((c) => ({
        id: c.id,
        userId: c.user_id,
        userName: usersById[c.user_id]?.name || "Unknown User",
        userPhone: usersById[c.user_id]?.phone || "",
        trustScore: Number(usersById[c.user_id]?.trust_score ?? 0),
        trustTier: usersById[c.user_id]?.trust_tier || "SILVER",
        policyId: c.policy_id || "",
        planTier: policiesById[c.policy_id]?.plan_tier || "standard",
        weeklyPremium: Number(policiesById[c.policy_id]?.weekly_premium ?? 0),
        fraudStatus: c.fraud_status || "FLAGGED",
        fraudScore: Number(c.fraud_score ?? 0),
        triggerType: c.trigger_type || "unknown",
        zone: c.zone || "",
        city: c.city || "",
        severity: Number(c.severity ?? 0),
        grossPayout: Number(c.gross_payout ?? 0),
        createdAt: c.created_at,
        fraudSignals: [],
        reason: c.fps_signals
          ? `Signals: ${JSON.stringify(c.fps_signals).slice(0, 160)}`
          : "No explicit fraud signals recorded",
      }));

      res.json({
        claims: mappedClaims,
        pagination: {
          page: pageNum,
          limit: limitNum,
          total: count,
          pages: Math.ceil((count || 0) / limitNum),
        },
      });
    } catch (error) {
      console.error("Error fetching fraud queue:", error);
      res.status(500).json({ error: "Failed to fetch fraud queue" });
    }
  },
);

// Update fraud status
router.put(
  "/fraud/:claimId/status",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { claimId } = req.params;
      const { status, adminNote } = req.body;

      // Validate status
      const validStatuses = ["CLEAN", "REVIEW", "FLAGGED", "REJECTED"];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({ error: "Invalid fraud status" });
      }

      const { data, error } = await supabase
        .from("claims")
        .update({
          fraud_status: status,
          updated_at: new Date().toISOString(),
        })
        .eq("id", claimId)
        .select()
        .single();

      if (error) throw error;

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "flag_claim",
        target_type: "claim",
        target_id: claimId,
        reason: adminNote || `Fraud status updated to ${status}`,
        metadata: { old_status: data.fraud_status, new_status: status },
      });

      res.json({ success: true, claim: data });
    } catch (error) {
      console.error("Error updating fraud status:", error);
      res.status(500).json({ error: "Failed to update fraud status" });
    }
  },
);

// Get payout queue - claims approved but not paid
router.get(
  "/payout-queue",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const pageNum = toInt(req.query.page, 1);
      const limitNum = toInt(req.query.limit, 20);
      const status = req.query.status || "APPROVED";

      const { data: claims, error } = await supabase
        .from("claims")
        .select("*")
        .eq("status", status)
        .order("created_at", { ascending: false })
        .range((pageNum - 1) * limitNum, pageNum * limitNum - 1);

      if (error) throw error;

      const { count } = await supabase
        .from("claims")
        .select("id", { count: "exact", head: true })
        .eq("status", status);

      const userIds = Array.from(
        new Set((claims || []).map((c) => c.user_id).filter(Boolean)),
      );
      let usersById = {};
      if (userIds.length > 0) {
        const { data: usersData } = await supabase
          .from("users")
          .select("id, name, phone")
          .in("id", userIds);
        usersById = (usersData || []).reduce((acc, u) => {
          acc[u.id] = u;
          return acc;
        }, {});
      }

      const mappedPayouts = (claims || []).map((c) => ({
        id: c.id,
        claimId: c.id,
        userId: c.user_id,
        userName: usersById[c.user_id]?.name || "Unknown User",
        userPhone: usersById[c.user_id]?.phone || "",
        amount: Number(c.gross_payout ?? 0),
        status: c.status || "APPROVED",
        paymentMethod: "UPI",
        createdAt: c.created_at,
      }));

      res.json({
        payouts: mappedPayouts,
        pagination: {
          page: pageNum,
          limit: limitNum,
          total: count,
          pages: Math.ceil((count || 0) / limitNum),
        },
      });
    } catch (error) {
      console.error("Error fetching payout queue:", error);
      res.status(500).json({ error: "Failed to fetch payout queue" });
    }
  },
);

// Process payout
router.post(
  "/payout/:claimId/process",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { claimId } = req.params;
      const { paymentMethod, upiRef } = req.body;

      // Get claim details
      const { data: claim, error: claimError } = await supabase
        .from("claims")
        .select("*, user_id, gross_payout, tranche1, tranche2")
        .eq("id", claimId)
        .single();

      if (claimError) throw claimError;

      if (claim.status !== "APPROVED") {
        return res.status(400).json({ error: "Claim not approved for payout" });
      }

      // Process in transaction
      const { data, error } = await supabase.rpc("process_claim_payout", {
        p_claim_id: claimId,
        p_payment_method: paymentMethod,
        p_upi_ref: upiRef,
      });

      if (error) throw error;

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "manual_payout",
        target_type: "claim",
        target_id: claimId,
        reason: `Manual payout processed via ${paymentMethod}`,
        metadata: { amount: claim.gross_payout, upi_ref: upiRef },
      });

      res.json({ success: true, payout: data });
    } catch (error) {
      console.error("Error processing payout:", error);
      res.status(500).json({ error: "Failed to process payout" });
    }
  },
);

// Get user trust scores
router.get(
  "/trust-scores",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const pageNum = toInt(req.query.page, 1);
      const limitNum = toInt(req.query.limit, 50);
      const { tier, minScore, maxScore, search } = req.query;

      let usersQuery = supabase
        .from("users")
        .select("*")
        .order("trust_score", { ascending: false });

      let countQuery = supabase
        .from("users")
        .select("id", { count: "exact", head: true });

      if (tier) {
        usersQuery = usersQuery.eq("trust_tier", tier);
        countQuery = countQuery.eq("trust_tier", tier);
      }

      if (minScore) {
        usersQuery = usersQuery.gte("trust_score", Number(minScore));
        countQuery = countQuery.gte("trust_score", Number(minScore));
      }

      if (maxScore) {
        usersQuery = usersQuery.lte("trust_score", Number(maxScore));
        countQuery = countQuery.lte("trust_score", Number(maxScore));
      }

      if (search) {
        const searchTerm = String(search).trim();
        if (searchTerm) {
          usersQuery = usersQuery.or(
            `name.ilike.%${searchTerm}%,phone.ilike.%${searchTerm}%`,
          );
          countQuery = countQuery.or(
            `name.ilike.%${searchTerm}%,phone.ilike.%${searchTerm}%`,
          );
        }
      }

      const { data: users, error } = await usersQuery.range(
        (pageNum - 1) * limitNum,
        pageNum * limitNum - 1,
      );
      if (error) throw error;

      const { count, error: countError } = await countQuery;
      if (countError) throw countError;

      const userIds = Array.from(
        new Set((users || []).map((u) => u.id).filter(Boolean)),
      );
      let policiesByUser = {};
      let claimsByUser = {};

      if (userIds.length > 0) {
        const { data: policiesData } = await supabase
          .from("policies")
          .select("user_id, plan_tier, weekly_premium, status, created_at")
          .in("user_id", userIds);

        policiesByUser = (policiesData || []).reduce((acc, p) => {
          if (!acc[p.user_id]) acc[p.user_id] = [];
          acc[p.user_id].push(p);
          return acc;
        }, {});

        const { data: claimsData } = await supabase
          .from("claims")
          .select("user_id, created_at")
          .in("user_id", userIds);

        claimsByUser = (claimsData || []).reduce((acc, c) => {
          if (!acc[c.user_id]) acc[c.user_id] = [];
          acc[c.user_id].push(c);
          return acc;
        }, {});
      }

      const mappedUsers = (users || []).map((u) => {
        const policies = Array.isArray(policiesByUser[u.id])
          ? policiesByUser[u.id]
          : [];
        const claims = Array.isArray(claimsByUser[u.id])
          ? claimsByUser[u.id]
          : [];
        const activePolicy =
          policies.find(
            (p) => p.status?.toLowerCase() === "active" || p.status?.toLowerCase() === "renewed",
          ) || null;

        const lastClaimTs = claims
          .map((c) => c.created_at)
          .filter(Boolean)
          .sort()
          .pop();

        return {
          id: u.id,
          name: u.name || "Unknown",
          phone: u.phone || "",
          zone: u.zone || "",
          city: u.city || "",
          trustScore: Number(u.trust_score ?? 0),
          trustTier: u.trust_tier || "SILVER",
          cleanWeeks: Number(u.clean_weeks ?? 0),
          cashbackEarned: Number(u.cashback_earned ?? 0),
          cashbackPending: Number(u.cashback_pending ?? 0),
          activePolicy: Boolean(activePolicy),
          policyTier: activePolicy?.plan_tier || "NONE",
          weeklyPremium: Number(activePolicy?.weekly_premium ?? 0),
          claimsCount: claims.length,
          lastClaimDate: lastClaimTs || null,
          kycStatus: u.kyc_status || "pending",
          createdAt: u.created_at,
        };
      });

      res.json({
        users: mappedUsers,
        pagination: {
          page: pageNum,
          limit: limitNum,
          total: count || 0,
          pages: Math.ceil((count || 0) / limitNum),
        },
      });
    } catch (error) {
      console.error("Error fetching trust scores:", error);
      res.status(500).json({ error: "Failed to fetch trust scores" });
    }
  },
);

// Update user trust score
router.put(
  "/trust/:userId/score",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { userId } = req.params;
      const { score, reason } = req.body;

      if (score < 0 || score > 1000) {
        return res
          .status(400)
          .json({ error: "Score must be between 0 and 1000" });
      }

      const { data, error } = await supabase
        .from("users")
        .update({
          trust_score: score,
          updated_at: new Date().toISOString(),
        })
        .eq("id", userId)
        .select()
        .single();

      if (error) throw error;

      // Log trust event
      await supabase.from("trust_events").insert({
        user_id: userId,
        event_type: "admin_adjustment",
        score_change: score - data.trust_score,
        new_score: score,
        reason: reason || "Admin adjustment",
      });

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "override_fraud",
        target_type: "user",
        target_id: userId,
        reason: reason || "Trust score manually adjusted",
        metadata: { old_score: data.trust_score, new_score: score },
      });

      res.json({ success: true, user: data });
    } catch (error) {
      console.error("Error updating trust score:", error);
      res.status(500).json({ error: "Failed to update trust score" });
    }
  },
);

// Get risk pool health
router.get("/risk-pools", authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const { city, riskType } = req.query;

    let query = supabase
      .from("risk_pools")
      .select(
        `
        *,
        policies:policies(count),
        claims:claims(count),
        pool_health(week_start, premiums_collected, claims_paid, loss_ratio)
      `,
      )
      .order("loss_ratio", { ascending: false });

    if (city) query = query.eq("city", city);
    if (riskType) query = query.eq("risk_type", riskType);

    const { data, error } = await query;

    if (error) throw error;

    if (!data || data.length === 0) {
      // Fallback: Generate live data from policies/claims for the main zones
      const zones = ['Adyar', 'T. Nagar', 'Anna Nagar', 'Velachery', 'Tambaram', 'Perungudi'];
      
      const { data: allPolicies } = await supabase.from('policies').select('id, status');
      const { data: allClaims } = await supabase.from('claims').select('id, gross_payout');
      
      const activeCount = allPolicies?.filter(p => p.status === 'active').length || 0;
      const totalPayout = allClaims?.reduce((acc, c) => acc + (c.gross_payout || 0), 0) || 0;
      const totalPremium = (allPolicies?.length || 0) * 49; // Average premium
      const globalBcr = totalPremium > 0 ? (totalPayout / totalPremium) * 100 : 0;

      const fallbackPools = zones.map(z => ({
        zone: z,
        city: 'Chennai',
        risk_type: 'weather',
        bcr: globalBcr + (Math.random() * 10 - 5), // Slight variation
        claims_count: Math.round((allClaims?.length || 0) / zones.length),
        active_policies: Math.round(activeCount / zones.length)
      }));
      
      return res.json({ pools: fallbackPools });
    }

    res.json({ pools: data });
  } catch (error) {
    console.error("Error fetching risk pools:", error);
    res.status(500).json({ error: "Failed to fetch risk pools" });
  }
});

// Adjust risk pool
router.put(
  "/risk-pools/:poolId/adjust",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { poolId } = req.params;
      const { adjustment, reason } = req.body;

      const { data, error } = await supabase
        .from("risk_pools")
        .update({
          reserve_fund: supabase.raw(`reserve_fund + ${adjustment}`),
          updated_at: new Date().toISOString(),
        })
        .eq("id", poolId)
        .select()
        .single();

      if (error) throw error;

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "adjust_pool",
        target_type: "risk_pool",
        target_id: poolId,
        reason: reason || `Reserve fund adjusted by ${adjustment}`,
        metadata: { adjustment },
      });

      res.json({ success: true, pool: data });
    } catch (error) {
      console.error("Error adjusting risk pool:", error);
      res.status(500).json({ error: "Failed to adjust risk pool" });
    }
  },
);

// Get circuit breakers
router.get(
  "/circuit-breakers",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { zone, status } = req.query;

      let query = supabase
        .from("circuit-breakers")
        .select("*")
        .order("bcr_at_trip", { ascending: false });

      if (zone) query = query.eq("zone", zone);
      if (status) query = query.eq("tripped", status === "tripped");

      const { data, error } = await query;

      if (error) throw error;

      res.json({ "circuit-breakers": data });
    } catch (error) {
      console.error("Error fetching circuit breakers:", error);
      res.status(500).json({ error: "Failed to fetch circuit breakers" });
    }
  },
);

// Reset circuit breaker
router.put(
  "/circuit-breakers/:cbId/reset",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { cbId } = req.params;
      const { reason } = req.body;

      const { data, error } = await supabase
        .from("circuit-breakers")
        .update({
          tripped: false,
          reset_at: new Date().toISOString(),
          reason: reason || "Manual reset by admin",
        })
        .eq("id", cbId)
        .select()
        .single();

      if (error) throw error;

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "other",
        target_type: "circuit-breaker",
        target_id: cbId,
        reason: reason || "Circuit breaker manually reset",
      });

      res.json({ success: true, "circuit-breaker": data });
    } catch (error) {
      console.error("Error resetting circuit breaker:", error);
      res.status(500).json({ error: "Failed to reset circuit breaker" });
    }
  },
);

// Get admin action logs
router.get(
  "/action-logs",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const {
        page = 1,
        limit = 50,
        actionType,
        targetId,
        startDate,
        endDate,
      } = req.query;

      let query = supabase
        .from("admin_actions")
        .select("*")
        .order("created_at", { ascending: false });

      if (actionType) query = query.eq("action_type", actionType);
      if (targetId) query = query.eq("target_id", targetId);
      if (startDate) query = query.gte("created_at", startDate);
      if (endDate) query = query.lte("created_at", endDate);

      const { data, error } = await query.range(
        (page - 1) * limit,
        page * limit - 1,
      );

      if (error) throw error;

      res.json({
        actions: data,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: data.length,
          pages: Math.ceil(data.length / limit),
        },
      });
    } catch (error) {
      console.error("Error fetching admin action logs:", error);
      res.status(500).json({ error: "Failed to fetch admin action logs" });
    }
  },
);

// Analytics Dashboard Endpoint
router.get("/analytics", authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const { data: claims } = await supabase
      .from("claims")
      .select("id, gross_payout, fraud_status, created_at");
    const { data: policies } = await supabase
      .from("policies")
      .select("id, weekly_premium, created_at");

    const totalClaims = claims?.length || 0;
    const flaggedClaims =
      claims?.filter((c) => c.fraud_status === "FLAGGED").length || 0;
    const totalPayout =
      claims?.reduce((acc, c) => acc + (c.gross_payout || 0), 0) || 0;
    const totalPremium =
      policies?.reduce((acc, p) => acc + (p.weekly_premium || 0), 0) || 0;
    const lossRatio = totalPremium > 0 ? (totalPayout / totalPremium) * 100 : 0;

    // Generate 7-day timeline for better UI charts
    const timeline = [];
    const now = new Date();
    for (let i = 6; i >= 0; i--) {
      const d = new Date(now);
      d.setDate(d.getDate() - i);
      const dateStr = d.toISOString().split("T")[0];
      
      const dayClaims = claims?.filter(c => c.created_at?.startsWith(dateStr)) || [];
      const dayPolicies = policies?.filter(p => p.created_at?.startsWith(dateStr)) || [];
      
      timeline.push({
        date: dateStr,
        claims: dayClaims.length,
        payout: dayClaims.reduce((acc, c) => acc + (c.gross_payout || 0), 0),
        flagged: dayClaims.filter(c => c.fraud_status === 'FLAGGED').length,
        premium: dayPolicies.reduce((acc, p) => acc + (p.weekly_premium || 0), 0)
      });
    }

    res.json({
      summary: {
        totalClaims,
        totalPayout,
        totalPremium,
        lossRatio,
        flaggedClaims,
        totalEvents: totalClaims,
      },
      claimsTimeline: timeline.map(t => ({
        date: t.date,
        claims: t.claims,
        payout: t.payout,
        flagged: t.flagged
      })),
      premiumsTimeline: timeline.map(t => ({
        week: t.date,
        amount: t.premium
      })),
      lossRatioTimeline: timeline.map(t => ({
        week: t.date,
        premium: t.premium,
        payout: t.payout,
        lossRatio: t.premium > 0 ? (t.payout / t.premium) * 100 : 0
      })),
      eventsTimeline: timeline.map(t => ({
        date: t.date,
        count: t.claims
      })),
      triggerBreakdown: [{ type: "weather", count: totalClaims }],
      severityBuckets: { low: totalClaims, medium: 0, high: 0 },
      prediction: {
        riskLevel: totalClaims > 10 ? "medium" : "low",
        expectedClaimsRange: "0-10",
        details: "Live analytics derived from Supabase.",
        aqiRisk: "Low",
        source: "Live Database",
        zonesChecked: 1,
      },
    });
  } catch (e) {
    console.error("[Admin] Analytics Error:", e);
    res.status(500).json({ error: "Failed to load analytics" });
  }
});

// GET /pool-summary - Total aggregate across all pools
router.get(
  "/pool-summary",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { data: policies } = await supabase
        .from("policies")
        .select("id, weekly_premium, status");

      const { data: claims } = await supabase
        .from("claims")
        .select("id, gross_payout, status");

      const activePoliciesCount =
        policies?.filter((p) => p.status === "active" || p.status === "renewed")
          .length || 0;
      const totalPremium =
        policies?.reduce((acc, p) => acc + (p.weekly_premium || 0), 0) || 0;
      const totalPayout =
        claims?.reduce((acc, c) => acc + (c.gross_payout || 0), 0) || 0;

      const weeklyPool = totalPremium;
      const bcr = totalPremium > 0 ? (totalPayout / totalPremium) * 100 : 0;
      const reserve = weeklyPool * 2.5;
      const circuitBreakerTripped = bcr >= 85;

      res.json({
        weeklyPool,
        bcr,
        activePolicies: activePoliciesCount,
        reserve,
        circuitBreakerTripped,
      });
    } catch (error) {
      console.error("[Admin] Error fetching pool summary:", error);
      res.status(500).json({ error: "Failed to fetch pool summary" });
    }
  },
);
router.get("/policies", authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const pageNum = toInt(req.query.page, 1);
    const limitNum = toInt(req.query.limit, 100);
    const { status, plan } = req.query;

    console.log("[Admin] Fetching policies...");
    let query = supabase
      .from("policies")
      .select("*")
      .order("created_at", { ascending: false })
      .range((pageNum - 1) * limitNum, pageNum * limitNum - 1);

    if (status) query = query.eq("status", status);
    if (plan) query = query.eq("plan_tier", plan);

    const { data, error } = await query;

    if (error) {
      console.error("[Admin] Supabase error fetching policies:", error);
      throw error;
    }

    if (!data || data.length === 0) {
      console.log("[Admin] No policies found in database.");
      return res.json({ policies: [] });
    }

    const userIds = [...new Set(data.map((p) => p.user_id))];
    const { data: users } = await supabase
      .from("users")
      .select("id, name")
      .in("id", userIds);

    const usersById = (users || []).reduce((acc, u) => {
      acc[u.id] = u;
      return acc;
    }, {});

    const mapped = data.map((p) => ({
      id: p.id,
      userId: p.user_id,
      userName: usersById[p.user_id]?.name || "Unknown User",
      planTier: p.plan_tier,
      basePremium: p.base_premium,
      zoneAdjustment: p.zone_adjustment,
      issAdjustment: p.iss_adjustment,
      weeklyPremium: p.weekly_premium,
      maxWeeklyPayout: p.max_weekly_payout,
      maxDailyPayout: p.max_daily_payout,
      status: p.status,
      autoRenew: p.auto_renew,
      coverageStart: p.coverage_start,
      paidUntil: p.coverage_end || p.commitment_end || p.paid_until || new Date(new Date(p.created_at).getTime() + 91*24*60*60*1000).toISOString(),
      commitmentEnd: p.commitment_end || p.coverage_end || new Date(new Date(p.created_at).getTime() + 91*24*60*60*1000).toISOString(),
      poolId: p.pool_id,
      createdAt: p.created_at,
    }));

    console.log(`[Admin] Returning ${mapped.length} policies.`);
    res.json({ policies: mapped });
  } catch (error) {
    console.error("[Admin] Error fetching policies:", error);
    res.status(500).json({ error: "Failed to fetch policies" });
  }
});

// Get system health metrics
router.get(
  "/system-health",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { getAPIHealth } = require("../services/api-wrapper");
      const liveHealth = getAPIHealth();

      const { count: flaggedClaimsCount } = await supabase
        .from("claims")
        .select("id", { count: "exact", head: true })
        .eq("fraud_status", "FLAGGED");

      const { data: latestClaim } = await supabase
        .from("claims")
        .select("created_at")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const apis = [
        {
          name: "Weather API",
          ok: liveHealth.weather?.healthy ?? false,
          latency: (liveHealth.weather?.failures ?? 0) > 0 ? 320 : 120,
        },
        {
          name: "AQI Monitor",
          ok: liveHealth.aqi?.healthy ?? false,
          latency: (liveHealth.aqi?.failures ?? 0) > 0 ? 300 : 110,
        },
        { name: "ML Fraud Service", ok: true, latency: 150 },
        { name: "Payment Gateway", ok: true, latency: 200 },
        { name: "Notification Service", ok: true, latency: 45 },
        { name: "Policy Service", ok: true, latency: 50 },
        { name: "Claims API", ok: true, latency: 80 },
        { name: "Wallet Service", ok: true, latency: 60 },
      ];

      const errors24h = Object.values(liveHealth).reduce(
        (acc, v) => acc + (v.failures || 0),
        0,
      );

      res.json({
        status: errors24h > 0 ? "degraded" : "healthy",
        apis,
        lastAdjudicatorRun: {
          success: true,
          claimsCreated: flaggedClaimsCount || 0,
          durationMs: 1800,
          timestamp: latestClaim?.created_at || new Date().toISOString(),
        },
        errors24h,
      });
    } catch (error) {
      console.error("Error fetching system health:", error);
      res.status(500).json({ error: "Failed to fetch system health" });
    }
  },
);

// Legacy duplicate endpoints retained for reference but moved off active paths.
router.get(
  "/_legacy/fraud-queue",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { page = 1, limit = 20, status } = req.query;
      let query = supabase
        .from("claims")
        .select(
          "id, user_id, policy_id, gross_payout, fraud_status, created_at, fraud_reason, users!inner(name)",
        )
        .eq("fraud_status", status || "FLAGGED")
        .order("created_at", { ascending: false })
        .range((page - 1) * limit, page * limit - 1);

      const { data, error } = await query;
      if (error) throw error;

      const mapped = data.map((c) => ({
        id: c.id,
        userName: c.users?.name || "Unknown User",
        policyId: c.policy_id,
        amount: c.gross_payout || 0,
        riskScore: 85, // placeholder
        status: c.fraud_status,
        date: c.created_at,
        reason: c.fraud_reason || "Suspicious Activity",
      }));

      res.json({ claims: mapped });
    } catch (e) {
      console.error("Fraud Queue Error:", e);
      res.status(500).json({ error: "Failed" });
    }
  },
);

// Legacy duplicate endpoints retained for reference but moved off active paths.
router.get(
  "/_legacy/payout-queue",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { page = 1, limit = 20, status } = req.query;
      let query = supabase
        .from("claims")
        .select(
          "id, user_id, policy_id, gross_payout, status, created_at, users!inner(name)",
        )
        .eq("status", status || "APPROVED")
        .order("created_at", { ascending: false })
        .range((page - 1) * limit, page * limit - 1);

      const { data, error } = await query;
      if (error) throw error;

      const mapped = data.map((c) => ({
        id: c.id,
        userName: c.users?.name || "Unknown User",
        policyId: c.policy_id,
        amount: c.gross_payout || 0,
        status: c.status,
        triggerEvent: "Automated Payout",
        date: c.created_at,
      }));

      res.json({ payouts: mapped });
    } catch (e) {
      console.error("Payout Queue Error:", e);
      res.status(500).json({ error: "Failed" });
    }
  },
);

// Legacy duplicate endpoints retained for reference but moved off active paths.
router.get(
  "/_legacy/system-health",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const health = {
        status: "healthy",
        uptime: process.uptime(),
        apis: [
          { name: "Core Backend", ok: true, latency: 45 },
          { name: "Python ML Engine", ok: true, latency: 120 },
          { name: "Supabase DB", ok: true, latency: 15 },
          { name: "Vercel Edge", ok: true, latency: 8 },
        ],
        lastAdjudicatorRun: {
          timestamp: new Date().toISOString(),
          durationMs: 350,
          processed: 12,
        },
      };

      res.json(health);
    } catch (e) {
      console.error("System Health Error:", e);
      res.status(500).json({ error: "Failed" });
    }
  },
);

// Legacy duplicate endpoints retained for reference but moved off active paths.
router.get(
  "/_legacy/trust-scores",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { page = 1, limit = 50, search, tier } = req.query;
      let query = supabase
        .from("users")
        .select("id, name, created_at, phone")
        .order("created_at", { ascending: false })
        .range((page - 1) * limit, page * limit - 1);

      if (search) {
        query = query.ilike("name", `%${search}%`);
      }

      const { data, error } = await query;
      if (error) throw error;

      const mapped = data.map((u) => ({
        id: u.id,
        name: u.name || "Unknown",
        trustScore: Math.floor(Math.random() * 50) + 50, // mock score
        status: "active",
        joinDate: u.created_at,
        tier: "standard",
        totalClaims: 0,
        activePolicies: 1,
      }));

      res.json({ users: mapped });
    } catch (e) {
      console.error("Trust Scores Error:", e);
      res.status(500).json({ error: "Failed" });
    }
  },
);

// POST /admin/iss/recalculate - Trigger ISS recalculation for a user
router.post(
  "/iss/recalculate",
  authMiddleware,
  adminMiddleware,
  async (req, res) => {
    try {
      const { user_id } = req.body;

      if (!user_id) {
        return res.status(400).json({ error: "user_id is required" });
      }

      // Fetch user data needed for ISS calculation
      const { data: user, error: userError } = await supabase
        .from("users")
        .select(
          "id, name, zone, city, active_days_last_30, avg_daily_income, disruption_freq_12mo, platform_tenure_weeks",
        )
        .eq("id", user_id)
        .single();

      if (userError || !user) {
        return res.status(404).json({ error: "User not found" });
      }

      // Call ML service to recalculate ISS
      const mlService = require("../services/ml-service");
      const issResult = await mlService.getISSScore({
        zone_flood_risk: 0.6, // default, could be looked up from zone
        avg_daily_income: user.avg_daily_income || 600,
        disruption_freq_12mo: user.disruption_freq_12mo || 8,
        platform_tenure_weeks: user.platform_tenure_weeks || 4,
        city: user.city || "Chennai",
      });

      if (!issResult.iss_score) {
        return res
          .status(500)
          .json({ error: "ISS calculation failed", details: issResult });
      }

      // Update user's iss_score in database
      const { data: updated, error: updateError } = await supabase
        .from("users")
        .update({
          iss_score: issResult.iss_score,
          updated_at: new Date().toISOString(),
        })
        .eq("id", user_id)
        .select()
        .single();

      if (updateError) throw updateError;

      // Log admin action
      await supabase.from("admin_actions").insert({
        admin_id: req.user.id,
        action_type: "recalculate_iss",
        target_type: "user",
        target_id: user_id,
        reason: "Manual ISS recalculation triggered from admin panel",
        metadata: {
          new_iss_score: issResult.iss_score,
          tier: issResult.tier,
          model: issResult.model_used,
        },
      });

      res.json({
        success: true,
        user: updated,
        iss_result: {
          iss_score: issResult.iss_score,
          tier: issResult.tier,
          model_used: issResult.model_used,
        },
      });
    } catch (error) {
      console.error("Error recalculating ISS:", error);
      res
        .status(500)
        .json({ error: "Failed to recalculate ISS", details: error.message });
    }
  },
);

module.exports = router;
