const axios = require("axios");
const crypto = require("crypto");
const { supabase } = require("../config/supabase");

const FIREBASE_SERVER_KEY = process.env.FIREBASE_SERVER_KEY;
const FCM_URL = "https://fcm.googleapis.com/fcm/send";
const HIGH_PRIORITY_TTL_MINUTES = Number(
  process.env.HIGH_PRIORITY_EVENT_TTL_MINUTES || 60,
);

function _nowIso() {
  return new Date().toISOString();
}

function _isoAfterMinutes(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000).toISOString();
}

function _computeBackoffMinutes(attemptCount) {
  if (attemptCount <= 1) return 1;
  if (attemptCount === 2) return 5;
  return 15;
}

function _isPermanentProviderError(code) {
  const c = String(code || "").toLowerCase();
  return (
    c === "notregistered" ||
    c === "invalidregistration" ||
    c === "mismatchsenderid" ||
    c === "invalidregistrationtoken"
  );
}

/**
 * Send a push notification via Firebase Cloud Messaging (FCM).
 * Falls back to mock mode if no key is configured or the request fails.
 *
 * @param {string} deviceToken  - FCM device registration token
 * @param {string} title        - Notification title
 * @param {string} body         - Notification body
 * @param {object} [data]       - Optional key-value data payload
 */
async function sendPushNotification(deviceToken, title, body, data = {}) {
  if (!FIREBASE_SERVER_KEY) {
    console.warn("[FCM] FIREBASE_SERVER_KEY not set — skipping notification");
    return {
      source: "mock",
      success: false,
      transient: true,
      status: "skipped",
      errorCode: "no_key",
      errorMessage: "FIREBASE_SERVER_KEY not set",
      providerMessageId: null,
      timestamp: _nowIso(),
    };
  }

  try {
    const res = await axios.post(
      FCM_URL,
      {
        to: deviceToken,
        notification: { title, body },
        data,
        priority: "high",
      },
      {
        headers: {
          Authorization: `key=${FIREBASE_SERVER_KEY}`,
          "Content-Type": "application/json",
        },
        timeout: 5000,
      },
    );

    const failed = Number(res.data?.failure || 0);
    const providerError = res.data?.results?.[0]?.error;
    if (failed > 0 || providerError) {
      const code = providerError || "provider_failure";
      return {
        source: "live_fcm",
        success: false,
        transient: !_isPermanentProviderError(code),
        status: "failed",
        errorCode: code,
        errorMessage: code,
        providerMessageId: null,
        timestamp: _nowIso(),
      };
    }

    console.log(
      `[FCM] LIVE notification sent | title="${title}" | fcm_id=${res.data?.message_id ?? "n/a"}`,
    );
    return {
      source: "live_fcm",
      success: true,
      transient: false,
      status: "sent",
      errorCode: null,
      errorMessage: null,
      providerMessageId: res.data?.message_id || null,
      timestamp: _nowIso(),
    };
  } catch (e) {
    const errMsg = e.response?.data?.error || e.message;
    const status = Number(e.response?.status || 0);
    const transient = status >= 500 || status === 0 || status === 429;
    console.warn(`[FCM] failed: ${errMsg} — falling back to mock`);
    return {
      source: "mock",
      success: false,
      transient,
      status: "simulated",
      errorCode: String(status || "network_error"),
      errorMessage: errMsg,
      providerMessageId: null,
      timestamp: _nowIso(),
    };
  }
}

async function _persistNotificationRecord({
  userId,
  title,
  body,
  type,
  metadata,
}) {
  const { data, error } = await supabase
    .from("notifications")
    .insert({
      user_id: userId,
      title,
      body,
      type,
      metadata: metadata || {},
    })
    .select("id")
    .single();

  if (error) throw error;
  return data.id;
}

async function _insertDeliveryLog({
  notificationId,
  userId,
  deviceToken,
  eventType,
  tripId,
  stateVersion,
  expiresAt,
  idempotencyKey,
}) {
  const payload = {
    notification_id: notificationId,
    user_id: userId,
    device_token: deviceToken,
    event_type: eventType || "general",
    trip_id: tripId || null,
    state_version: stateVersion || null,
    status: "pending",
    attempt_count: 0,
    next_attempt_at: _nowIso(),
    expires_at: expiresAt,
    idempotency_key: idempotencyKey,
    created_at: _nowIso(),
    updated_at: _nowIso(),
  };

  const { data, error } = await supabase
    .from("notification_delivery_log")
    .upsert(payload, { onConflict: "idempotency_key,device_token" })
    .select("id,attempt_count")
    .single();

  if (error) throw error;
  return data;
}

async function _findExistingDeliveryLog(idempotencyKey, deviceToken) {
  const { data, error } = await supabase
    .from("notification_delivery_log")
    .select("id,notification_id,status,attempt_count")
    .eq("idempotency_key", idempotencyKey)
    .eq("device_token", deviceToken)
    .maybeSingle();

  if (error) throw error;
  return data || null;
}

async function _updateDeliveryLogAfterAttempt(
  logId,
  currentAttemptCount,
  pushResult,
) {
  const attemptCount = currentAttemptCount + 1;
  const update = {
    attempt_count: attemptCount,
    last_attempt_at: _nowIso(),
    updated_at: _nowIso(),
    error_code: pushResult.errorCode || null,
    error_message: pushResult.errorMessage || null,
  };

  if (pushResult.success) {
    update.status = "sent";
    update.provider_message_id = pushResult.providerMessageId;
    update.next_attempt_at = null;
  } else if (pushResult.transient && attemptCount < 3) {
    const delayMinutes = _computeBackoffMinutes(attemptCount);
    update.status = "failed";
    update.next_attempt_at = _isoAfterMinutes(delayMinutes);
  } else {
    update.status = "failed";
    update.next_attempt_at = null;
  }

  const { error } = await supabase
    .from("notification_delivery_log")
    .update(update)
    .eq("id", logId);

  if (error) throw error;
  return update;
}

