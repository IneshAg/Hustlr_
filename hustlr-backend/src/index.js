require("dotenv").config();
const express = require("express");
const cors = require("cors");

const authRoutes = require("./routes/auth.routes");
const workerRoutes = require("./routes/worker.routes");
const policyRoutes = require("./routes/policy.routes");
const addonRoutes = require("./routes/addon.routes");
const claimsRoutes = require("./routes/claims.routes");
const walletRoutes = require("./routes/wallet.routes");
const paymentRoutes = require("./routes/payment.routes");
const disruptionRoutes = require("./routes/disruption.routes");
const guidewireRoutes = require("./routes/guidewire.routes");
const citiesRoutes = require("./routes/cities.routes");
const integrityRoutes = require("./routes/integrity.routes");
const mlRoutes = require("./routes/ml.routes");
const adminRoutes = require("./routes/admin.routes");
const { requireSession } = require("./middleware/session-auth");
// const shiftRoutes = require('./routes/shift.routes');
const mlService = require("./services/ml-service");
const demoRoutes = require("./routes/demo.routes");
const {
  startDisruptionCron,
  getDisruptionCronStatus,
} = require("./services/disruption-cron");
const {
  startRegionalWeeklyCron,
  getRegionalCronStatus,
} = require("./services/regional-weekly-cron");
const {
  startNotificationRetryWorker,
  getNotificationRetryStatus,
} = require("./services/notification-retry-worker");
const cron = require("node-cron");
const { createClient } = require("@supabase/supabase-js");

const app = express();

// Browser clients (e.g. Flutter web on Vercel): set CORS_ORIGIN=https://app.vercel.app (comma-separated for several).
if (
  process.env.CORS_ORIGIN &&
  process.env.CORS_ORIGIN.trim() &&
  process.env.CORS_ORIGIN.trim() !== "*"
) {
  const origins = process.env.CORS_ORIGIN.split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  app.use(
    cors({
      origin: origins.length === 1 ? origins[0] : origins,
      credentials: true,
    }),
  );
} else {
  app.use(cors());
}
app.use(express.json());

// Mount routes
app.use("/auth", authRoutes);
app.use("/workers", workerRoutes);
app.use("/policies", requireSession, policyRoutes);
app.use("/addons", requireSession, addonRoutes);
app.use("/claims", requireSession, claimsRoutes);
app.use("/wallet", requireSession, walletRoutes);
app.use("/payments", paymentRoutes);
app.use("/disruptions", disruptionRoutes);
app.use("/guidewire", guidewireRoutes);
app.use("/cities", citiesRoutes);
app.use("/integrity", requireSession, integrityRoutes);
app.use("/ml", mlRoutes);
app.use("/demo", demoRoutes);
app.use("/api/admin", adminRoutes);
// app.use('/shift', shiftRoutes);

const trustService = require("./services/trust-service");

// GET /workers/trust/:userId
app.get("/workers/trust/:userId", requireSession, async (req, res) => {
  if (req.authUserId !== req.params.userId) {
    return res.status(403).json({ error: "Forbidden" });
  }
  const profile = await trustService.getUserTrustProfile(req.params.userId);
  if (!profile) return res.status(404).json({ error: "Not found" });
  return res.json(profile);
});

// Health check (root)
app.get("/", (req, res) => {
  res.json({ status: "ok", service: "hustlr-backend" });
});

// Dedicated health endpoint pinged by the Flutter app
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "hustlr-backend",
    timestamp: new Date().toISOString(),
    uptime_seconds: Math.floor(process.uptime()),
  });
});

