-- NOTE: Destructive schema reset commands removed for live-safe usage.
-- If you need a full reset in a disposable environment, run that separately.

-- ═══════════════════════════════════════════════════════════════
-- HUSTLR — Complete Production Schema (All Phases)
-- Guidewire DEVTrails 2026
-- Run this ONCE in a fresh Supabase project.
-- If migrating from an existing DB run each ALTER TABLE
-- block individually and skip CREATE TABLE blocks that exist.
-- ═══════════════════════════════════════════════════════════════

-- ── Extensions ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ═══════════════════════════════════════════════════════════════
-- SECTION 1 — CORE TABLES
-- Order matters for foreign keys.
-- ═══════════════════════════════════════════════════════════════

-- ── 1a. USERS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                TEXT        NOT NULL,
  phone               TEXT        UNIQUE NOT NULL,
  zone                TEXT        NOT NULL,
  city                TEXT        NOT NULL,
  platform            TEXT        NOT NULL DEFAULT 'Zepto',

  -- Actuarial — backend only, NEVER sent to Flutter
  iss_score           INTEGER     DEFAULT NULL,

  -- Shift metadata
  shift_start         TIME        DEFAULT '08:00',
  shift_end           TIME        DEFAULT '22:00',
  shift_status        TEXT        NOT NULL DEFAULT 'OFFLINE'
                                  CHECK (shift_status IN ('OFFLINE','ACTIVE','PAUSED')),
  last_seen_at        TIMESTAMPTZ DEFAULT NULL,
  paused_at           TIMESTAMPTZ DEFAULT NULL,
  days_active         INTEGER     DEFAULT 0,

  -- Auth / onboarding
  onboarding_complete BOOLEAN     DEFAULT FALSE,
  fcm_token           TEXT        DEFAULT NULL,
  kyc_status          TEXT        NOT NULL DEFAULT 'pending'
                                  CHECK (kyc_status IN ('pending','submitted','verified','rejected')),
  kyc_verified_at     TIMESTAMPTZ DEFAULT NULL,

  -- Referral system
  referral_code       TEXT        UNIQUE DEFAULT NULL,
  referred_by         UUID        REFERENCES users(id) ON DELETE SET NULL,

  -- Trust / loyalty
  trust_score         INTEGER     DEFAULT 100,
  trust_tier          TEXT        DEFAULT 'SILVER',
  clean_weeks         INTEGER     DEFAULT 0,
  cashback_earned     INTEGER     DEFAULT 0,
  cashback_pending    INTEGER     DEFAULT 0,

  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);
