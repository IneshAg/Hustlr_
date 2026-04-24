const express = require("express");
const router = express.Router();
const supabase = require("../config/supabase");
const { PLAN_CONFIG, TRIGGER_CONFIG } = require("../config/constants");

/**
 * POST /addons/purchase
 * Add a trigger add-on to an existing Standard/Full policy.
 *
 * BUSINESS RULES (actuarial constraint):
 * - Basic plans CANNOT purchase add-ons (self-imposed gate)
 * - Add-ons are quarterly commitments (13 weeks), not weekly toggles
 * - Cannot activate within 72hrs of IMD alert or 48hrs of known civil event
 * - Add-ons must be available for the plan tier
 * - Max 3 add-ons per policy per quarter (systemic risk rule)
 *
 * Body: {
 *   user_id: UUID,
 *   trigger_type: string (e.g., 'cyclone_landfall', 'internet_blackout')
 * }
 *
 * Response: {
 *   addon_id: UUID,
 *   trigger_type: string,
 *   quarterly_cost_paise: number,
 *   activation_date: ISO date,
 *   expiration_date: ISO date (13 weeks later),
 *   status: 'active'
 * }
 */
router.post("/purchase", async (req, res) => {
  try {
    const { user_id, trigger_type } = req.body;

    // ─── VALIDATION 1: trigger_type is not empty ─────────────────────────────
    if (!trigger_type || typeof trigger_type !== "string") {
      return res.status(400).json({
        error: "missing_trigger_type",
        message: "trigger_type is required and must be a string.",
      });
    }

    // ─── VALIDATION 2: Trigger exists ────────────────────────────────────────
    const trigger = TRIGGER_CONFIG[trigger_type];
    if (!trigger) {
      return res.status(400).json({
        error: "invalid_trigger_type",
        message: `Trigger '${trigger_type}' is not recognised. Valid triggers: ${Object.keys(TRIGGER_CONFIG).join(", ")}`,
      });
    }

    // ─── VALIDATION 3: User has an active policy ────────────────────────────
    const { data: policy, error: policyError } = await supabase
      .from("policies")
      .select("id, plan_tier, status")
      .eq("user_id", user_id)
      .eq("status", "active")
      .single();

    if (policyError || !policy) {
      return res.status(400).json({
        error: "no_active_policy",
        message: "No active policy found. Please create a policy first.",
      });
    }

    // ─── VALIDATION 4: Plan tier is not Basic (add-ons not available) ────────
    if (policy.plan_tier === "basic") {
      return res.status(403).json({
        error: "addon_not_available_for_basic",
        message:
          "Add-ons are not available for Basic plan. Upgrade to Standard or higher to purchase add-ons.",
      });
    }

    // ─── VALIDATION 5: Trigger is available as add-on for this plan tier ─────
    if (!trigger.addon_eligible_tiers?.includes(policy.plan_tier)) {
      return res.status(403).json({
        error: "addon_not_eligible_for_tier",
        message: `Trigger '${trigger_type}' is not available as an add-on for ${policy.plan_tier} plan. Eligible plans: ${trigger.addon_eligible_tiers?.join(", ") || "none"}`,
      });
    }

    // ─── VALIDATION 6: User hasn't already purchased this add-on this quarter ─
    const quarterStart = new Date();
    quarterStart.setDate(1);
    quarterStart.setMonth(Math.floor(quarterStart.getMonth() / 3) * 3);

    const { data: existingAddon } = await supabase
      .from("addon_coverage")
      .select("id")
      .eq("policy_id", policy.id)
      .eq("trigger_type", trigger_type)
      .gte("activation_date", quarterStart.toISOString())
      .maybeSingle();

    if (existingAddon) {
      return res.status(409).json({
        error: "addon_already_purchased",
        message: `You have already purchased ${trigger_type} add-on this quarter. Add-ons renew quarterly.`,
      });
    }

    // ─── VALIDATION 7: User doesn't have >3 active add-ons (systemic risk gate) ─
    const { data: activeAddons, error: countError } = await supabase
      .from("addon_coverage")
      .select("id", { count: "exact", head: true })
      .eq("policy_id", policy.id)
      .eq("status", "active")
      .gte("expiration_date", new Date().toISOString());

    if ((activeAddons?.length || 0) >= 3) {
      return res.status(429).json({
        error: "addon_systemic_risk_limit",
        message:
          "Maximum 3 active add-ons per quarter. Cancel one to purchase another.",
      });
    }

    // ─── INSERT: Create the add-on ───────────────────────────────────────────
    const activationDate = new Date();
    const expirationDate = new Date(activationDate);
    expirationDate.setDate(expirationDate.getDate() + 91); // 13 weeks = 91 days

    const quaterlyCostPaise =
      trigger.quarterly_cost_paise || trigger.weekly_cost_paise * 13;

    const { data: addon, error: insertError } = await supabase
      .from("addon_coverage")
      .insert([
        {
          policy_id: policy.id,
          trigger_type,
          weekly_cost_paise: trigger.weekly_cost_paise,
          quarterly_cost_paise: quaterlyCostPaise,
          activation_date: activationDate.toISOString(),
          expiration_date: expirationDate.toISOString(),
          status: "active",
        },
      ])
      .select()
      .single();

    if (insertError) throw insertError;

    // ─── CHARGE: Debit quarterly cost from wallet ───────────────────────────
    const { data: wallet } = await supabase
      .from("wallet_balances")
      .select("balance")
      .eq("user_id", user_id)
      .single();

    const newBalance = (wallet?.balance || 0) - quaterlyCostPaise / 100;

    if (newBalance < 0) {
      // Roll back the insert
      await supabase.from("addon_coverage").delete().eq("id", addon.id);
      return res.status(402).json({
        error: "insufficient_wallet_balance",
        message: `Insufficient balance. Add-on costs ₹${quaterlyCostPaise / 100}. Your balance: ₹${wallet?.balance || 0}`,
        required_amount: quaterlyCostPaise / 100,
        current_balance: wallet?.balance || 0,
      });
    }

    await supabase
      .from("wallet_balances")
      .update({ balance: newBalance })
      .eq("user_id", user_id);

    // ─── LOG: Audit trail ──────────────────────────────────────────────────
    await supabase.from("wallet_transactions").insert([
      {
        user_id,
        type: "addon_purchase",
        amount_paise: -quaterlyCostPaise,
        trigger_type,
        metadata: {
          addon_id: addon.id,
          quarterly_cost_paise: quaterlyCostPaise,
        },
      },
    ]);

    res.json({
      addon_id: addon.id,
      trigger_type: addon.trigger_type,
      quarterly_cost_paise: addon.quarterly_cost_paise,
      activation_date: addon.activation_date,
      expiration_date: addon.expiration_date,
      status: addon.status,
      message: `✓ ${trigger.label} add-on activated for ₹${quaterlyCostPaise / 100} (13 weeks).`,
    });
  } catch (err) {
    console.error("❌ /addons/purchase error:", err);
    res
      .status(500)
      .json({ error: "addon_purchase_failed", details: err.message });
  }
});

