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
