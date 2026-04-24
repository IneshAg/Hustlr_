const express = require("express");
const { supabase } = require("../config/supabase");
const { computeZoneDepthAsync } = require("../services/zone-depth-service");
const { estimateLocation } = require("../services/cell-tower-service");
const {
  recordFingerprint,
  getFingerprintStats,
} = require("../services/device-fingerprint-service");
const { sendPushNotification } = require("../services/notification-service");
const { requireSession } = require("../middleware/session-auth");
const router = express.Router();

// GET /workers/phone/:phone
router.get("/phone/:phone", async (req, res) => {
  try {
    const { phone } = req.params;
    const { data: user, error } = await supabase
      .from("users")
      .select("*")
      .eq("phone", phone)
      .maybeSingle();
    if (error && error.code !== "PGRST116") throw error;
    if (!user) return res.status(404).json({ error: "User not found" });
    res.json({ user });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /workers/register
router.post("/register", async (req, res) => {
  const { name, phone, zone, city, platform } = req.body;

  if (!name || !phone || !zone || !city) {
    return res
      .status(400)
      .json({ error: "name, phone, zone and city are required" });
  }

  try {
    // Return existing worker if already registered
    const { data: existing } = await supabase
      .from("users")
      .select("*")
      .eq("phone", phone)
      .maybeSingle();

    if (existing) {
      return res
        .status(200)
        .json({ user: existing, message: "Worker already registered" });
    }

    // Create new worker
    const { data: user, error } = await supabase
      .from("users")
      .insert([
        {
          name,
          phone,
          zone,
          city,
          platform: platform || "Zepto",
          iss_score: 75,
        },
      ])
      .select()
      .single();

    if (error) throw error;

    return res.status(201).json({ user });
  } catch (e) {
    console.error("[Workers] Register error:", e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /workers/cell-locate — OpenCelliD and/or Unwired Labs (see .env.example)
router.post("/cell-locate", async (req, res) => {
  try {
    const result = await estimateLocation(req.body || {});
    if (result.error) {
      return res.status(400).json(result);
    }
    return res.json(result);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// All routes below this line require an active single-session token.
router.use(requireSession);

// POST /workers/fingerprint — record device hash for cluster / fraud (Phase 2)
router.post("/fingerprint", async (req, res) => {
  try {
    const { user_id, fingerprint_hash, zone } = req.body || {};
    const out = await recordFingerprint(user_id, fingerprint_hash, zone);
    if (!out.ok) {
      return res.status(400).json(out);
    }
    return res.status(201).json(out);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /workers/fingerprint/stats — shared-hash clusters (judge / admin)
router.get("/fingerprint/stats", async (req, res) => {
  try {
    const zone = req.query.zone || null;
    const days =
      req.query.days != null ? parseInt(String(req.query.days), 10) : 7;
    const limit =
      req.query.limit != null ? parseInt(String(req.query.limit), 10) : 30;
    const stats = await getFingerprintStats({
      zone: zone || null,
      days: Number.isFinite(days) ? days : 7,
      limit: Number.isFinite(limit) ? limit : 30,
    });
    return res.json(stats);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// POST /workers/zone-depth/compute — lat/lon → score (no DB write); PostGIS when enabled
router.post("/zone-depth/compute", async (req, res) => {
  const lat = Number(req.body?.lat);
  const lon = Number(req.body?.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return res
      .status(400)
      .json({ error: "lat and lon must be finite numbers" });
  }
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return res.status(400).json({ error: "lat/lon out of range" });
  }
  try {
    res.json(await computeZoneDepthAsync(lat, lon));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /workers/:id
router.get("/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { data: user, error: userError } = await supabase
      .from("users")
      .select("*")
      .eq("id", id)
      .single();
    if (userError) throw userError;

    const { data: active_policy } = await supabase
      .from("policies")
      .select("*")
      .eq("user_id", id)
      .eq("status", "active")
      .maybeSingle();

    res.json({ user, active_policy: active_policy || null });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// PATCH /workers/:id
// Supports lightweight profile updates from mobile client (zone/city/onboarding).
router.patch("/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { zone, city, onboarding_complete, kyc_status } = req.body || {};

    const updates = {};
    if (typeof zone === "string" && zone.trim().length > 0) {
      updates.zone = zone.trim();
    }
    if (typeof city === "string" && city.trim().length > 0) {
      updates.city = city.trim();
    }
    if (typeof onboarding_complete === "boolean") {
      updates.onboarding_complete = onboarding_complete;
    }
    if (typeof kyc_status === "string" && ["pending", "verified", "rejected"].includes(kyc_status)) {
      updates.kyc_status = kyc_status;
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: "No valid update fields provided" });
    }

    const { data: updated_user, error } = await supabase
      .from("users")
      .update(updates)
      .eq("id", id)
      .select("*")
      .single();

    if (error) throw error;
    res.json({ updated_user });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// PATCH /workers/:id/iss
router.patch("/:id/iss", async (req, res) => {
  try {
    const { id } = req.params;
    const { iss_score } = req.body;
    const { data: updated_user, error } = await supabase
      .from("users")
      .update({ iss_score })
      .eq("id", id)
      .select()
      .single();
    if (error) throw error;
    res.json({ updated_user });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// PATCH /workers/:id/zone-depth — persist zone_depth_score from lat/lon (PostGIS when USE_POSTGIS_ZONE_DEPTH=true)
router.patch("/:id/zone-depth", async (req, res) => {
  try {
    const { id } = req.params;
    const lat = Number(req.body?.lat);
    const lon = Number(req.body?.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return res
        .status(400)
        .json({ error: "lat and lon must be finite numbers" });
    }
    const { zone_depth_score, distance_km, hub, source } =
      await computeZoneDepthAsync(lat, lon);
    const { data: updated_user, error } = await supabase
      .from("users")
      .update({ zone_depth_score })
      .eq("id", id)
      .select()
      .single();
    if (error) throw error;
    res.json({ updated_user, distance_km, hub, source });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// PATCH /workers/:id/fcm-token
// Persist the latest Firebase token for this user.
router.patch("/:id/fcm-token", async (req, res) => {
  try {
    const { id } = req.params;
    const { fcm_token } = req.body || {};

    if (!req.authUserId || req.authUserId !== id) {
      return res.status(403).json({ error: "Forbidden" });
    }
    if (typeof fcm_token !== "string" || fcm_token.trim().length < 20) {
      return res.status(400).json({ error: "Valid fcm_token is required" });
    }

    const { data: updated_user, error } = await supabase
      .from("users")
      .update({
        fcm_token: fcm_token.trim(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", id)
      .select("id,name,fcm_token")
      .single();

    if (error) throw error;
    res.json({ updated_user, saved: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /workers/:id/push-test
// Sends a test push notification to verify device setup.
router.post("/:id/push-test", async (req, res) => {
  try {
    const { id } = req.params;
    if (!req.authUserId || req.authUserId !== id) {
      return res.status(403).json({ error: "Forbidden" });
    }

    const { data: user, error } = await supabase
      .from("users")
      .select("id,name,fcm_token")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!user) return res.status(404).json({ error: "User not found" });
    if (!user.fcm_token) {
      return res.status(400).json({ error: "No fcm_token saved for this user" });
    }

    const push = await sendPushNotification(
      user.fcm_token,
      "Hustlr Push Check",
      "Phone notifications are now connected.",
      {
        type: "push_test",
        user_id: id,
      },
    );

    res.json({ ok: true, push });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
