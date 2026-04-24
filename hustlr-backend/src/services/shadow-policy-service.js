/**
 * Shadow policy: estimate missed payout if worker had Standard Shield but didn't (or events while uninsured).
 * Uses disruption_events in the worker's zone (last N days).
 */
const { supabase } = require('../config/supabase');
const { HOURLY_RATES, DAILY_CAPS } = require('../config/constants');

const DEFAULT_HOURLY = 45;
const ESTIMATED_HOURS = 3;

function normalizeTrigger(triggerType) {
  const k = (triggerType || '').toLowerCase().replace(/ /g, '_');
  const map = {
    heavy_rain: 'rain_heavy',
    extreme_rain: 'rain_extreme',
    heat_wave: 'heat_severe',
    aqi: 'aqi_hazardous',
    app_outage: 'platform_outage',
  };
  return map[k] || k;
}

function hourlyForTrigger(triggerType) {
  const k = normalizeTrigger(triggerType);
  return HOURLY_RATES[k] ?? DEFAULT_HOURLY;
}

function capForTrigger(triggerType) {
  const k = normalizeTrigger(triggerType);
  return DAILY_CAPS[k] ?? 120;
}

function estimateEventPayout(triggerType, severity) {
  const sev = typeof severity === 'number' ? Math.min(1, Math.max(0.3, severity)) : 0.7;
  const gross = hourlyForTrigger(triggerType) * ESTIMATED_HOURS * sev;
  return Math.round(Math.min(gross, capForTrigger(triggerType)));
}

async function getShadowSummary(userId, days = 14) {
  if (!userId) return { error: 'user_id required' };

  const { data: user, error: uErr } = await supabase
    .from('users')
    .select('id, zone, city')
    .eq('id', userId)
    .maybeSingle();
  if (uErr) throw uErr;
  if (!user) return { error: 'User not found' };

  const since = new Date();
  since.setDate(since.getDate() - days);

  const { data: policy } = await supabase
    .from('policies')
    .select('id, plan_tier, status, weekly_premium')
    .eq('user_id', userId)
    .eq('status', 'active')
    .maybeSingle();

  const { data: events, error: eErr } = await supabase
    .from('disruption_events')
    .select('id, trigger_type, severity, started_at, rainfall_mm')
    .eq('zone', user.zone)
    .gte('started_at', since.toISOString())
    .order('started_at', { ascending: false });

  if (eErr) throw eErr;

  const list = events || [];
  let missedTotal = 0;
  const shadowEvents = [];

  for (const e of list) {
    const missed = estimateEventPayout(e.trigger_type, e.severity);
    missedTotal += missed;
    shadowEvents.push({
      trigger: e.trigger_type,
      triggerName: e.trigger_type.replace(/_/g, ' '),
      date: e.started_at?.slice(0, 10) ?? '',
      missed,
      claimableAmount: missed,
    });
  }

  const standardPremium = policy?.weekly_premium ?? 59;
  const netBenefit = Math.max(0, missedTotal - standardPremium * Math.ceil(days / 7));

  return {
    user_id: userId,
    zone: user.zone,
    city: user.city,
    window_days: days,
    had_active_policy: Boolean(policy),
    plan_tier: policy?.plan_tier ?? null,
    missed_payout_inr: missedTotal,
    standard_premium_fortnight_inr: standardPremium * 2,
    net_benefit_inr: netBenefit,
    events: shadowEvents,
    source: 'disruption_events',
  };
}

module.exports = { getShadowSummary, estimateEventPayout };
