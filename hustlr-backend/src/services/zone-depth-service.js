/**
 * Zone depth vs dark-store hub: distance rings → underwriting-style score [0.35, 1.0].
 * Optional PostGIS path: set USE_POSTGIS_ZONE_DEPTH=true and run supabase/hustlr_consolidated_schema.sql (RPC hustlr_zone_depth).
 * H3 Geospatial Precision: set USE_H3_ZONE_DEPTH=true to use Uber's H3 hexagonal grid.
 */

const { supabase } = require("../config/supabase");
const h3Service = require("./h3-service");

const EARTH_KM = 6371;

function toRad(d) {
  return (d * Math.PI) / 180;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_KM * c;
}

function scoreFromDistanceKm(km) {
  if (km <= 2) return 1.0;
  if (km <= 5) return 0.85;
  if (km <= 10) return 0.65;
  const decay = 0.02 * (km - 10);
  return Math.max(0.35, 0.65 - decay);
}

function computeZoneDepth(lat, lon) {
  let hubLat = parseFloat(process.env.DARK_STORE_LAT || "12.982");
  let hubLon = parseFloat(process.env.DARK_STORE_LON || "80.243");
  if (!Number.isFinite(hubLat)) hubLat = 12.982;
  if (!Number.isFinite(hubLon)) hubLon = 80.243;
  const distance_km = haversineKm(lat, lon, hubLat, hubLon);
  const zone_depth_score = scoreFromDistanceKm(distance_km);
  return {
    distance_km: Math.round(distance_km * 1000) / 1000,
    zone_depth_score: Math.round(zone_depth_score * 1000) / 1000,
    hub: { lat: hubLat, lon: hubLon },
    source: "haversine",
  };
}

/**
 * Compute zone depth using H3 hexagonal grid.
 * More precise than haversine for urban zone matching.
 */
function computeZoneDepthH3(lat, lon, zoneId, city = "Chennai") {
  try {
    const zoneDepthScore = h3Service.calculateZoneDepthScore(
      lat,
      lon,
      zoneId,
      city,
    );

    // Convert H3 distance (in hexes) to approximate km for consistency
    const zoneCenter = h3Service.ZONE_CENTERS[zoneId.toLowerCase()];
    let distanceKm = 0;
    if (zoneCenter) {
      distanceKm = haversineKm(lat, lon, zoneCenter.lat, zoneCenter.lng);
    }

    return {
      distance_km: Math.round(distanceKm * 1000) / 1000,
      zone_depth_score: Math.round(zoneDepthScore * 1000) / 1000,
      hub: zoneCenter || { lat: 12.982, lon: 80.243 },
      source: "h3",
    };
  } catch (e) {
    console.warn(
      "[ZoneDepth] H3 calculation failed, using haversine:",
      e.message,
    );
    return computeZoneDepth(lat, lon);
  }
}

/**
 * Prefer H3 when enabled, otherwise PostGIS ST_Distance (geography) when enabled and RPC exists.
 */
async function computeZoneDepthAsync(
  lat,
  lon,
  zoneId = "adyar",
  city = "Chennai",
) {
  // Priority 1: H3 Geospatial Precision
  if (process.env.USE_H3_ZONE_DEPTH === "true") {
    return computeZoneDepthH3(lat, lon, zoneId, city);
  }

  // Priority 2: PostGIS
  const fallback = computeZoneDepth(lat, lon);
  if (process.env.USE_POSTGIS_ZONE_DEPTH !== "true") {
    return fallback;
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
    return fallback;
  }
  try {
    const hubLat = parseFloat(process.env.DARK_STORE_LAT || "12.982");
    const hubLon = parseFloat(process.env.DARK_STORE_LON || "80.243");
    const { data, error } = await supabase.rpc("hustlr_zone_depth", {
      worker_lat: lat,
      worker_lon: lon,
      hub_lat: hubLat,
      hub_lon: hubLon,
    });
    if (error) throw error;
    const row = typeof data === "string" ? JSON.parse(data) : data;
    if (row && row.distance_km != null && row.zone_depth_score != null) {
      return {
        distance_km: Number(row.distance_km),
        zone_depth_score: Number(row.zone_depth_score),
        hub: { lat: hubLat, lon: hubLon },
        source: row.source || "postgis",
      };
    }
  } catch (e) {
    console.warn("[ZoneDepth] PostGIS RPC failed, using haversine:", e.message);
  }
  return fallback;
}

module.exports = {
  computeZoneDepth,
  computeZoneDepthAsync,
  computeZoneDepthH3,
  haversineKm,
};

