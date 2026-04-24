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
