const { supabase } = require('../config/supabase');

const LIMITS = {
  claims_per_zone_per_hour: 50,
  claims_per_city_per_day:  500,
  max_bcr_percent:          85,
};

async function checkCircuitBreaker(zone, city, triggerType) {
  
  // Check 1 — hourly zone limit (ATOMIC DATABASE LOCK)
  const { data, error } = await supabase.rpc('check_and_increment_circuit-breaker_atomic', {
    p_zone: zone,
    p_city: city,
    p_limit: LIMITS.claims_per_zone_per_hour,
  });

  if (error) {
    console.error('[CircuitBreaker] Failed to call atomic limit check RPC:', error.message);
    throw error;
  }
  
  // The first element in the array is the returned object from the RPC
  const { allowed, current_count } = data[0] || { allowed: true, current_count: 0 };
  
  if (!allowed) {
    await tripBreaker(zone, city, triggerType, 'HOURLY_LIMIT');
    return {
      tripped: true,
      reason: `Abnormal claim spike: ${current_count} claims in ${zone} — system paused for safety`,
      code: 'HOURLY_LIMIT_EXCEEDED',
    };
  }
  
  // Check 2 — daily city limit
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  
  const { count: dailyCount } = await supabase
    .from('claims')
    .select('*', { count: 'exact', head: true })
    .eq('city', city)
    .gte('created_at', oneDayAgo);
  
  if (dailyCount >= LIMITS.claims_per_city_per_day) {
    await tripBreaker(zone, city, triggerType, 'DAILY_LIMIT');
    return {
      tripped: true,
      reason: `Daily claim limit reached for ${city}`,
      code: 'DAILY_LIMIT_EXCEEDED',
    };
  }
  
  // Check 3 — pool BCR health
  const { data: pool } = await supabase
    .from('risk_pools')
    .select('loss_ratio, total_premium, total_claims_paid')
    .eq('city', city)
    .maybeSingle(); // Changed single to maybeSingle to avoid 406 if table empty
  
  if (pool && pool.loss_ratio * 100 >= LIMITS.max_bcr_percent) {
    await tripBreaker(zone, city, triggerType, 'BCR_EXCEEDED');
    return {
      tripped: true,
      reason: `Pool BCR at ${Math.round(pool.loss_ratio * 100)}% — enrollment paused`,
      code: 'BCR_LIMIT_EXCEEDED',
    };
  }
  
  return { tripped: false };
}

async function tripBreaker(zone, city, triggerType, reason) {
  await supabase
    .from('circuit-breakers')
    .upsert({
      zone,
      city,
      trigger_type: triggerType,
      tripped: true,
      tripped_at: new Date().toISOString(),
      reset_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    }, { onConflict: 'zone,trigger_type' });
  
  console.warn(`[CircuitBreaker] TRIPPED: ${reason} | Zone: ${zone}`);
}

async function getBCR(city) {
  const { data: pool } = await supabase
    .from('risk_pools')
    .select('total_premium, total_claims_paid, loss_ratio')
    .eq('city', city)
    .maybeSingle();
  
  if (!pool || pool.total_premium === 0) return 0;
  return Math.round(pool.loss_ratio * 100);
}

// Retained to prevent backend crashes
async function updatePoolHealth(city, premiumAmount, claimAmount) {
  const { data: existing } = await supabase
    .from('risk_pools')
    .select('*')
    .eq('city', city)
    .maybeSingle();

  if (existing) {
    const newClaims = existing.total_claims_paid + (claimAmount ?? 0);
    const newPremium = existing.total_premium + (premiumAmount ?? 0);
    const lossRatio = newPremium > 0 ? (newClaims / newPremium) : 0;

    await supabase
      .from('risk_pools')
      .update({
        total_claims_paid: newClaims,
        total_premium: newPremium,
        loss_ratio: lossRatio,
      })
      .eq('id', existing.id);
  } else {
    // Basic fallback if table is empty
    const initPremium = premiumAmount ?? 1000; // Seed logic
    const initClaims = claimAmount ?? 0;
    await supabase
      .from('risk_pools')
      .insert([{
        city,
        total_premium: initPremium,
        total_claims_paid: initClaims,
        loss_ratio: initPremium > 0 ? (initClaims / initPremium) : 0,
      }]);
  }
}

module.exports = { checkCircuitBreaker, getBCR, updatePoolHealth };

