const cron = require("node-cron");
const { supabase } = require("../config/supabase");
const { sendPushNotification } = require("./notification-service");

const MAX_ATTEMPTS = Number(process.env.NOTIFICATION_MAX_ATTEMPTS || 3);
const BATCH_SIZE = Number(process.env.NOTIFICATION_RETRY_BATCH_SIZE || 25);
const SCHEDULE = process.env.NOTIFICATION_RETRY_CRON || "*/3 * * * *";
const DEGRADE_DUE_BACKLOG_THRESHOLD = Number(
  process.env.NOTIFICATION_DEGRADE_DUE_BACKLOG_THRESHOLD || 1000,
);
const DEGRADE_BATCH_SIZE = Number(
  process.env.NOTIFICATION_DEGRADE_BATCH_SIZE || 8,
);
const HARD_STOP_DUE_BACKLOG_THRESHOLD = Number(
  process.env.NOTIFICATION_HARD_STOP_DUE_BACKLOG_THRESHOLD || 5000,
);

let isRunning = false;
let lastRunAt = null;
let lastRunError = null;
let inFlight = false;
let lastDueBacklog = 0;
let lastRunMode = "normal";

function _nowIso() {
  return new Date().toISOString();
}

function _isoAfterMinutes(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000).toISOString();
}

function _backoffMinutes(attemptCount) {
  if (attemptCount <= 1) return 1;
  if (attemptCount === 2) return 5;
  return 15;
}

async function _markExpiredAndExceeded() {
  const nowIso = _nowIso();

  await supabase
    .from("notification_delivery_log")
    .update({
      status: "failed",
      error_code: "expired",
      error_message: "TTL expired before delivery",
      next_attempt_at: null,
      updated_at: nowIso,
    })
    .lt("expires_at", nowIso)
    .in("status", ["pending", "failed"]);

  await supabase
    .from("notification_delivery_log")
    .update({
      status: "failed",
      error_code: "max_attempts_exceeded",
      error_message: "Max retry attempts reached",
      next_attempt_at: null,
      updated_at: nowIso,
    })
    .gte("attempt_count", MAX_ATTEMPTS)
    .in("status", ["pending", "failed"]);
}

async function _loadDueRows(limit) {
  const nowIso = _nowIso();
  const { data, error } = await supabase
    .from("notification_delivery_log")
    .select(
      "id,notification_id,device_token,attempt_count,expires_at,user_id,notifications(title,body,metadata)",
    )
    .in("status", ["pending", "failed"])
    .gt("expires_at", nowIso)
    .lte("next_attempt_at", nowIso)
    .lt("attempt_count", MAX_ATTEMPTS)
    .order("next_attempt_at", { ascending: true })
    .limit(limit);

  if (error) throw error;
  return data || [];
}

async function _countDueRows() {
  const nowIso = _nowIso();
  const { count, error } = await supabase
    .from("notification_delivery_log")
    .select("id", { count: "exact", head: true })
    .in("status", ["pending", "failed"])
    .gt("expires_at", nowIso)
    .lte("next_attempt_at", nowIso)
    .lt("attempt_count", MAX_ATTEMPTS);

  if (error) throw error;
  return Number(count || 0);
}

async function _processRow(row) {
  const notif = row.notifications || {};
  const title = notif.title;
  const body = notif.body;
  const payload = notif.metadata || {};

  if (!row.device_token || !title || !body) {
    await supabase
      .from("notification_delivery_log")
      .update({
        status: "failed",
        error_code: "invalid_delivery_record",
        error_message: "Missing device token/title/body",
        next_attempt_at: null,
        updated_at: _nowIso(),
      })
      .eq("id", row.id);
    return;
  }

  const push = await sendPushNotification(
    row.device_token,
    title,
    body,
    payload,
  );
  const attempts = Number(row.attempt_count || 0) + 1;
  const update = {
    attempt_count: attempts,
    last_attempt_at: _nowIso(),
    updated_at: _nowIso(),
    error_code: push.errorCode || null,
    error_message: push.errorMessage || null,
  };

  if (push.success) {
    update.status = "sent";
    update.provider_message_id = push.providerMessageId || null;
    update.next_attempt_at = null;
  } else if (push.transient && attempts < MAX_ATTEMPTS) {
    update.status = "failed";
    update.next_attempt_at = _isoAfterMinutes(_backoffMinutes(attempts));
  } else {
    update.status = "failed";
    update.next_attempt_at = null;
  }

  const { error } = await supabase
    .from("notification_delivery_log")
    .update(update)
    .eq("id", row.id);

  if (error) throw error;
}

async function runNotificationRetryTick() {
  if (inFlight) return;
  inFlight = true;
  try {
    await _markExpiredAndExceeded();
    const dueBacklog = await _countDueRows();
    lastDueBacklog = dueBacklog;

    if (dueBacklog >= HARD_STOP_DUE_BACKLOG_THRESHOLD) {
      lastRunMode = "hard_stop";
      lastRunAt = _nowIso();
      lastRunError = `due backlog too high (${dueBacklog}) - retries skipped to protect free tier`;
      console.warn(
        `[Notification Retry] hard-stop active. due backlog=${dueBacklog}, threshold=${HARD_STOP_DUE_BACKLOG_THRESHOLD}`,
      );
      return;
    }

    const batchLimit =
      dueBacklog >= DEGRADE_DUE_BACKLOG_THRESHOLD
        ? DEGRADE_BATCH_SIZE
        : BATCH_SIZE;
    lastRunMode =
      dueBacklog >= DEGRADE_DUE_BACKLOG_THRESHOLD ? "degraded" : "normal";

    const rows = await _loadDueRows(batchLimit);

    for (const row of rows) {
      try {
        await _processRow(row);
      } catch (err) {
        console.warn(
          "[Notification Retry] row processing failed:",
          err.message,
        );
      }
    }

    lastRunAt = _nowIso();
    lastRunError = null;
  } catch (err) {
    lastRunAt = _nowIso();
    lastRunError = err.message;
    console.error("[Notification Retry] tick failed:", err.message);
  } finally {
    inFlight = false;
  }
}

function startNotificationRetryWorker() {
  if (isRunning) return;
  isRunning = true;
  cron.schedule(SCHEDULE, () => {
    runNotificationRetryTick();
  });
  console.log(`[Notification Retry] worker started with cron "${SCHEDULE}"`);
}

function getNotificationRetryStatus() {
  return {
    running: isRunning,
    lastRunAt,
    lastRunError,
    lastRunMode,
    dueBacklog: lastDueBacklog,
    maxAttempts: MAX_ATTEMPTS,
    batchSize: BATCH_SIZE,
    degradeDueBacklogThreshold: DEGRADE_DUE_BACKLOG_THRESHOLD,
    degradeBatchSize: DEGRADE_BATCH_SIZE,
    hardStopDueBacklogThreshold: HARD_STOP_DUE_BACKLOG_THRESHOLD,
  };
}

module.exports = {
  startNotificationRetryWorker,
  getNotificationRetryStatus,
  runNotificationRetryTick,
};

