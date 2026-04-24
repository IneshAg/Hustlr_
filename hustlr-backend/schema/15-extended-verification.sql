-- SECTION 15 — EXTENDED VERIFICATION QUERIES
-- ═══════════════════════════════════════════════════════════════

-- Verify all public tables
SELECT
  table_name,
  (
    SELECT COUNT(*)
    FROM information_schema.columns c
    WHERE c.table_name = t.table_name
      AND c.table_schema = 'public'
  ) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Verify policies excluding broad allow_all
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname NOT LIKE '%allow_all%'
ORDER BY tablename, policyname;

-- Verify H3 zones
SELECT zone_id, zone_name, city, h3_center, h3_resolution
FROM zones_h3
ORDER BY city, zone_id;

-- Verify rows violating wallet sign/type constraint (clean these before VALIDATE CONSTRAINT)
SELECT id, user_id, type, amount, created_at
FROM wallet_transactions
WHERE amount < 0
ORDER BY created_at DESC;


-- ═══════════════════════════════════════════════════════════════
-- Run FIRST in Supabase SQL Editor
-- Patch notes:
--   • disruption_trigger_enum renamed to match Flutter's actual keys
--   • shift_telemetry data migrated to partitioned table
--   • wallet_balances upsert guard added
-- ═══════════════════════════════════════════════════════════════

BEGIN;

