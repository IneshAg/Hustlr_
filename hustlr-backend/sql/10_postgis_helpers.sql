-- SECTION 10 — POSTGIS HELPERS
-- ═══════════════════════════════════════════════════════════════

-- Zone depth scoring via PostGIS.
-- Returns distance_km and zone_depth_score as numeric fields
-- (not JSONB — cheaper for sorting and indexing).
-- Default hub = Chennai Adyar dark store centroid.

-- MUST DROP first because the previous version returned JSONB, and Postgres cannot 
-- "OR REPLACE" a function if the return type signature changes dramatically to TABLE.
DROP FUNCTION IF EXISTS hustlr_zone_depth(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION hustlr_zone_depth(
  worker_lat DOUBLE PRECISION,
  worker_lon DOUBLE PRECISION,
  hub_lat    DOUBLE PRECISION DEFAULT 13.0067,
  hub_lon    DOUBLE PRECISION DEFAULT 80.2206
) RETURNS TABLE (
  distance_km      NUMERIC,
  zone_depth_score NUMERIC,
  depth_multiplier NUMERIC,
  source           TEXT
) LANGUAGE sql STABLE AS $$
  WITH dist AS (
    SELECT ROUND(
      (ST_Distance(
        ST_SetSRID(ST_MakePoint(worker_lon, worker_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(hub_lon,    hub_lat),    4326)::geography
      ) / 1000.0)::NUMERIC,
      3
    ) AS d_km
  ),
  scored AS (
    SELECT
      d_km,
      CASE
        WHEN d_km <= 1.0 THEN 1.00
        WHEN d_km <= 2.0 THEN 0.85
        WHEN d_km <= 3.0 THEN 0.60
        WHEN d_km <= 4.0 THEN 0.30
        ELSE 0.00
      END::NUMERIC AS depth_score
    FROM dist
  )
  SELECT
    d_km,
    depth_score,
    -- multiplier mirrors Flutter LocationService.getDepthMultiplier()
    CASE
      WHEN depth_score >= 0.81 THEN 1.00
      WHEN depth_score >= 0.61 THEN 0.85
      WHEN depth_score >= 0.41 THEN 0.60
      WHEN depth_score >= 0.21 THEN 0.30
      ELSE 0.00
    END::NUMERIC,
    'postgis'
  FROM scored;
$$;
