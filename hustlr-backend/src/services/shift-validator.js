const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

/**
 * checkShiftIntersection — Fix 2
 * Evaluates whether a worker was genuinely on an active shift during a disruption.
 * Subtracts all logged gaps (duration > 120s) from the disruption window.
 * Demands at least 2 hours (120 minutes) of verified overlapping shift time to pass.
 *
 * @param {string} worker_id
 * @param {string|Date} disruption_start ISO string
 * @param {string|Date} disruption_end ISO string
 * @param {string} date String 'YYYY-MM-DD'
 * @returns {Promise<{pass: boolean, reason: string|null, effective_minutes: number}>}
 */
async function checkShiftIntersection(worker_id, disruption_start, disruption_end, date) {
  const ds = new Date(disruption_start).getTime();
  const de = new Date(disruption_end).getTime();
  const totalDisruptionMins = (de - ds) / 60000;

  if (totalDisruptionMins <= 0) {
    return { pass: false, reason: 'invalid_disruption_time', effective_minutes: 0 };
  }

  // 1. Fetch all shift_gaps for the worker today where duration > 120
  const startOfDay = new Date(`${date}T00:00:00Z`).toISOString();
  const endOfDay = new Date(`${date}T23:59:59Z`).toISOString();

  const { data: gaps } = await supabase
    .from('shift_gaps')
    .select('gap_start, gap_end')
    .eq('worker_id', worker_id)
    .gte('gap_duration_seconds', 120)
    .gte('gap_start', startOfDay)
    .lte('gap_start', endOfDay);

  let gapOverlapMins = 0;

  if (gaps && gaps.length > 0) {
    for (const g of gaps) {
      // If gap has no end, assume it lasted until the end of the disruption
      const gs = new Date(g.gap_start).getTime();
      const ge = g.gap_end ? new Date(g.gap_end).getTime() : de;

      const overlapStart = Math.max(ds, gs);
      const overlapEnd = Math.min(de, ge);

      if (overlapEnd > overlapStart) {
        gapOverlapMins += (overlapEnd - overlapStart) / 60000;
      }
    }
  }

  // 2. Build effective_minutes = declared shift window minus gap overlaps
  const effective_minutes = Math.max(0, totalDisruptionMins - gapOverlapMins);

  // 3. Check if disruption overlaps by at least 2 hours
  if (effective_minutes >= 120) {
    return { pass: true, reason: null, effective_minutes };
  } else {
    // 4. If disruption falls entirely within a gap (or just < 120 min) -> FAIL
    return { 
      pass: false, 
      reason: 'worker_not_verifiably_on_shift', 
      effective_minutes 
    };
  }
}

module.exports = {
  checkShiftIntersection,
};
