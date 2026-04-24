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

