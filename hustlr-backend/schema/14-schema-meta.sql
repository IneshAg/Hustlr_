-- SECTION 14 — SCHEMA VERSION METADATA
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS schema_meta (
  key            TEXT PRIMARY KEY,
  schema_version TEXT NOT NULL,
  applied_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes          TEXT DEFAULT NULL
);

ALTER TABLE schema_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON schema_meta;
DROP POLICY IF EXISTS "schema_meta_service_only" ON schema_meta;
CREATE POLICY "schema_meta_service_only" ON schema_meta
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')
  WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

INSERT INTO schema_meta (key, schema_version, notes)
VALUES (
  'hustlr_schema',
  'schema_consolidated_1100plus_v2',
  'Consolidated schema with hardening: pgcrypto, wallet sign constraint, indexes, active-policy uniqueness, tightened RLS.'
)
ON CONFLICT (key) DO UPDATE
SET
  schema_version = EXCLUDED.schema_version,
  applied_at = NOW(),
  notes = EXCLUDED.notes;

-- ═══════════════════════════════════════════════════════════════
