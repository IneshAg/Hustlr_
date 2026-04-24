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
