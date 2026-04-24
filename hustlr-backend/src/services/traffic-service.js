// services/traffic-service.js
// Primary: TomTom Traffic Flow API (TOMTOM_API_KEY)
// Fallback: OpenRouteService Directions API (OPENROUTE_API_KEY)

const axios = require("axios");
const { withFallback } = require("./api-wrapper");
const { FALLBACKS } = require("./fallback-service");

const ORS_API_KEY = process.env.OPENROUTE_API_KEY;
const ORS_URL = "https://api.openrouteservice.org/v2/directions/driving-car";
const TOMTOM_API_KEY = process.env.TOMTOM_API_KEY;

// Route coordinate tuples use [longitude, latitude] (GeoJSON order — opposite of Google)
const CORRIDOR_BASELINES = {
  gst_road_chennai: {
    baseline_kmh: 20,
    start: [80.1999, 12.9716],
    end: [80.1, 12.925],
  },
  anna_salai_chennai: {
    baseline_kmh: 18,
    start: [80.2707, 13.0827],
    end: [80.2338, 13.0569],
  },
  omr_chennai: {
    baseline_kmh: 35,
    start: [80.2181, 12.9716],
    end: [80.227, 12.8406],
  },
  electronic_city_bengaluru: {
    baseline_kmh: 17,
    start: [77.6603, 12.8456],
    end: [77.5946, 12.9716],
  },
};

// Map Hustlr working zones -> nearest corridor
const ZONE_TO_CORRIDOR = {
  adyar_chennai: "anna_salai_chennai",
  velachery_chennai: "gst_road_chennai",
  tambaram_chennai: "gst_road_chennai",
  omr_chennai: "omr_chennai",
  koramangala_bengaluru: "electronic_city_bengaluru",
};

// Time-of-day congestion multipliers for Chennai (1.0 = free flow)
// Higher multiplier = more congestion = slower effective speed
function getCongestionMultiplier() {
  const hour = new Date().getHours();
  if (hour >= 8 && hour <= 10) return 1.65; // Morning peak
  if (hour >= 11 && hour <= 13) return 1.25; // Mid-day
  if (hour >= 17 && hour <= 20) return 1.8; // Evening peak (worst)
  if (hour >= 21 || hour <= 6) return 1.05; // Night (near free-flow)
  return 1.35; // Regular daytime
}

/**
 * Returns real-time traffic speed data for a Hustlr zone.
 * Uses TomTom flow as primary and OpenRouteService-derived speed as fallback.
 * @param {string} zone - Hustlr working zone key (e.g. "adyar_chennai")
 */
async function getTrafficSpeed(zone) {
  const corridorKey = ZONE_TO_CORRIDOR[zone] || "gst_road_chennai";
  const corridor = CORRIDOR_BASELINES[corridorKey];

  return withFallback(
    "traffic",
    async () => {
      try {
        return await _getTrafficFromTomTom(zone, corridorKey, corridor);
      } catch (e) {
        console.warn(
          "[Traffic] TomTom failed, falling back to ORS:",
          e.message,
        );
        return await _getTrafficFromORS(zone, corridorKey, corridor);
      }
    },
    FALLBACKS.traffic,
  );
}

async function _getTrafficFromTomTom(zone, corridorKey, corridor) {
  if (!TOMTOM_API_KEY) {
    throw new Error("TOMTOM_API_KEY missing");
  }

  const midLat = ((corridor.start[1] + corridor.end[1]) / 2).toFixed(6);
  const midLon = ((corridor.start[0] + corridor.end[0]) / 2).toFixed(6);
  const url =
    "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json";

  const resp = await axios.get(url, {
    timeout: 8000,
    params: {
      key: TOMTOM_API_KEY,
      point: `${midLat},${midLon}`,
      unit: "KMPH",
    },
  });

  const seg = resp.data?.flowSegmentData;
  if (!seg) {
    throw new Error("TomTom payload missing flowSegmentData");
  }

  const currentSpeed = Number(seg.currentSpeed ?? corridor.baseline_kmh);
  const freeFlow = Number(seg.freeFlowSpeed ?? corridor.baseline_kmh);
  const baseline = freeFlow > 0 ? freeFlow : corridor.baseline_kmh;
  const speedDropPct = Math.max(0, (baseline - currentSpeed) / baseline);

  return {
    source: "live_tomtom",
    zone,
    corridor: corridorKey,
    current_speed_kmh: Math.round(currentSpeed * 10) / 10,
    baseline_speed_kmh: Math.round(baseline * 10) / 10,
    speed_drop_pct: Math.round(speedDropPct * 1000) / 1000,
    congestion_level: _congestionLevel(speedDropPct),
    congestion_multiplier:
      baseline > 0 ? Math.max(1, baseline / Math.max(currentSpeed, 1)) : 1,
    distance_m:
      (Number(seg.currentTravelTime ?? 0) * Math.max(currentSpeed, 1)) / 3.6,
    free_flow_secs: Number(seg.freeFlowTravelTime ?? 0),
    timestamp: new Date().toISOString(),
  };
}

