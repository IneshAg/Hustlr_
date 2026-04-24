-- SECTION 5 — TRUST, NOTIFICATIONS, REFERRALS
-- ═══════════════════════════════════════════════════════════════

-- ── 5a. TRUST EVENTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trust_events (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        REFERENCES users(id) ON DELETE CASCADE,
  event_type    TEXT        NOT NULL,
  score_change  INTEGER     NOT NULL,
  new_score     INTEGER     NOT NULL,
  reason        TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5b. NOTIFICATIONS ─────────────────────────────────────────
-- Persistent inbox. FCM sends the push; this stores the record.
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  body        TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'general'
              CHECK (type IN (
                'payout_credited','claim_update','policy_renewal',
                'shadow_nudge','fraud_alert','kyc_update',
                'driver_assigned','driver_arrived','trip_cancelled',
                'payment_failed','general'
              )),
  read        BOOLEAN     NOT NULL DEFAULT FALSE,
  action_url  TEXT        DEFAULT NULL,
  metadata    JSONB       DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5b-2. NOTIFICATION DELIVERY LOG (durable send state) ────
CREATE TABLE IF NOT EXISTS notification_delivery_log (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id     UUID        NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_token        TEXT        NOT NULL,
  event_type          TEXT        NOT NULL DEFAULT 'general',
  trip_id             TEXT        DEFAULT NULL,
  state_version       BIGINT      DEFAULT NULL,
  status              TEXT        NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'sent', 'failed', 'delivered')),
  attempt_count       INTEGER     NOT NULL DEFAULT 0,
  next_attempt_at     TIMESTAMPTZ DEFAULT NOW(),
  last_attempt_at     TIMESTAMPTZ DEFAULT NULL,
  error_code          TEXT        DEFAULT NULL,
  error_message       TEXT        DEFAULT NULL,
  expires_at          TIMESTAMPTZ NOT NULL,
  provider_message_id TEXT        DEFAULT NULL,
  idempotency_key     TEXT        NOT NULL,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (idempotency_key, device_token)
);

-- ── 5c. REFERRALS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS referrals (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referred_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reward_amount   INTEGER     NOT NULL DEFAULT 50,
  reward_status   TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (reward_status IN ('pending','paid','expired')),
  reward_paid_at  TIMESTAMPTZ DEFAULT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (referrer_id, referred_id)
);

-- ═══════════════════════════════════════════════════════════════
