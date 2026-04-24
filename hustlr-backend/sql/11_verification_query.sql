-- SECTION 11 — VERIFICATION QUERY
-- Run this after the script to confirm all tables exist.
-- ═══════════════════════════════════════════════════════════════

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
