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
