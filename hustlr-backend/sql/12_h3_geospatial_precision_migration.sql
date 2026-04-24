-- SECTION 12 — H3 GEOSPATIAL PRECISION MIGRATION
-- Consolidated from schema_h3.sql and Phase 4 additions.
-- ═══════════════════════════════════════════════════════════════

-- ── 12a. H3 columns on existing tables ────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS h3_location VARCHAR(16) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS h3_resolution INT DEFAULT 8;

ALTER TABLE claims
  ADD COLUMN IF NOT EXISTS h3_location VARCHAR(16) DEFAULT NULL;

ALTER TABLE disruption_events
  ADD COLUMN IF NOT EXISTS h3_center VARCHAR(16) DEFAULT NULL;

-- ── 12b. H3 zones reference table ─────────────────────────────
CREATE TABLE IF NOT EXISTS zones_h3 (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_id       TEXT UNIQUE NOT NULL,
  zone_name     TEXT NOT NULL,
  city          TEXT NOT NULL,
  h3_center     VARCHAR(16) NOT NULL,
  h3_resolution INT DEFAULT 8,
  h3_hexes      TEXT[] DEFAULT '{}',
  center_lat    FLOAT NOT NULL,
  center_lng    FLOAT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 12c. H3 indexes ───────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_h3_location
  ON users(h3_location);

CREATE INDEX IF NOT EXISTS idx_claims_h3_location
  ON claims(h3_location);

CREATE INDEX IF NOT EXISTS idx_disruptions_h3_center
  ON disruption_events(h3_center);

CREATE INDEX IF NOT EXISTS idx_zones_h3_center
  ON zones_h3(h3_center);

CREATE INDEX IF NOT EXISTS idx_zones_h3_city
  ON zones_h3(city);

-- ── 12d. Seed H3 zone centers (city-wise) ─────────────────────
INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('adyar', 'Adyar Dark Store Zone', 'Chennai', '8834e2a2a9fffff', 8, 13.0112, 80.2356),
  ('anna_nagar', 'Anna Nagar Dark Store Zone', 'Chennai', '8834e2a3c7fffff', 8, 13.0857, 80.2158),
  ('t_nagar', 'T Nagar Dark Store Zone', 'Chennai', '8834e2a2affffff', 8, 13.0417, 80.2353),
  ('velachery', 'Velachery Dark Store Zone', 'Chennai', '8834e2a287fffff', 8, 12.9817, 80.2182),
  ('korattur', 'Korattur Dark Store Zone', 'Chennai', '8834e2a4efffff', 8, 13.1379, 80.1850),
  ('tambaram', 'Tambaram Dark Store Zone', 'Chennai', '8834e2a197fffff', 8, 12.9249, 80.1502),
  ('porur', 'Porur Dark Store Zone', 'Chennai', '8834e2a2c7fffff', 8, 13.0347, 80.1625),
  ('chromepet', 'Chromepet Dark Store Zone', 'Chennai', '8834e2a1c7fffff', 8, 12.9504, 80.1399),
  ('sholinganallur', 'Sholinganallur Dark Store Zone', 'Chennai', '8834e2a267fffff', 8, 12.8944, 80.2235),
  ('guindy', 'Guindy Dark Store Zone', 'Chennai', '8834e2a2a7fffff', 8, 13.0107, 80.2128),
  ('perambur', 'Perambur Dark Store Zone', 'Chennai', '8834e2a5efffff', 8, 13.1167, 80.2333),
  ('royapettah', 'Royapettah Dark Store Zone', 'Chennai', '8834e2a2b7fffff', 8, 13.0567, 80.2708),
  ('mylapore', 'Mylapore Dark Store Zone', 'Chennai', '8834e2a2d7fffff', 8, 13.0333, 80.2667),
  ('triplicane', 'Triplicane Dark Store Zone', 'Chennai', '8834e2a2bfffff', 8, 13.0475, 80.2833),
  ('nungambakkam', 'Nungambakkam Dark Store Zone', 'Chennai', '8834e2a327fffff', 8, 13.0667, 80.2333)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('andheri', 'Andheri Dark Store Zone', 'Mumbai', '8834e6a2a7fffff', 8, 19.1196, 72.8466),
  ('bandra', 'Bandra Dark Store Zone', 'Mumbai', '8834e6a2c7fffff', 8, 19.0596, 72.8296),
  ('powai', 'Powai Dark Store Zone', 'Mumbai', '8834e6a327fffff', 8, 19.1196, 72.9086)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('koramangala', 'Koramangala Dark Store Zone', 'Bengaluru', '8834e12a2a7fffff', 8, 12.9352, 77.6245),
  ('electronic_city', 'Electronic City Dark Store Zone', 'Bengaluru', '8834e12a1c7fffff', 8, 12.8440, 77.6757),
  ('indiranagar', 'Indiranagar Dark Store Zone', 'Bengaluru', '8834e12a2c7fffff', 8, 12.9740, 77.6408)
ON CONFLICT (zone_id) DO NOTHING;

INSERT INTO zones_h3 (zone_id, zone_name, city, h3_center, h3_resolution, center_lat, center_lng)
VALUES
  ('connaught_place', 'Connaught Place Dark Store Zone', 'Delhi', '8834e0a2a7fffff', 8, 28.6315, 77.2167),
  ('saket', 'Saket Dark Store Zone', 'Delhi', '8834e0a2a7fffff', 8, 28.5245, 77.2067),
  ('dwarka', 'Dwarka Dark Store Zone', 'Delhi', '8834e0a197fffff', 8, 28.5815, 77.0697)
ON CONFLICT (zone_id) DO NOTHING;

-- ── 12e. RLS for zones_h3 ─────────────────────────────────────
ALTER TABLE zones_h3 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON zones_h3;
CREATE POLICY "allow_all" ON zones_h3 FOR ALL USING (true);

-- NOTE:
-- Intentionally not creating trigger update_worker_h3_location() from legacy script
-- because it references NEW.latitude / NEW.longitude columns that are absent in users.
-- h3_location should be populated by backend application logic.