-- ── 1a2. AUTH SESSIONS (single active session / user) ───────
CREATE TABLE IF NOT EXISTS auth_sessions (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone          TEXT        NOT NULL,
  token_hash     TEXT        NOT NULL UNIQUE,
  device_id      TEXT        DEFAULT NULL,
  device_label   TEXT        DEFAULT NULL,
  is_active      BOOLEAN     NOT NULL DEFAULT TRUE,
  revoked_reason TEXT        DEFAULT NULL,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at   TIMESTAMPTZ DEFAULT NOW(),
  revoked_at     TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_active
  ON auth_sessions (user_id, is_active);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_last_seen
  ON auth_sessions (user_id, last_seen_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_sessions_single_active
  ON auth_sessions (user_id)
  WHERE is_active = TRUE;

-- ── 1b. RISK POOLS ────────────────────────────────────────────
-- Each city × risk_type is a separate actuarial pool.
-- Chennai Rain ≠ Chennai AQI — correlated perils must be isolated.
CREATE TABLE IF NOT EXISTS risk_pools (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  city                TEXT        NOT NULL,
  risk_type           TEXT        NOT NULL,
  pool_name           TEXT        NOT NULL,
  total_premium       INTEGER     NOT NULL DEFAULT 0,
  total_claims_paid   INTEGER     NOT NULL DEFAULT 0,
  reserve_fund        INTEGER     NOT NULL DEFAULT 0,
  loss_ratio          FLOAT       NOT NULL DEFAULT 0,
  active_policies     INTEGER     NOT NULL DEFAULT 0,
  enrollment_stopped  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (city, risk_type)
);

-- Seed standard pools
INSERT INTO risk_pools (city, risk_type, pool_name) VALUES
  ('Chennai',   'rain',     'Chennai Rain Pool'),
  ('Chennai',   'aqi',      'Chennai AQI Pool'),
  ('Chennai',   'platform', 'Chennai Platform Pool'),
  ('Mumbai',    'rain',     'Mumbai Rain Pool'),
  ('Mumbai',    'platform', 'Mumbai Platform Pool'),
  ('Delhi',     'aqi',      'Delhi AQI Pool'),
  ('Bengaluru', 'platform', 'Bengaluru Platform Pool'),
  ('Kolkata',   'rain',     'Kolkata Rain Pool')
ON CONFLICT (city, risk_type) DO NOTHING;

-- ── 1c. POLICIES ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS policies (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_tier           TEXT        NOT NULL DEFAULT 'standard'
                                  CHECK (plan_tier IN ('basic','standard','full')),
  base_premium        INTEGER     NOT NULL DEFAULT 49,
  zone_adjustment     INTEGER     NOT NULL DEFAULT 0,
  -- iss_adjustment is always 0 — flat pricing, ISS never affects worker price
  iss_adjustment      INTEGER     NOT NULL DEFAULT 0,
  weekly_premium      INTEGER     NOT NULL DEFAULT 49,
  max_weekly_payout   INTEGER     NOT NULL DEFAULT 340,
  max_daily_payout    INTEGER     NOT NULL DEFAULT 150,
  riders              TEXT[]      DEFAULT '{}',
  status              TEXT        NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active','expired','cancelled','renewed','suspended')),
  auto_renew          BOOLEAN     NOT NULL DEFAULT TRUE,
  coverage_start      DATE        NOT NULL DEFAULT CURRENT_DATE,
  coverage_end        DATE        NOT NULL DEFAULT CURRENT_DATE + INTERVAL '91 days',

  -- Which pool bears this policy's risk
  -- Derived from user.city + primary trigger type for the plan
  pool_id             UUID        REFERENCES risk_pools(id),

  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ── 1d. APPEAL REQUESTS ───────────────────────────────────────
-- Declared before claims so claims can reference it.
CREATE TABLE IF NOT EXISTS appeal_requests (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claim_id            UUID        NOT NULL,   -- FK added after claims table
  reason              TEXT        NOT NULL,
  evidence_urls       TEXT[]      DEFAULT '{}',
  status              TEXT        NOT NULL DEFAULT 'open'
                                  CHECK (status IN ('open','under_review','approved','rejected')),
  reviewed_by         TEXT        DEFAULT NULL,
  review_note         TEXT        DEFAULT NULL,
  opened_at           TIMESTAMPTZ DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ DEFAULT NULL,

  UNIQUE (claim_id)
);

-- ── 1e. CLAIMS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS claims (
  id                    UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  policy_id             UUID      REFERENCES policies(id) ON DELETE SET NULL,

  -- Event data
  trigger_type          TEXT      NOT NULL,
  zone                  TEXT      NOT NULL,
  city                  TEXT      NOT NULL DEFAULT 'Chennai',
  severity              FLOAT     NOT NULL DEFAULT 1.0  CHECK (severity BETWEEN 0 AND 1),
  duration_hours        FLOAT     NOT NULL DEFAULT 3.0  CHECK (duration_hours > 0),

  -- Payout breakdown
  -- gross_payout = committed liability on APPROVED
  -- tranche1 = 70% — released in minutes
  -- tranche2 = 30% — released Sunday 11 PM
  gross_payout          INTEGER   NOT NULL CHECK (gross_payout >= 0),
  tranche1              INTEGER   NOT NULL CHECK (tranche1 >= 0),
  tranche2              INTEGER   NOT NULL CHECK (tranche2 >= 0),

  -- Fraud scoring
  fraud_score           INTEGER   NOT NULL DEFAULT 0 CHECK (fraud_score BETWEEN 0 AND 100),
  fraud_status          TEXT      NOT NULL DEFAULT 'CLEAN'
                                  CHECK (fraud_status IN ('CLEAN','REVIEW','FLAGGED','REJECTED')),
  fps_signals           JSONB     DEFAULT '{}',

  -- Validation flags
  zone_depth_score      FLOAT     DEFAULT NULL,
  shift_verified        BOOLEAN   DEFAULT TRUE,
  underwriting_passed   BOOLEAN   DEFAULT TRUE,

  -- Lifecycle
  status                TEXT      NOT NULL DEFAULT 'PENDING'
                                  CHECK (status IN ('PENDING','APPROVED','FLAGGED','REJECTED','SETTLED','PAYOUT_FAILED')),
  tranche1_released_at  TIMESTAMPTZ DEFAULT NULL,
  tranche2_released_at  TIMESTAMPTZ DEFAULT NULL,
  settled_at            TIMESTAMPTZ DEFAULT NULL,

  -- Payout retry tracking (rollback logic)
  payout_attempts       INTEGER   DEFAULT 0,
  payout_error          TEXT      DEFAULT NULL,
  payout_failed_at      TIMESTAMPTZ DEFAULT NULL,

  -- Appeal linkage
  appeal_id             UUID      REFERENCES appeal_requests(id) ON DELETE SET NULL,

  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- Now add the FK from appeal_requests → claims
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_appeals_claim'
      AND table_name = 'appeal_requests'
  ) THEN
    ALTER TABLE appeal_requests
      ADD CONSTRAINT fk_appeals_claim
      FOREIGN KEY (claim_id) REFERENCES claims(id) ON DELETE CASCADE;
  END IF;
END $$;

-- ── 1f. WALLET TRANSACTIONS ───────────────────────────────────
-- Amount is always non-negative; direction is determined by `type`.
-- No separate wallets table in base schema. Balance is query-derived.
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount      INTEGER     NOT NULL,   -- positive = credit, negative = debit
  type        TEXT        NOT NULL    CHECK (type IN ('credit','debit')),
  category    TEXT        NOT NULL DEFAULT 'other'
              CHECK (category IN (
                'premium','payout_tranche1','payout_tranche2',
                'cashback','withdrawal','refund','other'
              )),
  reference   TEXT,
  description TEXT,
  claim_id    UUID        REFERENCES claims(id) ON DELETE SET NULL,
  upi_ref     TEXT        DEFAULT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
  -- No updated_at — transactions are append-only
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'wallet_transactions'
      AND constraint_name = 'chk_wallet_amount_non_negative'
  ) THEN
    ALTER TABLE wallet_transactions
      ADD CONSTRAINT chk_wallet_amount_non_negative
      CHECK (amount >= 0) NOT VALID;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 2 — FRAUD & TELEMETRY
-- ═══════════════════════════════════════════════════════════════

-- ── 2a. FRAUD BASELINES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS fraud_baselines (
  id                      UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID    UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  avg_daily_deliveries    FLOAT   DEFAULT 0,
  typical_zones           TEXT[]  DEFAULT '{}',
  avg_shift_start_hour    INTEGER DEFAULT 8,
  avg_shift_end_hour      INTEGER DEFAULT 22,
  home_wifi_ssids         TEXT[]  DEFAULT '{}',
  typical_cell_towers     TEXT[]  DEFAULT '{}',
  weeks_active            INTEGER DEFAULT 0,
  claim_count_30d         INTEGER DEFAULT 0,
  last_updated            TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2b. FRAUD FLAGS ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fraud_flags (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claim_id    UUID        REFERENCES claims(id) ON DELETE SET NULL,
  reason      TEXT        NOT NULL,
  frs_score   INTEGER     NOT NULL DEFAULT 0,
  timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved    BOOLEAN     DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2c. DEVICE FINGERPRINT EVENTS ────────────────────────────
CREATE TABLE IF NOT EXISTS device_fingerprint_events (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fingerprint_hash  TEXT        NOT NULL,
  zone              TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2d. SHIFT TELEMETRY ───────────────────────────────────────
-- One row per GPS heartbeat ping (~every 30 seconds during active shift).
CREATE TABLE IF NOT EXISTS shift_telemetry (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lat               FLOAT8      NOT NULL,
  lng               FLOAT8      NOT NULL,
  accuracy          FLOAT4,     -- metres; > 50m = low confidence
  timestamp         TIMESTAMPTZ NOT NULL,
  is_mock_location  BOOLEAN     DEFAULT FALSE,
  activity_type     TEXT,       -- 'in_vehicle','on_foot','still','unknown'
  battery_level     FLOAT4,     -- 0.0–1.0
  signal_strength   INTEGER,    -- dBm
  is_low_confidence BOOLEAN     DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2e. SHIFT GAPS ────────────────────────────────────────────
-- Logged when GPS heartbeat drops > 120 seconds.
-- Gaps > 600s → +10 FRS penalty. Gaps > 1800s → +20 FRS.
CREATE TABLE IF NOT EXISTS shift_gaps (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gap_start             TIMESTAMPTZ NOT NULL,
  gap_end               TIMESTAMPTZ,       -- NULL until GPS resumes
  gap_duration_seconds  INTEGER,
  frs_penalty           INTEGER     DEFAULT 0,
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2f. PENDING FRS ADJUSTMENTS ──────────────────────────────
-- Queued by telemetry pipeline; consumed on next claim submission.
CREATE TABLE IF NOT EXISTS pending_frs_adjustments (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  adjustment  INTEGER     NOT NULL,
  reason      TEXT        NOT NULL,
  is_consumed BOOLEAN     DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- SECTION 3 — DISRUPTION & SHADOW POLICY
-- ═══════════════════════════════════════════════════════════════

-- ── 3a. DISRUPTION EVENTS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS disruption_events (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  zone              TEXT        NOT NULL,
  city              TEXT        NOT NULL DEFAULT 'Chennai',
  trigger_type      TEXT        NOT NULL,
  severity          FLOAT       NOT NULL DEFAULT 1.0,
  rainfall_mm       FLOAT       DEFAULT 0,
  temperature_c     FLOAT       DEFAULT 0,
  aqi               INTEGER     DEFAULT 0,
  data_source       TEXT        DEFAULT 'live',
  started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at          TIMESTAMPTZ DEFAULT NULL,
  duration_hrs      FLOAT       DEFAULT NULL,  -- auto-computed by trigger
  payout_triggered  BOOLEAN     DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3b. SHADOW POLICIES ──────────────────────────────────────
-- Tracks what uninsured workers would have received.
-- Drives the "You missed ₹680 this fortnight" conversion nudge.
CREATE TABLE IF NOT EXISTS shadow_policies (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start          DATE        NOT NULL,
  simulated_payout    INTEGER     NOT NULL DEFAULT 0,
  disruption_events   JSONB       DEFAULT '[]',
  nudge_sent          BOOLEAN     DEFAULT FALSE,
  nudge_sent_at       TIMESTAMPTZ DEFAULT NULL,
  created_at          TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, week_start)
);

-- ═══════════════════════════════════════════════════════════════
-- SECTION 4 — POOL HEALTH & CIRCUIT BREAKER
-- ═══════════════════════════════════════════════════════════════

-- ── 4a. POOL HEALTH (weekly snapshot) ────────────────────────
-- One row per (week_start, city, risk_type) written by Sunday cron.
CREATE TABLE IF NOT EXISTS pool_health (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start          DATE        NOT NULL,
  city                TEXT        NOT NULL,
  risk_type           TEXT        NOT NULL DEFAULT 'rain',
  premiums_collected  INTEGER     DEFAULT 0,
  claims_paid         INTEGER     DEFAULT 0,   -- = sum(gross_payout) for APPROVED claims
  burning_cost_rate   FLOAT       DEFAULT 0,   -- claims_paid / premiums_collected
  enrollment_stopped  BOOLEAN     DEFAULT FALSE,
  created_at          TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (week_start, city, risk_type)
);

-- ── 4b. CIRCUIT BREAKERS ──────────────────────────────────────
-- Keyed on (zone, trigger_type) — a zone-level rate limiter.
-- Also trips when city-level BCR > 0.85 (see cron.js).
CREATE TABLE IF NOT EXISTS circuit_breakers (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  zone            TEXT        NOT NULL,
  city            TEXT        NOT NULL DEFAULT 'Chennai',
  trigger_type    TEXT        NOT NULL,
  claims_count    INTEGER     DEFAULT 0,
  hourly_limit    INTEGER     DEFAULT 50,
  daily_limit     INTEGER     DEFAULT 500,
  bcr_at_trip     FLOAT       DEFAULT 0,
  tripped         BOOLEAN     DEFAULT FALSE,
  tripped_at      TIMESTAMPTZ DEFAULT NULL,
  reset_at        TIMESTAMPTZ DEFAULT NULL,
  reason          TEXT        DEFAULT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (zone, trigger_type)
);

-- ── 4c. WEEKLY SETTLEMENTS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS weekly_settlements (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start            DATE        NOT NULL,
  week_end              DATE        NOT NULL,
  city                  TEXT        NOT NULL,
  risk_type             TEXT        NOT NULL,
  total_premium         INTEGER     NOT NULL DEFAULT 0,
  total_claims_paid     INTEGER     NOT NULL DEFAULT 0,
  loss_ratio            FLOAT       NOT NULL DEFAULT 0,
  policies_count        INTEGER     NOT NULL DEFAULT 0,
  claims_count          INTEGER     NOT NULL DEFAULT 0,
  reserve_contribution  INTEGER     NOT NULL DEFAULT 0,
  reinsurance_triggered BOOLEAN     DEFAULT FALSE,
  settled_at            TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (week_start, city, risk_type)
);

-- ── 4d. REINSURANCE TRIGGERS ──────────────────────────────────
CREATE TABLE IF NOT EXISTS reinsurance_triggers (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id     UUID        NOT NULL REFERENCES weekly_settlements(id) ON DELETE CASCADE,
  city              TEXT        NOT NULL,
  risk_type         TEXT        NOT NULL,
  loss_ratio        FLOAT       NOT NULL,
  excess_claims     INTEGER     NOT NULL DEFAULT 0,
  reinsurer_name    TEXT        DEFAULT 'Munich Re',
  amount_recovered  INTEGER     DEFAULT 0,
  status            TEXT        NOT NULL DEFAULT 'filed'
                                CHECK (status IN ('filed','processing','settled','rejected')),
  filed_at          TIMESTAMPTZ DEFAULT NOW(),
  settled_at        TIMESTAMPTZ DEFAULT NULL
);

-- ═══════════════════════════════════════════════════════════════
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
-- SECTION 6 — ADMIN & AUDIT
-- ═══════════════════════════════════════════════════════════════

-- ── 6a. ADMIN ACTIONS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_actions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id    TEXT        NOT NULL,
  action_type TEXT        NOT NULL
              CHECK (action_type IN (
                'approve_claim','reject_claim','flag_claim',
                'adjust_pool','override_fraud','kyc_verify',
                'manual_payout','other'
              )),
  target_type TEXT        NOT NULL,
  target_id   UUID        NOT NULL,
  reason      TEXT        DEFAULT NULL,
  metadata    JSONB       DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 6b. REGIONAL INTELLIGENCE SNAPSHOTS ──────────────────────
CREATE TABLE IF NOT EXISTS regional_intelligence_snapshots (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start      DATE    NOT NULL,
  city            TEXT    NOT NULL,
  risk_score      FLOAT   NOT NULL DEFAULT 0.5,
  rain_exposure   FLOAT   NOT NULL DEFAULT 0,
  aqi_stress      FLOAT   NOT NULL DEFAULT 0,
  platform_risk   FLOAT   NOT NULL DEFAULT 0,
  summary         TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (week_start, city)
);

-- ═══════════════════════════════════════════════════════════════
-- SECTION 7 — INDEXES
-- ═══════════════════════════════════════════════════════════════

-- users
CREATE INDEX IF NOT EXISTS idx_users_phone         ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_zone          ON users(zone);
CREATE INDEX IF NOT EXISTS idx_users_city          ON users(city);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_ref_code
  ON users(referral_code) WHERE referral_code IS NOT NULL;

-- policies
CREATE INDEX IF NOT EXISTS idx_policies_user_id    ON policies(user_id);
CREATE INDEX IF NOT EXISTS idx_policies_status     ON policies(status);
CREATE INDEX IF NOT EXISTS idx_policies_pool_id    ON policies(pool_id);
CREATE INDEX IF NOT EXISTS idx_policies_user_status ON policies(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_policies_one_active_per_user
  ON policies(user_id)
  WHERE status = 'active' OR status = 'renewed';

-- claims
CREATE INDEX IF NOT EXISTS idx_claims_user_id      ON claims(user_id);
CREATE INDEX IF NOT EXISTS idx_claims_status       ON claims(status);
CREATE INDEX IF NOT EXISTS idx_claims_created_at   ON claims(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_claims_zone_ts      ON claims(zone, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_claims_fraud_status ON claims(fraud_status);
CREATE INDEX IF NOT EXISTS idx_claims_policy_id    ON claims(policy_id);
CREATE INDEX IF NOT EXISTS idx_claims_user_status_created
  ON claims(user_id, status, created_at DESC);
-- GIN index for fps_signals JSONB queries
CREATE INDEX IF NOT EXISTS idx_claims_fps_signals
  ON claims USING gin(fps_signals jsonb_path_ops);

-- wallet
CREATE INDEX IF NOT EXISTS idx_wallet_user_id      ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_created_at   ON wallet_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_category     ON wallet_transactions(user_id, category);
CREATE INDEX IF NOT EXISTS idx_wallet_claim_id     ON wallet_transactions(claim_id);

-- disruptions
CREATE INDEX IF NOT EXISTS idx_disruptions_zone    ON disruption_events(zone);
CREATE INDEX IF NOT EXISTS idx_disruptions_ts      ON disruption_events(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_disruptions_city    ON disruption_events(city, started_at DESC);

-- shadow policies
CREATE INDEX IF NOT EXISTS idx_shadow_user_id      ON shadow_policies(user_id);
CREATE INDEX IF NOT EXISTS idx_shadow_week         ON shadow_policies(week_start);

-- notifications
CREATE INDEX IF NOT EXISTS idx_notif_user_id       ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notif_unread        ON notifications(user_id, read)
  WHERE read = FALSE;

-- notification delivery log
CREATE INDEX IF NOT EXISTS idx_notif_delivery_status_due
  ON notification_delivery_log(status, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_notif_delivery_user_created
  ON notification_delivery_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_delivery_notif
  ON notification_delivery_log(notification_id);

-- referrals
CREATE INDEX IF NOT EXISTS idx_ref_referrer        ON referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_ref_referred        ON referrals(referred_id);

-- appeal requests
CREATE INDEX IF NOT EXISTS idx_appeals_claim       ON appeal_requests(claim_id);
CREATE INDEX IF NOT EXISTS idx_appeals_user        ON appeal_requests(user_id);

-- admin actions
CREATE INDEX IF NOT EXISTS idx_admin_target        ON admin_actions(target_id);

-- fraud
CREATE INDEX IF NOT EXISTS idx_fraud_flags_worker  ON fraud_flags(worker_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_dfe_hash_ts
  ON device_fingerprint_events(fingerprint_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dfe_zone_ts
  ON device_fingerprint_events(zone, created_at DESC)
  WHERE zone IS NOT NULL;

-- telemetry
CREATE INDEX IF NOT EXISTS idx_telemetry_worker_ts
  ON shift_telemetry(worker_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_gaps_worker
  ON shift_gaps(worker_id, gap_start DESC);
CREATE INDEX IF NOT EXISTS idx_frs_adj_worker
  ON pending_frs_adjustments(worker_id)
  WHERE is_consumed = FALSE;

-- trust
CREATE INDEX IF NOT EXISTS idx_trust_events_user   ON trust_events(user_id);

-- pool health
CREATE INDEX IF NOT EXISTS idx_pool_health_city    ON pool_health(city, week_start DESC);

-- circuit breakers
CREATE INDEX IF NOT EXISTS idx_cb_zone_type        ON circuit_breakers(zone, trigger_type);

-- ═══════════════════════════════════════════════════════════════
-- SECTION 8 — ROW LEVEL SECURITY
-- For hackathon: allow_all. Replace with role-specific policies
-- before production.
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'users','auth_sessions','risk_pools','policies','claims','wallet_transactions',
    'disruption_events','shadow_policies','fraud_baselines',
    'weekly_settlements','notifications','notification_delivery_log','referrals',
    'reinsurance_triggers','admin_actions','appeal_requests',
    'circuit_breakers','pool_health','fraud_flags',
    'device_fingerprint_events','shift_telemetry','shift_gaps',
    'pending_frs_adjustments','trust_events',
    'regional_intelligence_snapshots'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "allow_all" ON %I', t);
    EXECUTE format(
      'CREATE POLICY "allow_all" ON %I FOR ALL USING (true)', t
    );
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 9 — FUNCTIONS & TRIGGERS
-- ═══════════════════════════════════════════════════════════════

-- ── 9a. updated_at — applied to ALL tables that have the column ──

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Apply to every table that has updated_at
DO $$
DECLARE
  t TEXT;
  tables_with_ts TEXT[] := ARRAY[
    'users','risk_pools','policies','claims','notification_delivery_log'
  ];
BEGIN
  FOREACH t IN ARRAY tables_with_ts LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_updated_at ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_updated_at
       BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION update_updated_at()', t);
  END LOOP;
END $$;

-- ── 9b. Auto-generate referral_code on user insert ────────────

CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.referral_code IS NULL THEN
    NEW.referral_code :=
      'HUSTLR-' || upper(substring(gen_random_uuid()::text, 1, 5));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_referral_code ON users;
CREATE TRIGGER trg_referral_code
  BEFORE INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION generate_referral_code();

-- ── 9c. Auto-create fraud_baseline on new user ────────────────

CREATE OR REPLACE FUNCTION create_fraud_baseline()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO fraud_baselines (
    user_id, typical_zones, avg_shift_start_hour, avg_shift_end_hour
  ) VALUES (
    NEW.id, ARRAY[NEW.zone], 8, 22
  ) ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fraud_baseline ON users;
CREATE TRIGGER trg_fraud_baseline
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION create_fraud_baseline();

-- ── 9d. Sync risk_pool on policy change ───────────────────────
-- Pool is identified by pool_id (not city lookup) to avoid
-- the per-row subquery and ambiguous city-only key problem.

CREATE OR REPLACE FUNCTION sync_risk_pool()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- New active policy added
  IF TG_OP = 'INSERT' AND NEW.pool_id IS NOT NULL THEN
    UPDATE risk_pools SET
      active_policies = active_policies + 1,
      total_premium   = total_premium   + NEW.weekly_premium,
      updated_at      = NOW()
    WHERE id = NEW.pool_id;
  END IF;

  -- Policy expired or cancelled
  IF TG_OP = 'UPDATE'
     AND NEW.status IN ('expired','cancelled')
     AND OLD.status = 'active'
     AND NEW.pool_id IS NOT NULL
  THEN
    UPDATE risk_pools SET
      active_policies = GREATEST(active_policies - 1, 0),
      updated_at      = NOW()
    WHERE id = NEW.pool_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_policy_pool_sync ON policies;
CREATE TRIGGER trg_policy_pool_sync
  AFTER INSERT OR UPDATE ON policies
  FOR EACH ROW EXECUTE FUNCTION sync_risk_pool();

-- ── 9e. Update pool claims_paid when claim is APPROVED ────────
-- Accounting rule:
--   • gross_payout is the committed liability — use this for BCR.
--   • Fires when status changes PENDING → APPROVED.
--   • tranche2_released_at is set separately by Sunday cron.
-- Do NOT trigger on SETTLED (tranche2 is already counted in gross).

CREATE OR REPLACE FUNCTION update_pool_on_claim_approved()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'APPROVED' AND OLD.status = 'PENDING'
     AND NEW.policy_id IS NOT NULL
  THEN
    -- Find the pool via the policy (not user → city lookup)
    UPDATE risk_pools rp SET
      total_claims_paid = total_claims_paid + NEW.gross_payout,
      loss_ratio = ROUND(
        CASE WHEN (total_premium + 0.0) > 0
          THEN (total_claims_paid + NEW.gross_payout)::NUMERIC
               / total_premium::NUMERIC
          ELSE 0
        END,
        4
      ),
      updated_at = NOW()
    FROM policies p
    WHERE p.id = NEW.policy_id
      AND rp.id = p.pool_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_claim_pool_update ON claims;
CREATE TRIGGER trg_claim_pool_update
  AFTER UPDATE ON claims
  FOR EACH ROW EXECUTE FUNCTION update_pool_on_claim_approved();

-- ── 9f. Auto-compute disruption duration ──────────────────────

CREATE OR REPLACE FUNCTION compute_disruption_duration()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ended_at IS NOT NULL AND OLD.ended_at IS NULL THEN
    NEW.duration_hrs :=
      EXTRACT(EPOCH FROM (NEW.ended_at - NEW.started_at)) / 3600.0;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_disruption_duration ON disruption_events;
CREATE TRIGGER trg_disruption_duration
  BEFORE UPDATE ON disruption_events
  FOR EACH ROW EXECUTE FUNCTION compute_disruption_duration();

-- ── 9g. Close shift gap when GPS resumes ──────────────────────

CREATE OR REPLACE FUNCTION close_open_gap(
  p_worker_id   UUID,
  p_resume_time TIMESTAMPTZ
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE shift_gaps SET
    gap_end              = p_resume_time,
    gap_duration_seconds = EXTRACT(EPOCH FROM (p_resume_time - gap_start))::INTEGER,
    frs_penalty          = CASE
      WHEN EXTRACT(EPOCH FROM (p_resume_time - gap_start))::INTEGER > 1800 THEN 20
      WHEN EXTRACT(EPOCH FROM (p_resume_time - gap_start))::INTEGER > 600  THEN 10
      ELSE 0
    END
  WHERE worker_id = p_worker_id
    AND gap_end IS NULL;
END;
$$;

-- ── 9h. Auto-pause stale shifts ───────────────────────────────
-- Call via pg_cron or Supabase Edge Function every 60 seconds.

CREATE OR REPLACE FUNCTION auto_pause_stale_shifts()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  stale RECORD;
BEGIN
  FOR stale IN
    SELECT DISTINCT ON (worker_id)
      worker_id,
      timestamp AS last_seen
    FROM shift_telemetry
    WHERE timestamp > NOW() - INTERVAL '10 minutes'
    ORDER BY worker_id, timestamp DESC
  LOOP
    IF (NOW() - stale.last_seen) > INTERVAL '120 seconds' THEN
      INSERT INTO shift_gaps (worker_id, gap_start)
      SELECT stale.worker_id, stale.last_seen
      WHERE NOT EXISTS (
        SELECT 1 FROM shift_gaps
        WHERE worker_id = stale.worker_id AND gap_end IS NULL
      );
    END IF;
  END LOOP;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 10 — POSTGIS HELPERS
-- ═══════════════════════════════════════════════════════════════

-- Zone depth scoring via PostGIS.
-- Returns distance_km and zone_depth_score as numeric fields
-- (not JSONB — cheaper for sorting and indexing).
-- Default hub = Chennai Adyar dark store centroid.

-- MUST DROP first because the previous version returned JSONB, and Postgres cannot 
-- "OR REPLACE" a function if the return type signature changes dramatically to TABLE.
DROP FUNCTION IF EXISTS hustlr_zone_depth(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION hustlr_zone_depth(
  worker_lat DOUBLE PRECISION,
  worker_lon DOUBLE PRECISION,
  hub_lat    DOUBLE PRECISION DEFAULT 13.0067,
  hub_lon    DOUBLE PRECISION DEFAULT 80.2206
) RETURNS TABLE (
  distance_km      NUMERIC,
  zone_depth_score NUMERIC,
  depth_multiplier NUMERIC,
  source           TEXT
) LANGUAGE sql STABLE AS $$
  WITH dist AS (
    SELECT ROUND(
      (ST_Distance(
        ST_SetSRID(ST_MakePoint(worker_lon, worker_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(hub_lon,    hub_lat),    4326)::geography
      ) / 1000.0)::NUMERIC,
      3
    ) AS d_km
  ),
  scored AS (
    SELECT
      d_km,
      CASE
        WHEN d_km <= 1.0 THEN 1.00
        WHEN d_km <= 2.0 THEN 0.85
        WHEN d_km <= 3.0 THEN 0.60
        WHEN d_km <= 4.0 THEN 0.30
        ELSE 0.00
      END::NUMERIC AS depth_score
    FROM dist
  )
  SELECT
    d_km,
    depth_score,
    -- multiplier mirrors Flutter LocationService.getDepthMultiplier()
    CASE
      WHEN depth_score >= 0.81 THEN 1.00
      WHEN depth_score >= 0.61 THEN 0.85
      WHEN depth_score >= 0.41 THEN 0.60
      WHEN depth_score >= 0.21 THEN 0.30
      ELSE 0.00
    END::NUMERIC,
    'postgis'
  FROM scored;
$$;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 11 — VERIFICATION QUERY
-- Run this after the script to confirm all tables exist.
-- ═══════════════════════════════════════════════════════════════

SELECT
  table_name,
  (
    SELECT COUNT(*)
    FROM information_schema.columns c
    WHERE c.table_name = t.table_name
      AND c.table_schema = 'public'
  ) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 12 — H3 GEOSPATIAL PRECISION MIGRATION
-- Consolidated from schema_h3.sql and Phase 4 additions.
-- ═══════════════════════════════════════════════════════════════

-- ── 12a. H3 columns on existing tables ────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS h3_location VARCHAR(16) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS h3_resolution INT DEFAULT 8;

ALTER TABLE claims
  ADD COLUMN IF NOT EXISTS h3_location VARCHAR(16) DEFAULT NULL;

ALTER TABLE disruption_events
  ADD COLUMN IF NOT EXISTS h3_center VARCHAR(16) DEFAULT NULL;

-- ── 12b. H3 zones reference table ─────────────────────────────
CREATE TABLE IF NOT EXISTS zones_h3 (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_id       TEXT UNIQUE NOT NULL,
  zone_name     TEXT NOT NULL,
  city          TEXT NOT NULL,
  h3_center     VARCHAR(16) NOT NULL,
  h3_resolution INT DEFAULT 8,
  h3_hexes      TEXT[] DEFAULT '{}',
  center_lat    FLOAT NOT NULL,
  center_lng    FLOAT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 12c. H3 indexes ───────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_h3_location
  ON users(h3_location);

CREATE INDEX IF NOT EXISTS idx_claims_h3_location
  ON claims(h3_location);

CREATE INDEX IF NOT EXISTS idx_disruptions_h3_center
  ON disruption_events(h3_center);

CREATE INDEX IF NOT EXISTS idx_zones_h3_center
  ON zones_h3(h3_center);

CREATE INDEX IF NOT EXISTS idx_zones_h3_city
  ON zones_h3(city);

-- ── 12d. Seed H3 zone centers (city-wise) ─────────────────────
INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('adyar', 'Adyar Dark Store Zone', 'Chennai', '8834e2a2a9fffff', 8, 13.0112, 80.2356),
  ('anna_nagar', 'Anna Nagar Dark Store Zone', 'Chennai', '8834e2a3c7fffff', 8, 13.0857, 80.2158),
  ('t_nagar', 'T Nagar Dark Store Zone', 'Chennai', '8834e2a2affffff', 8, 13.0417, 80.2353),
  ('velachery', 'Velachery Dark Store Zone', 'Chennai', '8834e2a287fffff', 8, 12.9817, 80.2182),
  ('korattur', 'Korattur Dark Store Zone', 'Chennai', '8834e2a4efffff', 8, 13.1379, 80.1850),
  ('tambaram', 'Tambaram Dark Store Zone', 'Chennai', '8834e2a197fffff', 8, 12.9249, 80.1502),
  ('porur', 'Porur Dark Store Zone', 'Chennai', '8834e2a2c7fffff', 8, 13.0347, 80.1625),
  ('chromepet', 'Chromepet Dark Store Zone', 'Chennai', '8834e2a1c7fffff', 8, 12.9504, 80.1399),
  ('sholinganallur', 'Sholinganallur Dark Store Zone', 'Chennai', '8834e2a267fffff', 8, 12.8944, 80.2235),
  ('guindy', 'Guindy Dark Store Zone', 'Chennai', '8834e2a2a7fffff', 8, 13.0107, 80.2128),
  ('perambur', 'Perambur Dark Store Zone', 'Chennai', '8834e2a5efffff', 8, 13.1167, 80.2333),
  ('royapettah', 'Royapettah Dark Store Zone', 'Chennai', '8834e2a2b7fffff', 8, 13.0567, 80.2708),
  ('mylapore', 'Mylapore Dark Store Zone', 'Chennai', '8834e2a2d7fffff', 8, 13.0333, 80.2667),
  ('triplicane', 'Triplicane Dark Store Zone', 'Chennai', '8834e2a2bfffff', 8, 13.0475, 80.2833),
  ('nungambakkam', 'Nungambakkam Dark Store Zone', 'Chennai', '8834e2a327fffff', 8, 13.0667, 80.2333)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('andheri', 'Andheri Dark Store Zone', 'Mumbai', '8834e6a2a7fffff', 8, 19.1196, 72.8466),
  ('bandra', 'Bandra Dark Store Zone', 'Mumbai', '8834e6a2c7fffff', 8, 19.0596, 72.8296),
  ('powai', 'Powai Dark Store Zone', 'Mumbai', '8834e6a327fffff', 8, 19.1196, 72.9086)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('koramangala', 'Koramangala Dark Store Zone', 'Bengaluru', '8834e12a2a7fffff', 8, 12.9352, 77.6245),
  ('electronic_city', 'Electronic City Dark Store Zone', 'Bengaluru', '8834e12a1c7fffff', 8, 12.8440, 77.6757),
  ('indiranagar', 'Indiranagar Dark Store Zone', 'Bengaluru', '8834e12a2c7fffff', 8, 12.9740, 77.6408)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('connaught_place', 'Connaught Place Dark Store Zone', 'Delhi', '8834e0a2a7fffff', 8, 28.6315, 77.2167),
  ('saket', 'Saket Dark Store Zone', 'Delhi', '8834e0a2a7fffff', 8, 28.5245, 77.2067),
  ('dwarka', 'Dwarka Dark Store Zone', 'Delhi', '8834e0a197fffff', 8, 28.5815, 77.0697)
ON CONFLICT (zone_id) DO NOTHING;

-- ── 12e. RLS for zones_h3 ─────────────────────────────────────
ALTER TABLE zones_h3 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON zones_h3;
CREATE POLICY "allow_all" ON zones_h3 FOR ALL USING (true);

-- NOTE:
-- Intentionally not creating trigger update_worker_h3_location() from legacy script
-- because it references NEW.latitude / NEW.longitude columns that are absent in users.
-- h3_location should be populated by backend application logic.

-- ═══════════════════════════════════════════════════════════════
-- SECTION 13 — SECURE AUTH POLICIES (OVERRIDES ALLOW_ALL)
-- Consolidated and deduped from secure_auth_policies.sql
-- ═══════════════════════════════════════════════════════════════

-- ── 13a. Remove baseline open policies where secure policies apply ────────────
DROP POLICY IF EXISTS "allow_all" ON users;
DROP POLICY IF EXISTS "allow_all" ON auth_sessions;
DROP POLICY IF EXISTS "allow_all" ON policies;
DROP POLICY IF EXISTS "allow_all" ON claims;
DROP POLICY IF EXISTS "allow_all" ON wallet_transactions;
DROP POLICY IF EXISTS "allow_all" ON disruption_events;

-- Remove previous secure policy definitions for idempotency
DROP POLICY IF EXISTS "users_read_own" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;
DROP POLICY IF EXISTS "users_insert_own" ON users;
DROP POLICY IF EXISTS "policies_read_own" ON policies;
DROP POLICY IF EXISTS "policies_update_own" ON policies;
DROP POLICY IF EXISTS "claims_read_own" ON claims;
DROP POLICY IF EXISTS "claims_update_own" ON claims;
DROP POLICY IF EXISTS "wallet_read_own" ON wallet_transactions;
DROP POLICY IF EXISTS "wallet_insert_own" ON wallet_transactions;
DROP POLICY IF EXISTS "disruptions_public" ON disruption_events;
DROP POLICY IF EXISTS "service_access_users" ON users;
DROP POLICY IF EXISTS "auth_sessions_service_access" ON auth_sessions;
DROP POLICY IF EXISTS "service_access_policies" ON policies;
DROP POLICY IF EXISTS "service_access_claims" ON claims;
DROP POLICY IF EXISTS "service_access_wallet" ON wallet_transactions;

-- ── 13b. User-owned access policies ───────────────────────────
CREATE POLICY "users_read_own" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_update_own" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "users_insert_own" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "policies_read_own" ON policies
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "policies_update_own" ON policies
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "claims_read_own" ON claims
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "claims_update_own" ON claims
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "wallet_read_own" ON wallet_transactions
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "wallet_insert_own" ON wallet_transactions
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "disruptions_public" ON disruption_events
  FOR SELECT USING (true);

-- ── 13c. Backend service role policies ────────────────────────
CREATE POLICY "service_access_users" ON users
  FOR ALL USING (
    auth.jwt() ->> 'role' = 'service_role'
    OR auth.uid() = id
  );
CREATE POLICY "auth_sessions_service_access" ON auth_sessions
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "service_access_policies" ON policies
  FOR ALL USING (
    auth.jwt() ->> 'role' = 'service_role'
    OR user_id = auth.uid()
  );

CREATE POLICY "service_access_claims" ON claims
  FOR ALL USING (
    auth.jwt() ->> 'role' = 'service_role'
    OR user_id = auth.uid()
  );

CREATE POLICY "service_access_wallet" ON wallet_transactions
  FOR ALL USING (
    auth.jwt() ->> 'role' = 'service_role'
    OR user_id = auth.uid()
  );

-- ── 13d. Tightened policies for non-core tables ───────────────
DROP POLICY IF EXISTS "allow_all" ON notifications;
DROP POLICY IF EXISTS "allow_all" ON referrals;
DROP POLICY IF EXISTS "allow_all" ON shift_telemetry;
DROP POLICY IF EXISTS "allow_all" ON fraud_flags;
DROP POLICY IF EXISTS "allow_all" ON admin_actions;
DROP POLICY IF EXISTS "allow_all" ON reinsurance_triggers;

DROP POLICY IF EXISTS "notifications_read_own" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON notifications;
DROP POLICY IF EXISTS "notifications_service_access" ON notifications;
DROP POLICY IF EXISTS "notif_delivery_read_own" ON notification_delivery_log;
DROP POLICY IF EXISTS "notif_delivery_service_access" ON notification_delivery_log;
DROP POLICY IF EXISTS "referrals_read_own" ON referrals;
DROP POLICY IF EXISTS "referrals_insert_own" ON referrals;
DROP POLICY IF EXISTS "referrals_service_access" ON referrals;
DROP POLICY IF EXISTS "shift_telemetry_insert_own" ON shift_telemetry;
DROP POLICY IF EXISTS "shift_telemetry_read_own" ON shift_telemetry;
DROP POLICY IF EXISTS "shift_telemetry_service_access" ON shift_telemetry;
DROP POLICY IF EXISTS "fraud_flags_read_own" ON fraud_flags;
DROP POLICY IF EXISTS "fraud_flags_service_access" ON fraud_flags;
DROP POLICY IF EXISTS "admin_actions_service_only" ON admin_actions;
DROP POLICY IF EXISTS "reinsurance_triggers_service_only" ON reinsurance_triggers;

CREATE POLICY "notifications_read_own" ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "notifications_insert_own" ON notifications
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "notifications_update_own" ON notifications
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "notifications_service_access" ON notifications
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "notif_delivery_read_own" ON notification_delivery_log
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "notif_delivery_service_access" ON notification_delivery_log
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "referrals_read_own" ON referrals
  FOR SELECT USING (referrer_id = auth.uid() OR referred_id = auth.uid());

CREATE POLICY "referrals_insert_own" ON referrals
  FOR INSERT WITH CHECK (referrer_id = auth.uid());

CREATE POLICY "referrals_service_access" ON referrals
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "shift_telemetry_insert_own" ON shift_telemetry
  FOR INSERT WITH CHECK (worker_id = auth.uid());

CREATE POLICY "shift_telemetry_read_own" ON shift_telemetry
  FOR SELECT USING (worker_id = auth.uid());

CREATE POLICY "shift_telemetry_service_access" ON shift_telemetry
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "fraud_flags_read_own" ON fraud_flags
  FOR SELECT USING (worker_id = auth.uid());

CREATE POLICY "fraud_flags_service_access" ON fraud_flags
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "admin_actions_service_only" ON admin_actions
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "reinsurance_triggers_service_only" ON reinsurance_triggers
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- ── 13e. Tightened policies for remaining tables ──────────────
DROP POLICY IF EXISTS "allow_all" ON risk_pools;
DROP POLICY IF EXISTS "allow_all" ON shadow_policies;
DROP POLICY IF EXISTS "allow_all" ON fraud_baselines;
DROP POLICY IF EXISTS "allow_all" ON weekly_settlements;
DROP POLICY IF EXISTS "allow_all" ON appeal_requests;
DROP POLICY IF EXISTS "allow_all" ON circuit_breakers;
DROP POLICY IF EXISTS "allow_all" ON pool_health;
DROP POLICY IF EXISTS "allow_all" ON device_fingerprint_events;
DROP POLICY IF EXISTS "allow_all" ON shift_gaps;
DROP POLICY IF EXISTS "allow_all" ON pending_frs_adjustments;
DROP POLICY IF EXISTS "allow_all" ON trust_events;
DROP POLICY IF EXISTS "allow_all" ON regional_intelligence_snapshots;
DROP POLICY IF EXISTS "allow_all" ON zones_h3;

DROP POLICY IF EXISTS "risk_pools_public_read" ON risk_pools;
DROP POLICY IF EXISTS "risk_pools_service_access" ON risk_pools;
DROP POLICY IF EXISTS "shadow_policies_read_own" ON shadow_policies;
DROP POLICY IF EXISTS "shadow_policies_insert_own" ON shadow_policies;
DROP POLICY IF EXISTS "shadow_policies_update_own" ON shadow_policies;
DROP POLICY IF EXISTS "shadow_policies_service_access" ON shadow_policies;
DROP POLICY IF EXISTS "fraud_baselines_read_own" ON fraud_baselines;
DROP POLICY IF EXISTS "fraud_baselines_service_access" ON fraud_baselines;
DROP POLICY IF EXISTS "weekly_settlements_public_read" ON weekly_settlements;
DROP POLICY IF EXISTS "weekly_settlements_service_access" ON weekly_settlements;
DROP POLICY IF EXISTS "appeal_requests_read_own" ON appeal_requests;
DROP POLICY IF EXISTS "appeal_requests_insert_own" ON appeal_requests;
DROP POLICY IF EXISTS "appeal_requests_update_own" ON appeal_requests;
DROP POLICY IF EXISTS "appeal_requests_service_access" ON appeal_requests;
DROP POLICY IF EXISTS "circuit_breakers_public_read" ON circuit_breakers;
DROP POLICY IF EXISTS "circuit_breakers_service_access" ON circuit_breakers;
DROP POLICY IF EXISTS "pool_health_public_read" ON pool_health;
DROP POLICY IF EXISTS "pool_health_service_access" ON pool_health;
DROP POLICY IF EXISTS "device_fingerprint_events_read_own" ON device_fingerprint_events;
DROP POLICY IF EXISTS "device_fingerprint_events_insert_own" ON device_fingerprint_events;
DROP POLICY IF EXISTS "device_fingerprint_events_service_access" ON device_fingerprint_events;
DROP POLICY IF EXISTS "shift_gaps_read_own" ON shift_gaps;
DROP POLICY IF EXISTS "shift_gaps_service_access" ON shift_gaps;
DROP POLICY IF EXISTS "pending_frs_adjustments_read_own" ON pending_frs_adjustments;
DROP POLICY IF EXISTS "pending_frs_adjustments_service_access" ON pending_frs_adjustments;
DROP POLICY IF EXISTS "trust_events_read_own" ON trust_events;
DROP POLICY IF EXISTS "trust_events_service_access" ON trust_events;
DROP POLICY IF EXISTS "regional_intel_public_read" ON regional_intelligence_snapshots;
DROP POLICY IF EXISTS "regional_intel_service_access" ON regional_intelligence_snapshots;
DROP POLICY IF EXISTS "zones_h3_public_read" ON zones_h3;
DROP POLICY IF EXISTS "zones_h3_service_access" ON zones_h3;

CREATE POLICY "risk_pools_public_read" ON risk_pools
  FOR SELECT USING (true);
CREATE POLICY "risk_pools_service_access" ON risk_pools
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "shadow_policies_read_own" ON shadow_policies
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "shadow_policies_insert_own" ON shadow_policies
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "shadow_policies_update_own" ON shadow_policies
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "shadow_policies_service_access" ON shadow_policies
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "fraud_baselines_read_own" ON fraud_baselines
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "fraud_baselines_service_access" ON fraud_baselines
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "weekly_settlements_public_read" ON weekly_settlements
  FOR SELECT USING (true);
CREATE POLICY "weekly_settlements_service_access" ON weekly_settlements
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "appeal_requests_read_own" ON appeal_requests
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "appeal_requests_insert_own" ON appeal_requests
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "appeal_requests_update_own" ON appeal_requests
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "appeal_requests_service_access" ON appeal_requests
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "circuit_breakers_public_read" ON circuit_breakers
  FOR SELECT USING (true);
CREATE POLICY "circuit_breakers_service_access" ON circuit_breakers
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "pool_health_public_read" ON pool_health
  FOR SELECT USING (true);
CREATE POLICY "pool_health_service_access" ON pool_health
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "device_fingerprint_events_read_own" ON device_fingerprint_events
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "device_fingerprint_events_insert_own" ON device_fingerprint_events
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "device_fingerprint_events_service_access" ON device_fingerprint_events
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "shift_gaps_read_own" ON shift_gaps
  FOR SELECT USING (worker_id = auth.uid());
CREATE POLICY "shift_gaps_service_access" ON shift_gaps
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "pending_frs_adjustments_read_own" ON pending_frs_adjustments
  FOR SELECT USING (worker_id = auth.uid());
CREATE POLICY "pending_frs_adjustments_service_access" ON pending_frs_adjustments
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "trust_events_read_own" ON trust_events
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "trust_events_service_access" ON trust_events
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "regional_intel_public_read" ON regional_intelligence_snapshots
  FOR SELECT USING (true);
CREATE POLICY "regional_intel_service_access" ON regional_intelligence_snapshots
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "zones_h3_public_read" ON zones_h3
  FOR SELECT USING (true);
CREATE POLICY "zones_h3_service_access" ON zones_h3
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- ═══════════════════════════════════════════════════════════════
-- SECTION 14 — SCHEMA VERSION METADATA
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS schema_meta (
  key            TEXT PRIMARY KEY,
  schema_version TEXT NOT NULL,
  applied_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes          TEXT DEFAULT NULL
);

ALTER TABLE schema_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON schema_meta;
DROP POLICY IF EXISTS "schema_meta_service_only" ON schema_meta;
CREATE POLICY "schema_meta_service_only" ON schema_meta
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

INSERT INTO schema_meta (key, schema_version, notes)
VALUES (
  'hustlr_schema',
  'schema_consolidated_1100plus_v2',
  'Consolidated schema with hardening: pgcrypto, wallet sign constraint, indexes, active-policy uniqueness, tightened RLS.'
)
ON CONFLICT (key) DO UPDATE
SET
  schema_version = EXCLUDED.schema_version,
  applied_at = NOW(),
  notes = EXCLUDED.notes;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 15 — EXTENDED VERIFICATION QUERIES
-- ═══════════════════════════════════════════════════════════════

-- Verify all public tables
SELECT
  table_name,
  (
    SELECT COUNT(*)
    FROM information_schema.columns c
    WHERE c.table_name = t.table_name
      AND c.table_schema = 'public'
  ) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Verify policies excluding broad allow_all
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname NOT LIKE '%allow_all%'
ORDER BY tablename, policyname;

-- Verify H3 zones
SELECT zone_id, zone_name, city, h3_center, h3_resolution
FROM zones_h3
ORDER BY city, zone_id;

-- Verify rows violating wallet sign/type constraint (clean these before VALIDATE CONSTRAINT)
SELECT id, user_id, type, amount, created_at
FROM wallet_transactions
WHERE amount < 0
ORDER BY created_at DESC;


-- ═══════════════════════════════════════════════════════════════
-- Run FIRST in Supabase SQL Editor
-- Patch notes:
--   • disruption_trigger_enum renamed to match Flutter's actual keys
--   • shift_telemetry data migrated to partitioned table
--   • wallet_balances upsert guard added
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. STRICT TYPING: DISRUPTION EVENTS ENUM ───────────────────
-- IMPORTANT: enum values MUST match the Flutter app's trigger_type strings.
-- Flutter sends: rain_heavy, rain_moderate, rain_light, heat_severe,
--   heat_stress, aqi_hazardous, aqi_very_unhealthy, platform_outage,
--   dark_store_closure, bandh_strike, internet_blackout.
-- New enum therefore preserves those names, not the alternate wordforms.

DO $$
BEGIN
  CREATE TYPE disruption_trigger_enum AS ENUM (
    'rain_heavy', 'rain_moderate', 'rain_light',
    'heat_severe', 'heat_stress',
    'aqi_hazardous', 'aqi_very_unhealthy',
    'platform_outage', 'dark_store_closure',
    'bandh_strike', 'internet_blackout',
    'traffic_congestion', 'cyclone_landfall'
  );
EXCEPTION
  WHEN duplicate_object THEN
    NULL;
END $$;

ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'rain_heavy';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'rain_moderate';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'rain_light';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'heat_severe';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'heat_stress';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'aqi_hazardous';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'aqi_very_unhealthy';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'platform_outage';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'dark_store_closure';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'bandh_strike';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'internet_blackout';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'traffic_congestion';
ALTER TYPE disruption_trigger_enum ADD VALUE IF NOT EXISTS 'cyclone_landfall';

-- Normalise any stale legacy values before casting
UPDATE disruption_events SET trigger_type = 'rain_heavy'        WHERE trigger_type::text = 'heavy_rain';
UPDATE disruption_events SET trigger_type = 'rain_heavy'        WHERE trigger_type::text = 'extreme_rain';
UPDATE disruption_events SET trigger_type = 'heat_severe'       WHERE trigger_type::text = 'heatwave';
UPDATE disruption_events SET trigger_type = 'aqi_hazardous'     WHERE trigger_type::text IN ('severe_aqi', 'severe_pollution');
UPDATE disruption_events SET trigger_type = 'internet_blackout' WHERE trigger_type = 'internet_blackout';
UPDATE disruption_events SET trigger_type = 'bandh_strike'      WHERE trigger_type = 'bandh_strike';

ALTER TABLE disruption_events
  ALTER COLUMN trigger_type TYPE disruption_trigger_enum
  USING trigger_type::disruption_trigger_enum;


-- ── 2. FINANCIAL SAFETY: IDEMPOTENCY & HARD BALANCE LOCKING ────

-- A. Idempotency keys (prevents double billing / double payouts on retries)
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE;
ALTER TABLE claims              ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE;

-- B. Hard balance ledger table
CREATE TABLE IF NOT EXISTS wallet_balances (
  user_id      UUID    PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  balance      INTEGER NOT NULL DEFAULT 0,
  last_updated TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_positive_balance CHECK (balance >= 0)
);

-- Seed existing users with 0 balance (real balance is in wallet_transactions)
INSERT INTO wallet_balances (user_id, balance)
SELECT id, 0 FROM users
ON CONFLICT DO NOTHING;

-- C. Row-level lock trigger — uses UPSERT guard so new users never error
CREATE OR REPLACE FUNCTION process_wallet_transaction()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Ensure row exists before locking (handles brand-new users)
  INSERT INTO wallet_balances (user_id, balance)
  VALUES (NEW.user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Atomic row-level lock — prevents race conditions
  PERFORM * FROM wallet_balances WHERE user_id = NEW.user_id FOR UPDATE;

  IF NEW.type = 'credit' THEN
    UPDATE wallet_balances
      SET balance = balance + NEW.amount, last_updated = NOW()
      WHERE user_id = NEW.user_id;
  ELSE
    -- chk_positive_balance will reject if result < 0
    UPDATE wallet_balances
      SET balance = balance - NEW.amount, last_updated = NOW()
      WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wallet_transaction_lock ON wallet_transactions;
CREATE TRIGGER trg_wallet_transaction_lock
  BEFORE INSERT ON wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION process_wallet_transaction();


-- ── 3. AUDITABILITY: POLICY VERSIONING ─────────────────────────

CREATE TABLE IF NOT EXISTS policy_versions (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id         UUID        NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  plan_tier         TEXT        NOT NULL,   -- TEXT to survive enum migrations
  weekly_premium    INTEGER     NOT NULL,
  max_weekly_payout INTEGER     NOT NULL,
  zone_adjustment   INTEGER     NOT NULL,
  iss_adjustment    INTEGER     NOT NULL,
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_to          TIMESTAMPTZ,
  changed_by        TEXT        DEFAULT 'system'
);

CREATE INDEX IF NOT EXISTS idx_policy_versions_lookup
  ON policy_versions(policy_id, valid_to);

CREATE OR REPLACE FUNCTION log_policy_version()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Close the previous open version snapshot
  UPDATE policy_versions
    SET valid_to = NOW()
    WHERE policy_id = NEW.id AND valid_to IS NULL;

  -- Record the new state
  INSERT INTO policy_versions (
    policy_id, plan_tier, weekly_premium, max_weekly_payout,
    zone_adjustment, iss_adjustment, valid_from
  ) VALUES (
    NEW.id, NEW.plan_tier::TEXT, NEW.weekly_premium, NEW.max_weekly_payout,
    NEW.zone_adjustment, NEW.iss_adjustment, NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_policy_version ON policies;
CREATE TRIGGER trg_log_policy_version
  AFTER INSERT OR UPDATE OF plan_tier, weekly_premium, zone_adjustment, iss_adjustment
  ON policies FOR EACH ROW EXECUTE FUNCTION log_policy_version();


-- ── 4. IRDAI COMPLIANCE: IMMUTABLE SHA-256 HASH CHAIN ──────────

ALTER TABLE claims
  ADD COLUMN IF NOT EXISTS previous_hash TEXT,
  ADD COLUMN IF NOT EXISTS record_hash   TEXT;

CREATE OR REPLACE FUNCTION generate_claim_hash()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  payload   TEXT;
BEGIN
  NEW.previous_hash := COALESCE(
    (SELECT c.record_hash FROM claims c ORDER BY c.created_at DESC LIMIT 1),
    'GENESIS_BLOCK'
  );
  
  -- ARMOR: Coalesce every field to empty string to prevent NULL propagation
  payload := COALESCE(NEW.id::TEXT, '') || COALESCE(NEW.user_id::TEXT, '')
          || COALESCE(NEW.gross_payout::TEXT, '') || COALESCE(NEW.status::TEXT, '')
          || NEW.previous_hash;

  NEW.record_hash := encode(digest(payload, 'sha256'), 'hex');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generate_claim_hash ON claims;
CREATE TRIGGER trg_generate_claim_hash
  BEFORE INSERT ON claims
  FOR EACH ROW EXECUTE FUNCTION generate_claim_hash();


-- ── 5. SCALABILITY: DECLARATIVE PARTITIONING ───────────────────
-- Renames the old monolithic table, rebuilds it as a partitioned parent,
-- migrates all existing data, then creates rolling month partitions.

-- A. Shift Telemetry
DO $$
BEGIN
  IF to_regclass('public.shift_telemetry') IS NOT NULL
     AND to_regclass('public.shift_telemetry_old') IS NULL THEN
    EXECUTE 'ALTER TABLE shift_telemetry RENAME TO shift_telemetry_old';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS shift_telemetry (
  id                UUID        DEFAULT gen_random_uuid(),
  worker_id         UUID        NOT NULL,
  lat               FLOAT8      NOT NULL,
  lng               FLOAT8      NOT NULL,
  accuracy          FLOAT4,
  timestamp         TIMESTAMPTZ NOT NULL,
  is_mock_location  BOOLEAN     DEFAULT FALSE,
  activity_type     TEXT,
  battery_level     FLOAT4,
  signal_strength   INTEGER,
  is_low_confidence BOOLEAN     DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE IF NOT EXISTS shift_telemetry_y2026m04 PARTITION OF shift_telemetry
  FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS shift_telemetry_y2026m05 PARTITION OF shift_telemetry
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- ARMOR: Catch-all bucket for future dates so GPS tracking never crashes
CREATE TABLE IF NOT EXISTS shift_telemetry_default PARTITION OF shift_telemetry DEFAULT;

-- Migrate existing rows (runs only once; old table kept as backup)
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'shift_telemetry_old') THEN
    INSERT INTO shift_telemetry
      SELECT * FROM shift_telemetry_old
      ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- B. Fraud Signal Logs
DO $$
BEGIN
  IF to_regclass('public.fraud_signal_logs') IS NOT NULL
     AND to_regclass('public.fraud_signal_logs_old') IS NULL THEN
    EXECUTE 'ALTER TABLE fraud_signal_logs RENAME TO fraud_signal_logs_old';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS fraud_signal_logs (
  id                UUID        DEFAULT gen_random_uuid(),
  claim_id          UUID        NOT NULL,
  signal_name       TEXT        NOT NULL,
  signal_value      FLOAT       NOT NULL,
  weight_applied    FLOAT       NOT NULL,
  score_contribution INTEGER    NOT NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE IF NOT EXISTS fraud_signal_logs_y2026m04 PARTITION OF fraud_signal_logs
  FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS fraud_signal_logs_y2026m05 PARTITION OF fraud_signal_logs
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- ARMOR: Catch-all bucket for unpartitioned future dates
CREATE TABLE IF NOT EXISTS fraud_signal_logs_default PARTITION OF fraud_signal_logs DEFAULT;

DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'fraud_signal_logs_old') THEN
    INSERT INTO fraud_signal_logs
      SELECT * FROM fraud_signal_logs_old
      ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Re-hardening after partition-table recreation.
ALTER TABLE shift_telemetry ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "shift_telemetry_insert_own" ON shift_telemetry;
DROP POLICY IF EXISTS "shift_telemetry_read_own" ON shift_telemetry;
DROP POLICY IF EXISTS "shift_telemetry_service_access" ON shift_telemetry;
CREATE POLICY "shift_telemetry_insert_own" ON shift_telemetry
  FOR INSERT WITH CHECK (worker_id = auth.uid());
CREATE POLICY "shift_telemetry_read_own" ON shift_telemetry
  FOR SELECT USING (worker_id = auth.uid());
CREATE POLICY "shift_telemetry_service_access" ON shift_telemetry
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

ALTER TABLE fraud_signal_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fraud_signal_logs_service_only" ON fraud_signal_logs;
CREATE POLICY "fraud_signal_logs_service_only" ON fraud_signal_logs
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');


-- ── 6. WORK VERIFICATION LAYER ─────────────────────────────────

CREATE TABLE IF NOT EXISTS work_sessions (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id                UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform_shift_id        TEXT,
  started_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at                 TIMESTAMPTZ,
  total_deliveries         INTEGER     DEFAULT 0,
  zone_coverage_percentage FLOAT       DEFAULT 1.0,
  is_verified              BOOLEAN     DEFAULT FALSE,
  created_at               TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_sessions_lookup
  ON work_sessions(worker_id, started_at DESC);


-- ── 7. DATA TRUST SCORING FOR PARAMETRIC TRIGGERS ──────────────

ALTER TABLE disruption_events
  ADD COLUMN IF NOT EXISTS data_trust_score FLOAT
    CHECK (data_trust_score BETWEEN 0 AND 1),
  ADD COLUMN IF NOT EXISTS source_weight FLOAT DEFAULT 1.0;

-- Hard minimum trust before payout can be triggered
ALTER TABLE disruption_events
  DROP CONSTRAINT IF EXISTS chk_minimum_trust;
ALTER TABLE disruption_events
  ADD CONSTRAINT chk_minimum_trust
    CHECK (payout_triggered = FALSE OR data_trust_score >= 0.75);


-- ── 8. RLS ─────────────────────────────────────────────────────
DO $$
DECLARE t TEXT;
DECLARE new_tables TEXT[] := ARRAY[
  'wallet_balances','policy_versions','work_sessions'
];
BEGIN
  FOREACH t IN ARRAY new_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "allow_all" ON %I', t);
    EXECUTE format('CREATE POLICY "allow_all" ON %I FOR ALL USING (true)', t);
  END LOOP;
END $$;

COMMIT;


-- ═══════════════════════════════════════════════════════════════
-- HUSTLR — FINAL CRITICAL REMEDIATION PATCH (PATCHED)
-- Runs within this consolidated script.
-- Patches applied:
--   • UNIQUE INDEX partial predicate uses OR not IN (Postgres requirement)
--   • wallet trigger redefined with credit/debit logic
--   • policy_versions plan_tier stored as TEXT to survive enum migrations
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. REMOVE PHANTOM 'ELITE' TIER ─────────────────────────────
-- Demote plan_tier to TEXT, swap enum, re-cast safely.

DROP TRIGGER IF EXISTS trg_log_policy_version ON policies;
ALTER TABLE policies      ALTER COLUMN plan_tier TYPE TEXT;
-- policy_versions already uses TEXT (created earlier in this script)

ALTER TABLE policies ALTER COLUMN plan_tier DROP DEFAULT;

-- Defensive cleanup for reruns: remove any legacy CHECK constraints
-- on plan_tier that may compare enum to text.
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.policies'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%plan_tier%'
  LOOP
    EXECUTE format('ALTER TABLE policies DROP CONSTRAINT IF EXISTS %I', c.conname);
  END LOOP;
END $$;

DROP TYPE IF EXISTS policy_tier_enum;
CREATE TYPE policy_tier_enum AS ENUM ('basic', 'standard', 'full');

ALTER TABLE policies DROP CONSTRAINT IF EXISTS policies_plan_tier_check;

ALTER TABLE policies
  ALTER COLUMN plan_tier TYPE policy_tier_enum
  USING plan_tier::text::policy_tier_enum;

ALTER TABLE policies ALTER COLUMN plan_tier SET DEFAULT 'standard'::policy_tier_enum;

CREATE TRIGGER trg_log_policy_version
  AFTER INSERT OR UPDATE OF plan_tier, weekly_premium, zone_adjustment, iss_adjustment
  ON policies FOR EACH ROW EXECUTE FUNCTION log_policy_version();


-- ── 2. PREMIUM SAFETY CONSTRAINTS ──────────────────────────────
-- Fix any legacy ₹60 premiums (should be ₹49 standard)
UPDATE policies
  SET weekly_premium = 49, base_premium = 49
  WHERE plan_tier = 'standard'::policy_tier_enum AND weekly_premium = 60;

-- Fix legacy ₹29 premiums (should be ₹35 basic)
UPDATE policies
  SET weekly_premium = 35, base_premium = 35
  WHERE plan_tier = 'basic'::policy_tier_enum AND weekly_premium = 29;

ALTER TABLE policies DROP CONSTRAINT IF EXISTS chk_valid_premium;
ALTER TABLE policies ADD CONSTRAINT chk_valid_premium CHECK (
  (plan_tier = 'basic'::policy_tier_enum    AND weekly_premium BETWEEN 30 AND 40)  OR
  (plan_tier = 'standard'::policy_tier_enum AND weekly_premium BETWEEN 45 AND 55)  OR
  (plan_tier = 'full'::policy_tier_enum     AND weekly_premium BETWEEN 70 AND 85)
);


-- ── 3. FIX WALLET SIGN CONVENTION ──────────────────────────────
-- Flutter app sends positive amounts for both credits and debits.
-- Direction determined by the 'type' column, NOT by sign.

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_amount_sign_matches_type;

-- Convert any legacy negative values to absolute
UPDATE wallet_transactions SET amount = ABS(amount) WHERE amount < 0;

-- Enforce strictly non-negative amounts from here on
ALTER TABLE wallet_transactions
  ADD CONSTRAINT chk_wallet_amount_positive CHECK (amount >= 0);

-- Redefine trigger to use type-aware math (idempotent redefine)
CREATE OR REPLACE FUNCTION process_wallet_transaction()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO wallet_balances (user_id, balance)
  VALUES (NEW.user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM * FROM wallet_balances WHERE user_id = NEW.user_id FOR UPDATE;

  IF NEW.type = 'credit' THEN
    UPDATE wallet_balances
      SET balance = balance + NEW.amount, last_updated = NOW()
      WHERE user_id = NEW.user_id;
  ELSE
    -- chk_positive_balance rejects overdrafts atomically
    UPDATE wallet_balances
      SET balance = balance - NEW.amount, last_updated = NOW()
      WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;


-- ── 4. PAYOUT REQUESTS TABLE ────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE payout_status_enum AS ENUM ('pending', 'processing', 'completed', 'failed');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS payout_requests (
  id             UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID               NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount         INTEGER            NOT NULL CHECK (amount > 0),
  method         TEXT               NOT NULL CHECK (method IN ('upi', 'bank_direct')),
  upi_id         TEXT               DEFAULT NULL,
  bank_account   TEXT               DEFAULT NULL,
  ifsc_code      TEXT               DEFAULT NULL,
  status         payout_status_enum NOT NULL DEFAULT 'pending',
  reference_id   TEXT               DEFAULT NULL,
  error_message  TEXT               DEFAULT NULL,
  attempts       INTEGER            NOT NULL DEFAULT 0,
  initiated_at   TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  completed_at   TIMESTAMPTZ        DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_payout_requests_user
  ON payout_requests(user_id, initiated_at DESC);

-- RLS
ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON payout_requests;
CREATE POLICY "allow_all" ON payout_requests FOR ALL USING (true);


-- ── 5. FIX ACTIVE POLICY RENEWAL BLOCKER ───────────────────────
-- CRITICAL: PostgreSQL does NOT support IN() in partial index predicates.
-- Must use explicit OR conditions.

DROP INDEX IF EXISTS idx_policies_one_active_per_user;
CREATE UNIQUE INDEX idx_policies_one_active_per_user ON policies(user_id)
  WHERE status = 'active' OR status = 'renewed';


-- ── 6. FIX VACUOUS SESSION TIMEOUT CONSTRAINT ──────────────────
ALTER TABLE auth_sessions DROP CONSTRAINT IF EXISTS chk_session_timeout;

-- Replace with an index for efficient cleanup queries
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expiry
  ON auth_sessions(last_seen_at)
  WHERE is_active = TRUE;


-- ── 7. KATTANKULATHUR H3 ZONE + POSTGIS WRAPPER ────────────────
INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES (
  'kattankulathur',
  'Kattankulathur Dark Store Zone',
  'Chennai',
  '8834e2a117fffff',
  8,
  12.8185,
  80.0419   -- SRM University / Potheri corridor
)
ON CONFLICT (zone_id) DO NOTHING;

-- Dynamic hub centroid lookup by zone_id
CREATE OR REPLACE FUNCTION hustlr_zone_depth_by_name(
  worker_lat DOUBLE PRECISION,
  worker_lon DOUBLE PRECISION,
  zone_id_in TEXT
) RETURNS TABLE (
  distance_km       NUMERIC,
  zone_depth_score  NUMERIC,
  depth_multiplier  NUMERIC,
  source            TEXT
) LANGUAGE sql STABLE AS $$
  SELECT * FROM hustlr_zone_depth(
    worker_lat,
    worker_lon,
    (SELECT center_lat FROM zones_h3 WHERE zone_id = zone_id_in LIMIT 1),
    (SELECT center_lng FROM zones_h3 WHERE zone_id = zone_id_in LIMIT 1)
  );
$$;


-- ── 8. STRUCTURAL INTEGRITY FIXES ──────────────────────────────

-- Link pool_health directly to risk_pools
ALTER TABLE pool_health
  ADD COLUMN IF NOT EXISTS pool_id UUID REFERENCES risk_pools(id) ON DELETE CASCADE;

-- Remove silent global default on claims.city
ALTER TABLE claims ALTER COLUMN city DROP DEFAULT;

-- Fast inbox query index
CREATE INDEX IF NOT EXISTS idx_notif_inbox
  ON notifications(user_id, read, created_at DESC)
  WHERE read = FALSE;

-- Fast disruption recency index (was missing from original schema)
CREATE INDEX IF NOT EXISTS idx_disruptions_started_at
  ON disruption_events(started_at DESC);


COMMIT;

