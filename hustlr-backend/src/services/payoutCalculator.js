const { MAX_PAYOUTS, PAYOUT_PERCENTAGES } = require('../config/constants');

function calculatePayout(plan_tier, trigger_type, severity) {
  const max_payout = MAX_PAYOUTS[plan_tier];
  if (typeof max_payout === 'undefined') {
    throw new Error(`Invalid plan tier: ${plan_tier}`);
  }
  
  const payout_pct = PAYOUT_PERCENTAGES[trigger_type] || 0.5;
  const gross_payout = Math.round(max_payout * payout_pct * severity);
  
  const tranche1 = Math.floor(gross_payout * 0.7);
  const tranche2 = gross_payout - tranche1;
  
  return { gross_payout, tranche1, tranche2 };
}

module.exports = { calculatePayout };
