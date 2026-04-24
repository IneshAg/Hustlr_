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