// Per-service health — real-time state from the api-wrapper circuit breaker
// plus env-key presence checks for APIs that aren't self-reporting.
app.get("/health/services", async (req, res) => {
  const { getAPIHealth } = require("./services/api-wrapper");
  const liveHealth = getAPIHealth(); // { weather, aqi, news, platform, internet, cell_tower, traffic }

  function toStatus(name) {
    const s = liveHealth[name];
    if (!s) return "unknown";
    if (s.healthy && s.failures === 0) return "ok";
    if (!s.healthy) return "degraded";
    return "ok"; // failures > 0 but still healthy = recovering
  }

  function envPresent(key) {
    return process.env[key] ? "ok" : "missing_key";
  }

  const { isMaxMindConfigured } = require("./services/maxmind-service");

  function maxmindEnvStatus() {
    if (isMaxMindConfigured()) return "ok";
    const a = !!(process.env.MAXMIND_ACCOUNT_ID || "").trim();
    const b = !!(process.env.MAXMIND_LICENSE_KEY || "").trim();
    if (!a && !b) return "missing_key";
    return "partial_key";
  }

  const ooklaKey = (process.env.OOKLA_API_KEY || "").trim();
  const ooklaEnabled =
    process.env.USE_OOKLA_INTERNET === "true" && ooklaKey.length > 0;
  let ooklaInternetStatus = "inferred_only";
  if (ooklaEnabled) ooklaInternetStatus = "enterprise_live";
  else if (ooklaKey.length > 0) {
    ooklaInternetStatus = "key_present_opt_in_disabled";
  }

  const {
    isConfigured: playIntegrityConfigured,
    isSimulatedMode,
  } = require("./services/play-integrity-service");
  let playIntegrityStatus = "not_configured";
  if (process.env.PLAY_INTEGRITY_BYPASS_DEV === "true")
    playIntegrityStatus = "dev_bypass";
  else if (isSimulatedMode()) playIntegrityStatus = "simulated";
  else if (playIntegrityConfigured()) playIntegrityStatus = "configured";

  res.json({
    // Core
    supabase: envPresent("SUPABASE_URL"),
    // Weather & Environment
    weather: toStatus("weather"),
    aqi: toStatus("aqi"),
    traffic: toStatus("traffic"),
    // Intelligence
    news: toStatus("news"),
    cell_tower: toStatus("cell_tower"),
    opencellid: process.env.OPENCELLID_API_KEY ? "ok" : "ok",
    maxmind: maxmindEnvStatus(),
    ookla_internet: ooklaInternetStatus,
    // Payments & Notifications
    paypal: envPresent("PAYPAL_CLIENT_ID"),
    stripe: envPresent("STRIPE_PUBLISHABLE_KEY"),
    guidewire:
      process.env.ENABLE_GUIDEWIRE_ROUTES === "true" ? "enabled" : "off",
    play_integrity: playIntegrityStatus,
    firebase: envPresent("FIREBASE_SERVER_KEY"),
    ml_service: (await mlService.isMlOnline()) ? "ok" : "offline",
    // Failure counts for detail
    _failures: Object.fromEntries(
      Object.entries(liveHealth).map(([k, v]) => [k, v.failures]),
    ),
  });
});

app.get("/health/cron", (req, res) => {
  res.json({
    ...getDisruptionCronStatus(),
    regional_weekly: getRegionalCronStatus(),
    notification_retry: getNotificationRetryStatus(),
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`hustlr-backend listening on port ${PORT}`);
  startDisruptionCron();
  startRegionalWeeklyCron();
  startNotificationRetryWorker();

  // Shift Watchdog: Auto-pause cron (every 60s)
  cron.schedule("* * * * *", async () => {
    try {
      const supabase = createClient(
        process.env.SUPABASE_URL,
        process.env.SUPABASE_SERVICE_KEY,
      );
      const staleTime = new Date(Date.now() - 120000).toISOString(); // 120s ago

      const { data: staleWorkers } = await supabase
        .from("users")
        .select("id, last_seen_at")
        .eq("shift_status", "ACTIVE")
        .lt("last_seen_at", staleTime);

      if (!staleWorkers || staleWorkers.length === 0) return;

      const now = new Date().toISOString();
      for (const w of staleWorkers) {
        // Pausing shift
        await supabase
          .from("users")
          .update({ shift_status: "PAUSED", paused_at: now })
          .eq("id", w.id);

        // Open a gap record
        await supabase
          .from("shift_gaps")
          .insert({ worker_id: w.id, gap_start: w.last_seen_at });

        console.log(
          `[Push] Sent to ${w.id}: GPS signal lost — your coverage is paused. Re-enable location to resume earning.`,
        );
      }
    } catch (e) {
      console.error("[Watchdog Cron] Error checking stale shifts:", e.message);
    }
  });
});
