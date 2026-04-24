const axios = require('axios');

/**
 * Build a Guidewire ClaimCenter–style payload stub for reinsurance / carrier integration demos.
 * @param {object} claim — row from `claims` with nested `users` if joined
 */
function buildClaimPayload(claim) {
  const user = claim.users || {};
  return {
    integration: 'guidewire_claim_center_stub',
    version: '1.0',
    claim: {
      external_id: claim.id,
      loss_type: claim.trigger_type,
      loss_location: {
        zone: claim.zone,
        city: claim.city || 'Chennai',
      },
      severity: claim.severity,
      duration_hours: claim.duration_hours,
      amounts: {
        gross_payout_paise: claim.gross_payout,
        tranche1_paise: claim.tranche1,
        tranche2_paise: claim.tranche2,
      },
      fraud: {
        score: claim.fraud_score,
        status: claim.fraud_status,
      },
      policy_id: claim.policy_id,
      created_at: claim.created_at,
    },
    claimant: {
      user_id: claim.user_id,
      name: user.name,
      phone: user.phone,
      zone: user.zone,
    },
    meta: {
      generated_at: new Date().toISOString(),
    },
  };
}

/**
 * Optional forward to GUIDEWIRE_WEBHOOK_URL (POST JSON). Disabled if URL unset.
 */
async function forwardToGuidewire(payload) {
  const url = process.env.GUIDEWIRE_WEBHOOK_URL;
  if (!url) {
    return { sent: false, reason: 'GUIDEWIRE_WEBHOOK_URL not set' };
  }
  const secret = process.env.GUIDEWIRE_WEBHOOK_SECRET;
  const headers = { 'Content-Type': 'application/json' };
  if (secret) headers['X-Integration-Secret'] = secret;

  const res = await axios.post(url, payload, {
    headers,
    timeout: 15000,
    validateStatus: () => true,
  });
  return {
    sent: true,
    status: res.status,
    ok: res.status >= 200 && res.status < 300,
  };
}

/**
 * PolicyCenter-style weekly policy issuance stub (B2C demo).
 */
function buildPolicyPayload(policy, user = {}) {
  return {
    integration: 'guidewire_policy_center_stub',
    version: '1.0',
    policy: {
      external_policy_id: policy.id,
      plan_tier: policy.plan_tier,
      weekly_premium_paise: policy.weekly_premium,
      base_premium_paise: policy.base_premium,
      iss_adjustment_paise: policy.iss_adjustment,
      zone_adjustment_paise: policy.zone_adjustment,
      max_weekly_payout_paise: policy.max_weekly_payout,
      max_daily_payout_paise: policy.max_daily_payout,
      status: policy.status,
      coverage_start: policy.coverage_start,
      coverage_end: policy.coverage_end,
      riders: policy.riders || [],
      pool_id: policy.pool_id,
      created_at: policy.created_at,
    },
    named_insured: {
      user_id: policy.user_id,
      name: user.name,
      phone: user.phone,
      zone: user.zone,
      city: user.city,
      iss_score: user.iss_score,
    },
    meta: {
      generated_at: new Date().toISOString(),
    },
  };
}

/**
 * BillingCenter-style premium debit / payout schedule stub.
 */
function buildBillingPayload(policy, user = {}, options = {}) {
  const amountPaise = options.amount_paise ?? policy.weekly_premium ?? 0;
  return {
    integration: 'guidewire_billing_center_stub',
    version: '1.0',
    invoice: {
      external_policy_id: policy.id,
      amount_paise: amountPaise,
      currency: 'INR',
      frequency: 'weekly',
      line_item: 'parametric_micro_premium',
      due_date: options.due_date || policy.coverage_start,
    },
    payor: {
      user_id: policy.user_id,
      name: user.name,
      phone: user.phone,
    },
    disbursement_channel: options.disbursement_channel || 'UPI_test_mode',
    meta: {
      generated_at: new Date().toISOString(),
    },
  };
}

module.exports = {
  buildClaimPayload,
  buildPolicyPayload,
  buildBillingPayload,
  forwardToGuidewire,
};
