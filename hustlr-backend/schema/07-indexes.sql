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
