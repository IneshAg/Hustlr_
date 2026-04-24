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
