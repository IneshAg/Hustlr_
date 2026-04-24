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
