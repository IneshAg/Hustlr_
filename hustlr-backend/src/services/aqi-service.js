// services/aqi-service.js
// OWM Air Pollution API (free tier)
// Endpoint: api.openweathermap.org/data/2.5/air_pollution
// OWM AQI scale: 1=Good 2=Fair 3=Moderate 4=Poor 5=VeryPoor

const axios = require("axios");
const { withFallback } = require("./api-wrapper");
const { FALLBACKS } = require("./fallback-service");

const AQICN_KEY = process.env.WAQI_API_KEY || process.env.AQICN_API_KEY;

const ZONE_COORDS = {
  "Adyar Dark Store Zone": { lat: 13.0067, lon: 80.2574 },
  "Delhi Central": { lat: 28.6139, lon: 77.209 },
  "Gurugram Sector 44": { lat: 28.4595, lon: 77.0266 },
  "Noida Sector 62": { lat: 28.5355, lon: 77.391 },
  default: { lat: 13.0827, lon: 80.2707 },
};

function getCoordsForZone(zone) {
  if (ZONE_COORDS[zone]) return ZONE_COORDS[zone];
  const normalized = (zone || "").toLowerCase();
  for (const [key, coords] of Object.entries(ZONE_COORDS)) {
    if (normalized.includes(key.toLowerCase())) return coords;
  }
  return ZONE_COORDS["default"];
}

async function getCurrentAQI(zone = "Adyar Dark Store Zone") {
  const coords = getCoordsForZone(zone);

  return withFallback(
    "aqi",
    async () => {
      const url = `https://api.waqi.info/feed/geo:${coords.lat};${coords.lon}/`;
      const res = await axios.get(url, {
        timeout: 5000,
        params: {
          token: AQICN_KEY,
        },
      });

      if (res.data.status !== "ok") {
        throw new Error(`AQICN API failed: ${res.data.data}`);
      }

      const d = res.data.data;
      const usAqi = typeof d.aqi === "number" ? d.aqi : parseInt(d.aqi, 10);

      if (isNaN(usAqi)) {
        throw new Error("Invalid or missing AQI value from AQICN");
      }

      return {
        aqi: usAqi,
        pm25: d.iaqi?.pm25?.v ?? 0,
        pm10: d.iaqi?.pm10?.v ?? 0,
        no2: d.iaqi?.no2?.v ?? 0,
        o3: d.iaqi?.o3?.v ?? 0,
        station: d.city?.name ?? `AQICN (${coords.lat},${coords.lon})`,
        updated_at: d.time?.iso ?? new Date().toISOString(),
        _source: "live_aqicn",
      };
    },
    FALLBACKS.aqi,
  );
}

// AQI trigger check: US AQI >= 300 (Hazardous - per underwriting slide)
function assessAQIDisruption(aqi) {
  if (aqi.aqi >= 300) {
    return {
      trigger_type: "severe_pollution",
      display_name: "Hazardous AQI",
      hourly_rate: 60,
      severity: Math.min(aqi.aqi / 500, 1.0),
      current_value: `AQI ${aqi.aqi}`,
      threshold: "AQI 300",
      source: aqi._source,
      active: true,
    };
  } else if (aqi.aqi >= 200) {
    return {
      trigger_type: "aqi_unhealthy",
      display_name: "Severe Pollution",
      hourly_rate: 40,
      severity: Math.min(aqi.aqi / 300, 1.0),
      current_value: `AQI ${aqi.aqi}`,
      threshold: "AQI 200",
      source: aqi._source,
      active: true,
    };
  }
  return null;
}

module.exports = { getCurrentAQI, assessAQIDisruption };

