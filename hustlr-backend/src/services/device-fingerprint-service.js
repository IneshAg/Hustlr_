// Phase 2 — lightweight shared-device signal for fraud (ring / install clustering).
// Requires `device_fingerprint_events` from supabase/hustlr_consolidated_schema.sql

const { supabase } = require("../config/supabase");

const WINDOW_DAYS = 7;
const BUMP_PER_OTHER_USER = 12;
const MAX_BUMP = 36;

/**
 * Persist a device fingerprint sample (idempotent-friendly: multiple rows per user are OK).
 */
async function recordFingerprint(userId, fingerprintHash, zone) {
  if (!userId || !fingerprintHash || typeof fingerprintHash !== "string") {
    return { ok: false, error: "user_id and fingerprint_hash required" };
  }
  const hash = fingerprintHash.trim().slice(0, 128);
  if (hash.length < 8) {
    return { ok: false, error: "fingerprint_hash too short" };
  }

  const { data, error } = await supabase
    .from("device_fingerprint_events")
    .insert({
      user_id: userId,
      fingerprint_hash: hash,
      zone: zone || null,
    })
    .select("id")
    .single();

  if (error) {
    console.warn("[DeviceFingerprint] insert failed:", error.message);
    return { ok: false, error: error.message };
  }
  return { ok: true, id: data.id };
}

/**
 * Count distinct other users in the same zone sharing this fingerprint in the rolling window.
 */
async function getSharedDeviceFraudBump(userId, zone, fingerprintHash) {
  if (!fingerprintHash || typeof fingerprintHash !== "string" || !zone) {
    return { bump: 0, other_users: 0, reason: null };
  }
  const hash = fingerprintHash.trim().slice(0, 128);
  if (hash.length < 8) {
    return { bump: 0, other_users: 0, reason: null };
  }

  const since = new Date(
    Date.now() - WINDOW_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  try {
    const { data, error } = await supabase
      .from("device_fingerprint_events")
      .select("user_id")
      .eq("fingerprint_hash", hash)
      .eq("zone", zone)
      .gte("created_at", since);

    if (error) throw error;
    const others = new Set();
    for (const row of data || []) {
      if (row.user_id && row.user_id !== userId) others.add(row.user_id);
    }
    const otherUsers = others.size;
    const bump = Math.min(MAX_BUMP, otherUsers * BUMP_PER_OTHER_USER);
    return {
      bump,
      other_users: otherUsers,
      reason:
        otherUsers > 0
          ? `shared_device_fingerprint:${otherUsers}_other_users_in_zone`
          : null,
    };
  } catch (e) {
    console.warn("[DeviceFingerprint] cluster query failed:", e.message);
    return { bump: 0, other_users: 0, reason: null };
  }
}

/**
 * Aggregates for judge / admin: top hashes by distinct user count (optional zone filter).
 */
async function getFingerprintStats({
  zone = null,
  days = WINDOW_DAYS,
  limit = 30,
} = {}) {
  const since = new Date(
    Date.now() - Number(days) * 24 * 60 * 60 * 1000,
  ).toISOString();

  let q = supabase
    .from("device_fingerprint_events")
    .select("fingerprint_hash, user_id, zone")
    .gte("created_at", since);

  if (zone) q = q.eq("zone", zone);

  const { data, error } = await q;
  if (error) throw error;

  const byHash = new Map();
  for (const row of data || []) {
    const h = row.fingerprint_hash;
    if (!byHash.has(h))
      byHash.set(h, { users: new Set(), zones: new Set(), events: 0 });
    const agg = byHash.get(h);
    agg.users.add(row.user_id);
    if (row.zone) agg.zones.add(row.zone);
    agg.events++;
  }

  const clusters = [...byHash.entries()]
    .map(([fingerprint_hash, v]) => ({
      fingerprint_hash,
      distinct_users: v.users.size,
      event_count: v.events,
      zones: [...v.zones],
    }))
    .filter((c) => c.distinct_users >= 2)
    .sort((a, b) => b.distinct_users - a.distinct_users)
    .slice(0, limit);

  return {
    window_days: Number(days) || WINDOW_DAYS,
    zone_filter: zone || null,
    cluster_count: clusters.length,
    clusters,
  };
}

module.exports = {
  recordFingerprint,
  getSharedDeviceFraudBump,
  getFingerprintStats,
};
