/**
 * shift.routes.js — Hustlr Phase 3: Background Geolocation Engine
 *
 * Endpoints:
 *   POST /shift/heartbeat   — GPS telemetry ping from Flutter app (~every 30s)
 *   POST /shift/start       — Mark shift as ACTIVE in Supabase
 *   POST /shift/stop        — Mark shift as ENDED, close any open gaps
 *   GET  /shift/status/:id  — Return current shift status + open gaps for worker
 */

const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

router.post('/heartbeat', async (req, res) => {
  const {
    worker_id, lat, lng, 
    accuracy, timestamp, 
    is_mock_location, activity_type, 
    battery_level, battery_is_charging, speed, cell_tower_id
  } = req.body;

  if (!worker_id || lat == null || lng == null) {
    return res.status(400).json({ error: 'worker_id, lat, lng are required' });
  }

  const reqTime = timestamp || new Date().toISOString();

  // Condition 1: Mock Location -> Flag 403, DO NOT update last_seen_at
  if (is_mock_location === true) {
    await supabase.from('fraud_flags').insert({
      worker_id,
      reason: 'mock_location_detected',
      frs_score: 100,
      timestamp: reqTime,
    });
    return res.status(403).json({ error: 'mock_location_detected' });
  }

  // Condition 2: Accuracy > 50 -> low_confidence
  const is_low_confidence = accuracy > 50;

  // Condition 3: Speed > 25 (90km/h) -> impossible speed, +15 pending FRS
  if (speed > 25) {
    await supabase.from('fraud_flags').insert({ worker_id, reason: 'impossible_speed', frs_score: 15, timestamp: reqTime });
    await supabase.from('pending_frs_adjustments').insert({ worker_id, adjustment: 15, reason: 'impossible_speed' });
  }

  // Condition 4: Still AND Speed > 5 -> accel_gps_mismatch, +20 pending FRS
  if (activity_type === 'still' && speed > 5) {
    await supabase.from('fraud_flags').insert({ worker_id, reason: 'accelerometer_gps_mismatch', frs_score: 20, timestamp: reqTime });
    await supabase.from('pending_frs_adjustments').insert({ worker_id, adjustment: 20, reason: 'accelerometer_gps_mismatch' });
  }

  // Condition 5: Charging AND in_vehicle -> charging_during_outdoor_shift, +8 pending FRS
  if (battery_is_charging === true && activity_type === 'in_vehicle') {
    await supabase.from('fraud_flags').insert({ worker_id, reason: 'charging_during_outdoor_shift', frs_score: 8, timestamp: reqTime });
    await supabase.from('pending_frs_adjustments').insert({ worker_id, adjustment: 8, reason: 'charging_during_outdoor_shift' });
  }

  // 6: Upsert Telemetry and update workers.last_seen_at
  await supabase.from('shift_telemetry').insert({
    worker_id, lat, lng,
    accuracy: accuracy ?? null,
    timestamp: reqTime,
    is_mock_location: false,
    activity_type: activity_type ?? 'unknown',
    battery_level: battery_level ?? null,
    is_low_confidence,
  });

  // Need to update the users/workers table with the heartbeat
  await supabase.from('users').update({ last_seen_at: reqTime }).eq('id', worker_id);

  // Auto-Resume Mode: Close any open gap, trigger push if gap closed
  const { data: openGap } = await supabase
    .from('shift_gaps')
    .select('id, gap_start')
    .eq('worker_id', worker_id)
    .is('gap_end', null)
    .single();

  if (openGap) {
    const gapSec = Math.round((new Date(reqTime) - new Date(openGap.gap_start)) / 1000);
    await supabase.from('shift_gaps').update({
      gap_end: reqTime,
      gap_duration_seconds: gapSec,
      frs_penalty: gapSec > 1800 ? 20 : gapSec > 600 ? 10 : 0,
    }).eq('id', openGap.id);

    // If gap_duration_seconds > 600, insert pending FRS
    if (gapSec > 600) {
      const penalty = gapSec > 1800 ? 20 : 10;
      await supabase.from('pending_frs_adjustments').insert({
        worker_id, adjustment: penalty, reason: `gps_gap_${gapSec}s`
      });
    }

    // Auto-Resume worker status
    await supabase.from('users').update({ shift_status: 'ACTIVE', paused_at: null }).eq('id', worker_id);
    console.log(`[Push] Sent to ${worker_id}: Location restored — you're covered again.`);
  }

  return res.json({ status: 'ok', timestamp: reqTime });
});

// ─── POST /shift/start ────────────────────────────────────────────────────────
router.post('/start', async (req, res) => {
  const { worker_id, zone } = req.body;
  if (!worker_id) return res.status(400).json({ error: 'worker_id required' });

  const { error } = await supabase
    .from('workers')
    .update({ shift_status: 'ACTIVE', shift_started_at: new Date().toISOString() })
    .eq('id', worker_id);

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ status: 'ACTIVE', zone });
});

// ─── POST /shift/stop ─────────────────────────────────────────────────────────
router.post('/stop', async (req, res) => {
  const { worker_id } = req.body;
  if (!worker_id) return res.status(400).json({ error: 'worker_id required' });

  // Close any open gap
  await supabase
    .from('shift_gaps')
    .update({ gap_end: new Date().toISOString(), gap_duration_seconds: 0 })
    .eq('worker_id', worker_id)
    .is('gap_end', null);

  await supabase
    .from('workers')
    .update({ shift_status: 'ENDED', shift_ended_at: new Date().toISOString() })
    .eq('id', worker_id);

  return res.json({ status: 'ENDED' });
});

// ─── GET /shift/status/:id ────────────────────────────────────────────────────
router.get('/status/:id', async (req, res) => {
  const worker_id = req.params.id;

  const { data: worker } = await supabase
    .from('workers')
    .select('shift_status, shift_started_at')
    .eq('id', worker_id)
    .single();

  const { data: gaps } = await supabase
    .from('shift_gaps')
    .select('gap_start, gap_end, gap_duration_seconds, frs_penalty')
    .eq('worker_id', worker_id)
    .order('gap_start', { ascending: false })
    .limit(10);

  const { data: lastPing } = await supabase
    .from('shift_telemetry')
    .select('timestamp, lat, lng, accuracy, is_mock_location')
    .eq('worker_id', worker_id)
    .order('timestamp', { ascending: false })
    .limit(1)
    .single();

  return res.json({
    shift_status: worker?.shift_status ?? 'OFFLINE',
    shift_started_at: worker?.shift_started_at,
    last_heartbeat: lastPing?.timestamp,
    last_lat: lastPing?.lat,
    last_lng: lastPing?.lng,
    open_gaps: gaps?.filter(g => !g.gap_end).length ?? 0,
    recent_gaps: gaps ?? [],
  });
});

// ─── Haversine helper ─────────────────────────────────────────────────────────
function haversineMetres(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

module.exports = router;
