const supabase = require('../config/supabase');

const TRUST_EVENTS = {
  // Positive
  PHONE_VERIFIED:         +5,
  SIX_MONTHS_CLEAN:      +10,
  CLAIM_VELOCITY_CLEAN:   +3,
  CONSISTENT_ZONE:        +2,
  REFERRAL_ACTIVE:       +10,
  // Negative
  CLAIM_REJECTED_FRAUD:  -50,
  ZONE_MISMATCH:         -20,
  SOFT_HOLD_TRIGGERED:   -10,
  MASS_CLAIM_LINKED:     -35,
};

const TRUST_TIERS = {
  PLATINUM: { min: 150, payout_hours: 6,  support: 'priority', label: '🌟 Platinum' },
  GOLD:     { min: 120, payout_hours: 12, support: 'fast',     label: '🥇 Gold' },
  SILVER:   { min: 80,  payout_hours: 24, support: 'standard', label: '🥈 Silver' },
  BRONZE:   { min: 50,  payout_hours: 48, support: 'standard', label: '🥉 Bronze' },
  AT_RISK:  { min: 0,   payout_hours: 72, support: 'limited',  label: '⚠️ At Risk' },
};

function getTier(score) {
  if (score >= 150) return 'PLATINUM';
  if (score >= 120) return 'GOLD';
  if (score >= 80)  return 'SILVER';
  if (score >= 50)  return 'BRONZE';
  return 'AT_RISK';
}

async function adjustTrustScore(userId, eventType, reason) {
  const change = TRUST_EVENTS[eventType] ?? 0;
  if (change === 0) return;

  const { data: user } = await supabase
    .from('users')
    .select('trust_score')
    .eq('id', userId)
    .single();

  const newScore = Math.max(0, Math.min(200,
    (user?.trust_score ?? 100) + change
  ));
  const newTier = getTier(newScore);

  await supabase.from('users').update({
    trust_score: newScore,
    trust_tier:  newTier,
  }).eq('id', userId);

  await supabase.from('trust_events').insert([{
    user_id:      userId,
    event_type:   eventType,
    score_change: change,
    new_score:    newScore,
    reason:       reason || eventType,
  }]);

  return { newScore, newTier, change };
}

async function getUserTrustProfile(userId) {
  const { data: user } = await supabase
    .from('users')
    .select('trust_score, trust_tier, clean_weeks, cashback_earned, cashback_pending')
    .eq('id', userId)
    .single();

  if (!user) return null;

  const tier     = TRUST_TIERS[user.trust_tier] || TRUST_TIERS.SILVER;
  const tierInfo = { ...tier, name: user.trust_tier };

  return {
    score:             user.trust_score,
    tier:              tierInfo,
    clean_weeks:       user.clean_weeks,
    cashback_earned:   user.cashback_earned,
    cashback_pending:  user.cashback_pending,
  };
}

async function processSundayTrustUpdate() {
  // Runs every Sunday 11 PM alongside settlement batch
  // Check each active worker's week for clean claims

  const { data: workers } = await supabase
    .from('users')
    .select('id, trust_score, clean_weeks')
    .not('trust_score', 'is', null);
    
  if (!workers) return;

  const weekStart = new Date();
  weekStart.setDate(weekStart.getDate() - 7);

  for (const worker of workers) {
    const { data: claims } = await supabase
      .from('claims')
      .select('id, status, fraud_status')
      .eq('user_id', worker.id)
      .gte('created_at', weekStart.toISOString());

    const hasFraudFlags = claims?.some(c =>
      c.fraud_status === 'FLAGGED' || c.fraud_status === 'REVIEW'
    );

    if (!hasFraudFlags) {
      // Clean week — increment streak
      const newCleanWeeks = (worker.clean_weeks || 0) + 1;

      await supabase.from('users').update({
        clean_weeks: newCleanWeeks,
      }).eq('id', worker.id);

      // Award +3 trust for clean week
      await adjustTrustScore(
        worker.id,
        'CLAIM_VELOCITY_CLEAN',
        `Clean week ${newCleanWeeks}`
      );

      // Claim-free cashback: 4 consecutive clean weeks
      if (newCleanWeeks > 0 && newCleanWeeks % 4 === 0) {
        await processCashbackAward(worker.id);
      }
    } else {
      // Reset clean streak
      await supabase.from('users').update({
        clean_weeks: 0,
      }).eq('id', worker.id);
    }
  }
}

async function processCashbackAward(userId) {
  // Get last 4 weeks of premiums paid
  const fourWeeksAgo = new Date();
  fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);

  const { data: premiums } = await supabase
    .from('wallet_transactions')
    .select('amount')
    .eq('user_id', userId)
    .eq('type', 'debit')
    .like('description', '%Premium%')
    .gte('created_at', fourWeeksAgo.toISOString());

  const totalPremiums = Math.abs(
    premiums?.reduce((s, t) => s + t.amount, 0) || 0
  );
  const cashback = Math.round(totalPremiums * 0.10); // 10%

  if (cashback <= 0) return;

  // Credit cashback to wallet
  await supabase.from('wallet_transactions').insert([{
    user_id:     userId,
    amount:      cashback,
    type:        'credit',
    description: '4-Week Claim-Free Cashback 🎉',
    reference:   `CASHBACK_${Date.now()}`,
  }]);

  await supabase.from('users').update({
    cashback_earned:  supabase.rpc('increment', { x: cashback }),
    cashback_pending: 0,
    clean_weeks:      0,  // Reset after award
  }).eq('id', userId);

  console.log(`[Trust] Cashback ₹${cashback} awarded to ${userId}`);
}

module.exports = {
  adjustTrustScore,
  getUserTrustProfile,
  processSundayTrustUpdate,
  getTier,
  TRUST_TIERS,
};
