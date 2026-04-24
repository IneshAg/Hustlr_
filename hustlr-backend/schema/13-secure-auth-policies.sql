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
