const cron = require("node-cron");
const { fetchDisruptionBundle } = require("./disruption-snapshot");
const { supabase } = require("../config/supabase");
const { sendPredictiveNudge } = require("./notification-service");

const DEDUP_MINUTES = parseInt(
  process.env.DISRUPTION_CRON_DEDUP_MINUTES || "90",
  10,
);
const NUDGE_COOLDOWN_MS = parseInt(
  process.env.PREDICTIVE_NUDGE_COOLDOWN_MS || String(6 * 60 * 60 * 1000),
  10,
);

let lastRunAt = null;
const lastNudgeSentByZone = new Map();
let lastRunError = null;
let lastZonesSummary = null;

function parseMonitoredZones() {
  const raw =
    process.env.MONITORED_ZONES || "Adyar,Velachery,OMR,T Nagar,Anna Nagar";
  return raw
    .split(",")
    .map((z) => z.trim())
    .filter(Boolean);
}

function hasSupabase() {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY);
}

async function recentEventExists(zone, triggerType) {
  if (!hasSupabase()) return false;
  const since = new Date(Date.now() - DEDUP_MINUTES * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("disruption_events")
    .select("id")
    .eq("zone", zone)
    .eq("trigger_type", triggerType)
    .gte("started_at", since)
    .limit(1);

  if (error) {
    console.warn("[Cron] disruption_events dedup query:", error.message);
    return false;
  }
  return (data && data.length > 0) || false;
}

async function persistActiveTriggers(bundle) {
  if (!hasSupabase() || !bundle.disruptions?.length) return 0;

  const city = process.env.DEFAULT_CITY || "Chennai";
  let inserted = 0;

  for (const d of bundle.disruptions) {
    const triggerType = d.trigger_type || "unknown";
    if (await recentEventExists(bundle.zone, triggerType)) continue;

    const row = {
      zone: bundle.zone,
      city,
      trigger_type: triggerType,
      severity: typeof d.severity === "number" ? d.severity : 1,
      rainfall_mm: bundle.weather?.rainfall_mm_1h ?? 0,
      temperature_c: bundle.weather?.temp_celsius ?? 0,
      aqi: bundle.aqi?.current ?? 0,
      data_source: d.source || "cron_monitor",
    };

    const { error } = await supabase.from("disruption_events").insert([row]);
    if (error) {
      console.warn("[Cron] insert disruption_events:", error.message);
    } else {
      inserted += 1;
    }
  }
  return inserted;
}

async function pushPredictiveNudgesForZone(zone, bundle) {
  if (process.env.DISABLE_PREDICTIVE_NUDGE_PUSH === "true") return;
  if (!hasSupabase()) return;
  const nudge = bundle?.predictive_nudge;
  if (!nudge || !nudge.message) return;

  const last = lastNudgeSentByZone.get(zone) || 0;
  if (Date.now() - last < NUDGE_COOLDOWN_MS) return;

  const { data: users, error } = await supabase
    .from("users")
    .select("id,fcm_token")
    .eq("zone", zone)
    .not("fcm_token", "is", null)
    .limit(80);
  if (error) {
    console.warn("[Cron] nudge user query:", error.message);
    return;
  }
  for (const u of users || []) {
    if (!u.fcm_token) continue;
    await sendPredictiveNudge({
      userId: u.id,
      deviceToken: u.fcm_token,
      zone,
      nudge,
      idempotencyKey: `predictive_nudge:${u.id}:${zone}:${nudge.urgency || "MEDIUM"}`,
    });
  }
  lastNudgeSentByZone.set(zone, Date.now());
}

async function runDisruptionMonitorTick() {
  const zones = parseMonitoredZones();
  const summary = { zones: zones.length, inserted: 0, errors: [] };

  for (const zone of zones) {
    try {
      const bundle = await fetchDisruptionBundle(zone, { useCache: false });
      const n = await persistActiveTriggers(bundle);
      summary.inserted += n;
      if (n > 0 || bundle?.predictive_nudge?.urgency === "HIGH") {
        await pushPredictiveNudgesForZone(zone, bundle);
      }
    } catch (e) {
      summary.errors.push({ zone, message: e.message });
    }
  }

  lastRunAt = new Date().toISOString();
  lastRunError = summary.errors.length ? summary.errors : null;
  lastZonesSummary = summary;

  console.log(
    `[Cron] disruption monitor @ ${lastRunAt} — ` +
      `zones=${summary.zones} rows_inserted=${summary.inserted}` +
      (summary.errors.length ? ` errors=${summary.errors.length}` : ""),
  );
}

function startDisruptionCron() {
  if (process.env.DISABLE_DISRUPTION_CRON === "true") {
    console.log("[Cron] disruption monitor disabled (DISABLE_DISRUPTION_CRON)");
    return;
  }

  const schedule = process.env.DISRUPTION_CRON_SCHEDULE || "*/15 * * * *";
  cron.schedule(schedule, () => {
    runDisruptionMonitorTick().catch((e) => {
      lastRunError = [{ zone: "_tick", message: e.message }];
      console.error("[Cron] disruption monitor tick failed:", e.message);
    });
  });

  console.log(
    `[Cron] disruption monitor scheduled (${schedule}) — ` +
      parseMonitoredZones().join(", "),
  );

  if (process.env.RUN_DISRUPTION_CRON_ON_BOOT === "true") {
    runDisruptionMonitorTick().catch((e) =>
      console.error("[Cron] boot tick failed:", e.message),
    );
  }
}

function getDisruptionCronStatus() {
  return {
    last_run_at: lastRunAt,
    last_error: lastRunError,
    last_summary: lastZonesSummary,
    monitored_zones: parseMonitoredZones(),
    dedup_minutes: DEDUP_MINUTES,
  };
}

module.exports = {
  startDisruptionCron,
  runDisruptionMonitorTick,
  getDisruptionCronStatus,
};