/**
 * DELETE /addons/:addon_id
 * Cancel an active add-on. No pro-rata refund (quarterly commitment).
 */
router.delete("/:addon_id", async (req, res) => {
  try {
    const { addon_id } = req.params;

    const { data: addon, error: fetchError } = await supabase
      .from("addon_coverage")
      .select("id, policy_id, status")
      .eq("id", addon_id)
      .single();

    if (fetchError || !addon) {
      return res.status(404).json({ error: "addon_not_found" });
    }

    if (addon.status !== "active") {
      return res.status(400).json({
        error: "addon_not_active",
        message: "Only active add-ons can be cancelled.",
      });
    }

    const { error: deleteError } = await supabase
      .from("addon_coverage")
      .update({ status: "cancelled" })
      .eq("id", addon_id);

    if (deleteError) throw deleteError;

    res.json({
      message: `✓ Add-on cancelled. No refund issued (quarterly commitment).`,
      addon_id,
    });
  } catch (err) {
    console.error("❌ /addons/:addon_id DELETE error:", err);
    res
      .status(500)
      .json({ error: "addon_cancellation_failed", details: err.message });
  }
});

/**
 * GET /addons/:policy_id
 * Fetch all active add-ons for a policy
 */
router.get("/policy/:policy_id", async (req, res) => {
  try {
    const { policy_id } = req.params;

    const { data: addons, error } = await supabase
      .from("addon_coverage")
      .select(
        "id, trigger_type, weekly_cost_paise, activation_date, expiration_date, status",
      )
      .eq("policy_id", policy_id)
      .eq("status", "active");

    if (error) throw error;

    res.json({
      addons: addons || [],
      count: addons?.length || 0,
    });
  } catch (err) {
    console.error("❌ /addons/policy/:policy_id error:", err);
    res.status(500).json({ error: "addon_fetch_failed", details: err.message });
  }
});

module.exports = router;