async function _getTrafficFromORS(zone, corridorKey, corridor) {
  const resp = await axios.post(
    ORS_URL,
    {
      coordinates: [corridor.start, corridor.end],
      instructions: false,
    },
    {
      headers: {
        Authorization: ORS_API_KEY,
        "Content-Type": "application/json",
      },
      timeout: 8000,
    },
  );

  const summary = resp.data.routes[0].summary;
  const distanceM = summary.distance; // metres
  const freeFlowSecs = summary.duration; // seconds (no traffic)

  // Apply congestion multiplier to simulate real traffic delay
  const multiplier = getCongestionMultiplier();
  const inTrafficSecs = freeFlowSecs * multiplier;
  const currentSpeed = (distanceM / inTrafficSecs) * 3.6; // km/h
  const speedDropPct =
    (corridor.baseline_kmh - currentSpeed) / corridor.baseline_kmh;

  console.log(
    `[Traffic] ORS LIVE | zone=${zone} corridor=${corridorKey}` +
      ` speed=${currentSpeed.toFixed(1)}km/h drop=${(speedDropPct * 100).toFixed(1)}%` +
      ` multiplier=${multiplier}x`,
  );

  return {
    source: "live_openrouteservice",
    zone,
    corridor: corridorKey,
    current_speed_kmh: Math.round(currentSpeed * 10) / 10,
    baseline_speed_kmh: corridor.baseline_kmh,
    speed_drop_pct: Math.round(speedDropPct * 1000) / 1000,
    congestion_level: _congestionLevel(speedDropPct),
    congestion_multiplier: multiplier,
    distance_m: Math.round(distanceM),
    free_flow_secs: Math.round(freeFlowSecs),
    timestamp: new Date().toISOString(),
  };
}

/**
 * Converts traffic data into a Hustlr disruption trigger.
 * Returns null if traffic is Normal or Moderate.
 */
function detectTrafficTrigger(trafficData) {
  if (!trafficData || trafficData.congestion_level !== "Severe") return null;

  return {
    trigger_type: "traffic_severe",
    display_name: "Severe Traffic Congestion",
    hourly_rate: 40,
    severity: trafficData.speed_drop_pct,
    current_value: `${trafficData.current_speed_kmh} km/h`,
    threshold: `< ${Math.round(trafficData.baseline_speed_kmh * 0.6)} km/h (>=40% speed drop)`,
    payout_pct: 70,
    active: true,
    source: trafficData.source,
  };
}

function _congestionLevel(dropPct) {
  if (dropPct < 0.15) return "Normal";
  if (dropPct < 0.3) return "Inconclusive_Mild";
  if (dropPct < 0.45) return "Inconclusive_Moderate";
  return "Severe";
}

// ── Blueprint additions: INCONCLUSIVE sub-bands ───────────────────────────────
/**
 * classifyTrafficIncident — splits old INCONCLUSIVE into two actionable bands.
 * Heavy rain amplifies effective speed drop by 35%.
 */
function classifyTrafficIncident(
  speedDropPct,
  weather,
  incidentType,
  corridor,
) {
  // Rain amplification: heavy rain makes congestion 35% worse
  const effectiveDrop =
    weather === "heavy_rain"
      ? Math.min(speedDropPct * 1.35, 1.0)
      : speedDropPct;

  if (effectiveDrop < 0.15) {
    return {
      classification: "NORMAL",
      action: "route_normally",
      delayBuffer: 0,
    };
  } else if (effectiveDrop <= 0.3) {
    return {
      classification: "INCONCLUSIVE_MILD",
      action: "route_with_buffer",
      delayBuffer: 0.1,
    };
  } else if (effectiveDrop <= 0.45) {
    return {
      classification: "INCONCLUSIVE_MODERATE",
      action: "flag_for_sla_review",
      delayBuffer: 0.25,
    };
  } else {
    return {
      classification: "ACCIDENT_BLACKSPOT",
      action: "check_reroute",
      delayBuffer: null,
    };
  }
}

/**
 * applyTTMCaps — Travel Time Multiplier hard caps.
 * Above 2.9 → trigger reroute instead of extending SLA.
 */
function applyTTMCaps(baseTTM, isPeakHour, isMonsoon) {
  let ttm = baseTTM;
  if (isPeakHour) ttm = Math.min(ttm, 2.5);
  if (isMonsoon) ttm += 0.4;
  return Math.min(ttm, 2.9); // Hard cap
}

// ── Chennai Metro Phase 2 construction zones (lack training data — apply caution buffer) ──
const METRO_CONSTRUCTION_ZONES = {
  OMR_Sholinganallur: {
    corridor: "Corridor 3 — SRP Tools to Navalur",
    speedReductionFactor: 0.7,
    active: true,
  },
  Velachery: {
    corridor: "Corridor 5 — near Velachery station",
    speedReductionFactor: 0.75,
    diversionActive: true,
    active: true,
  },
  Perumbakkam: {
    corridor: "Phase 2 station — post-2023",
    speedReductionFactor: 0.8,
    active: true,
  },
};

function isMetroConstructionZone(locationName) {
  return METRO_CONSTRUCTION_ZONES[locationName] || null;
}

module.exports = {
  getTrafficSpeed,
  detectTrafficTrigger,
  classifyTrafficIncident,
  applyTTMCaps,
  isMetroConstructionZone,
  METRO_CONSTRUCTION_ZONES,
};