async function persistAndSendNotification({
  userId,
  deviceToken,
  title,
  body,
  type = "general",
  metadata = {},
  eventType = "general",
  tripId = null,
  stateVersion = null,
  ttlMinutes = HIGH_PRIORITY_TTL_MINUTES,
  idempotencyKey,
}) {
  if (!userId) {
    throw new Error("persistAndSendNotification requires userId");
  }
  if (!deviceToken) {
    throw new Error("persistAndSendNotification requires deviceToken");
  }

  const finalIdempotencyKey =
    idempotencyKey ||
    crypto
      .createHash("sha256")
      .update(
        `${userId}:${eventType}:${tripId || ""}:${stateVersion || ""}:${title}:${body}`,
      )
      .digest("hex");

  const existing = await _findExistingDeliveryLog(
    finalIdempotencyKey,
    deviceToken,
  );
  if (existing) {
    return {
      notificationId: existing.notification_id,
      deliveryLogId: existing.id,
      idempotencyKey: finalIdempotencyKey,
      source: "dedupe",
      success: existing.status === "sent" || existing.status === "delivered",
      transient: false,
      status: "duplicate",
      errorCode: null,
      errorMessage: null,
      providerMessageId: null,
      timestamp: _nowIso(),
    };
  }

  const expiresAt = _isoAfterMinutes(ttlMinutes);
  const notificationId = await _persistNotificationRecord({
    userId,
    title,
    body,
    type,
    metadata,
  });

  const log = await _insertDeliveryLog({
    notificationId,
    userId,
    deviceToken,
    eventType,
    tripId,
    stateVersion,
    expiresAt,
    idempotencyKey: finalIdempotencyKey,
  });

  const pushResult = await sendPushNotification(
    deviceToken,
    title,
    body,
    metadata,
  );
  await _updateDeliveryLogAfterAttempt(
    log.id,
    log.attempt_count || 0,
    pushResult,
  );

  return {
    notificationId,
    deliveryLogId: log.id,
    idempotencyKey: finalIdempotencyKey,
    ...pushResult,
  };
}

/**
 * Convenience: send a disruption alert to a worker's device.
 */
async function sendDisruptionAlert({
  userId,
  deviceToken,
  triggerType,
  zone,
  payoutAmount,
  tripId,
  stateVersion,
  idempotencyKey,
}) {
  const title = "⚡ Disruption Detected in Your Zone";
  const body = `${_label(triggerType)} in ${zone} — You may be eligible for ₹${payoutAmount} payout.`;
  const data = {
    type: "disruption_alert",
    trigger_type: triggerType,
    zone,
    payout_amount: String(payoutAmount),
  };
  if (!userId) return sendPushNotification(deviceToken, title, body, data);
  return persistAndSendNotification({
    userId,
    deviceToken,
    title,
    body,
    type: "shadow_nudge",
    metadata: data,
    eventType: "disruption_alert",
    tripId,
    stateVersion,
    idempotencyKey,
  });
}

/**
 * Convenience: notify worker that a claim payout was credited.
 */
async function sendPayoutCredited({
  userId,
  deviceToken,
  amount,
  claimId,
  idempotencyKey,
}) {
  const title = "💰 Payout Credited!";
  const body = `₹${amount} has been added to your Hustlr wallet for claim #${claimId}.`;
  const data = {
    type: "payout_credited",
    claim_id: claimId,
    amount: String(amount),
  };
  if (!userId) return sendPushNotification(deviceToken, title, body, data);
  return persistAndSendNotification({
    userId,
    deviceToken,
    title,
    body,
    type: "payout_credited",
    metadata: data,
    eventType: "payout_credited",
    idempotencyKey,
  });
}

function _label(t) {
  const m = {
    rain_heavy: "Heavy Rain",
    heat_severe: "Extreme Heat",
    platform_outage: "Platform Downtime",
    aqi_hazardous: "Severe Pollution",
    bandh: "Bandh/Curfew",
  };
  return m[t] ?? t;
}

/**
 * Predictive nudge from weather / cron (Phase 2).
 */
async function sendPredictiveNudge({
  userId,
  deviceToken,
  zone,
  nudge,
  idempotencyKey,
}) {
  if (!deviceToken || !nudge?.message) {
    return { source: "skipped", reason: "no_token_or_message" };
  }
  const title =
    nudge.urgency === "HIGH"
      ? "⚠️ High rain risk in your zone"
      : "🌧️ Weather heads-up";
  const body = `${nudge.message} ${nudge.sub_message || ""}`
    .trim()
    .slice(0, 180);
  const data = {
    type: "predictive_nudge",
    zone: zone || "",
    urgency: nudge.urgency || "MEDIUM",
    rain_chance: String(nudge.rain_chance ?? ""),
  };
  if (!userId) return sendPushNotification(deviceToken, title, body, data);
  return persistAndSendNotification({
    userId,
    deviceToken,
    title,
    body,
    type: "shadow_nudge",
    metadata: data,
    eventType: "predictive_nudge",
    idempotencyKey,
  });
}

module.exports = {
  sendPushNotification,
  persistAndSendNotification,
  sendDisruptionAlert,
  sendPayoutCredited,
  sendPredictiveNudge,
};
