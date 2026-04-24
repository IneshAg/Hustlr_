// services/weather-service.js
// Primary: Tomorrow.io Weather Intelligence (TOMORROW_API_KEY)
// Fallback: OpenWeatherMap free tier (OWM_API_KEY)

const axios = require("axios");
const { withFallback } = require("./api-wrapper");
const { FALLBACKS } = require("./fallback-service");

const OWM_KEY = process.env.OWM_API_KEY;
const TOMORROW_KEY = process.env.TOMORROW_API_KEY;

// Chennai zone coordinates
const ZONE_COORDS = {
  "Adyar Dark Store Zone": { lat: 13.0067, lon: 80.2574 },
  Velachery: { lat: 12.9815, lon: 80.218 },
  Tambaram: { lat: 12.9249, lon: 80.1 },
  "OMR (Old Mahabalipuram Road)": { lat: 12.901, lon: 80.2279 },
  "Anna Nagar": { lat: 13.085, lon: 80.2101 },
  "T Nagar": { lat: 13.0418, lon: 80.2341 },
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

function mapTomorrowCondition(weatherCode) {
  const code = Number(weatherCode ?? 0);
  const labels = {
    1000: "clear",
    1100: "mostly clear",
    1101: "partly cloudy",
    1102: "mostly cloudy",
    1001: "cloudy",
    4000: "drizzle",
    4001: "rain",
    4200: "light rain",
    4201: "heavy rain",
    5000: "snow",
    5100: "light snow",
    5101: "heavy snow",
    6000: "freezing drizzle",
    6001: "freezing rain",
    6200: "light freezing rain",
    6201: "heavy freezing rain",
    7000: "ice pellets",
    7101: "heavy ice pellets",
    7102: "light ice pellets",
    8000: "thunderstorm",
  };
  return labels[code] || "unknown";
}

async function _getCurrentWeatherTomorrow(coords) {
  if (!TOMORROW_KEY) {
    throw new Error("TOMORROW_API_KEY missing");
  }

  const res = await axios.get("https://api.tomorrow.io/v4/weather/realtime", {
    timeout: 5000,
    params: {
      location: `${coords.lat},${coords.lon}`,
      units: "metric",
      apikey: TOMORROW_KEY,
    },
  });

  const values = res.data?.data?.values;
  if (!values) {
    throw new Error("Tomorrow realtime payload missing values");
  }

  const localTime = res.data?.data?.time || new Date().toISOString();
  const hour = new Date(localTime).getHours();
  const rainPerHour =
    Number(values.rainIntensity ?? values.precipitationIntensity ?? 0) || 0;

  return {
    temp_celsius: Number(values.temperature ?? 0),
    feels_like: Number(values.temperatureApparent ?? values.temperature ?? 0),
    rainfall_mm_1h: rainPerHour,
    rainfall_mm_3h: rainPerHour * 3,
    humidity: Number(values.humidity ?? 0),
    wind_kph: Number(values.windSpeed ?? 0) * 3.6,
    condition: mapTomorrowCondition(values.weatherCode),
    condition_id: Number(values.weatherCode ?? 0),
    city: "Chennai",
    country: "IN",
    local_time: localTime,
    is_day: hour >= 6 && hour <= 18,
    _source: "live_tomorrowio",
  };
}

async function _getCurrentWeatherOpenWeather(coords) {
  const url = "https://api.openweathermap.org/data/2.5/weather";
  const res = await axios.get(url, {
    timeout: 5000,
    params: {
      lat: coords.lat,
      lon: coords.lon,
      appid: OWM_KEY,
      units: "metric",
    },
  });

  const d = res.data;
  const rain1h = d.rain?.["1h"] ?? 0;
  const rain3h = d.rain?.["3h"] ?? 0;

  return {
    temp_celsius: d.main.temp,
    feels_like: d.main.feels_like,
    rainfall_mm_1h: rain1h,
    rainfall_mm_3h: rain3h,
    humidity: d.main.humidity,
    wind_kph: d.wind.speed * 3.6,
    condition: d.weather[0].description,
    condition_id: d.weather[0].id,
    city: d.name,
    country: d.sys.country,
    local_time: new Date(d.dt * 1000).toISOString(),
    is_day: d.weather[0].icon.endsWith("d"),
    _source: "live_openweathermap",
  };
}

async function _getForecastTomorrow(coords) {
  if (!TOMORROW_KEY) {
    throw new Error("TOMORROW_API_KEY missing");
  }

  const res = await axios.get("https://api.tomorrow.io/v4/weather/forecast", {
    timeout: 5000,
    params: {
      location: `${coords.lat},${coords.lon}`,
      timesteps: "1d",
      units: "metric",
      apikey: TOMORROW_KEY,
    },
  });

  const daily = res.data?.timelines?.daily;
  if (!Array.isArray(daily) || daily.length === 0) {
    throw new Error("Tomorrow forecast payload missing daily timeline");
  }

  return daily.slice(0, 7).map((item) => {
    const date =
      (item.time || "").split("T")[0] || new Date().toISOString().split("T")[0];
    const values = item.values || {};
    const rainMm = Number(
      values.precipitationAccumulationSum ??
        values.precipitationIntensityAvg ??
        values.rainAccumulationSum ??
        0,
    );
    const chance = Number(
      values.precipitationProbabilityAvg ??
        values.precipitationProbabilityMax ??
        0,
    );
    const conditionCode = values.weatherCodeMax ?? values.weatherCode ?? 0;

    return {
      date,
      date_unix: Math.floor(new Date(date).getTime() / 1000),
      max_temp: Number(
        values.temperatureMax ?? values.temperatureApparentMax ?? 0,
      ),
      min_temp: Number(
        values.temperatureMin ?? values.temperatureApparentMin ?? 0,
      ),
      total_rain_mm: Math.round(rainMm * 10) / 10,
      rain_chance_pct: Math.round(chance),
      condition: mapTomorrowCondition(conditionCode),
      uv_index: Math.round(Number(values.uvIndexMax ?? 0)),
      _source: "live_tomorrowio",
    };
  });
}

async function _getForecastOpenWeather(coords) {
  const url = "https://api.openweathermap.org/data/2.5/forecast";
  const res = await axios.get(url, {
    timeout: 5000,
    params: {
      lat: coords.lat,
      lon: coords.lon,
      appid: OWM_KEY,
      units: "metric",
      cnt: 40,
    },
  });

  const byDate = {};
  for (const item of res.data.list) {
    const date = item.dt_txt.split(" ")[0];
    if (!byDate[date]) {
      byDate[date] = {
        temps: [],
        rain_total: 0,
        rain_pops: [],
        conditions: [],
        uv_indices: [],
      };
    }
    byDate[date].temps.push(item.main.temp);
    byDate[date].rain_total += item.rain?.["3h"] ?? 0;
    byDate[date].rain_pops.push((item.pop ?? 0) * 100);
    byDate[date].conditions.push(item.weather[0].description);
    byDate[date].uv_indices.push(estimateUV(item.weather[0].id));
  }

  return Object.entries(byDate)
    .slice(0, 7)
    .map(([date, d]) => ({
      date,
      date_unix: new Date(date).getTime() / 1000,
      max_temp: Math.max(...d.temps),
      min_temp: Math.min(...d.temps),
      total_rain_mm: Math.round(d.rain_total * 10) / 10,
      rain_chance_pct: Math.round(Math.max(...d.rain_pops)),
      condition: d.conditions[Math.floor(d.conditions.length / 2)],
      uv_index: Math.round(
        d.uv_indices.reduce((a, b) => a + b, 0) / d.uv_indices.length,
      ),
      _source: "live_openweathermap",
    }));
}

// ─────────────────────────────────────────────
// CURRENT WEATHER
// ─────────────────────────────────────────────
async function getCurrentWeather(zone = "Adyar Dark Store Zone") {
  const coords = getCoordsForZone(zone);

  return withFallback(
    "weather",
    async () => {
      try {
        return await _getCurrentWeatherTomorrow(coords);
      } catch (e) {
        console.warn(
          "[Weather] Tomorrow.io failed, falling back to OWM:",
          e.message,
        );
        return await _getCurrentWeatherOpenWeather(coords);
      }
    },
    FALLBACKS.weather,
  );
}

// ─────────────────────────────────────────────
// 5-DAY FORECAST (3-hour intervals → aggregated to daily)
// ─────────────────────────────────────────────
async function get7DayForecast(zone = "Adyar Dark Store Zone") {
  const coords = getCoordsForZone(zone);

  return withFallback(
    "weather",
    async () => {
      try {
        return await _getForecastTomorrow(coords);
      } catch (e) {
        console.warn(
          "[Weather] Tomorrow.io forecast failed, falling back to OWM:",
          e.message,
        );
        return await _getForecastOpenWeather(coords);
      }
    },
    FALLBACKS.forecast,
  );
}

// ─────────────────────────────────────────────
// DISRUPTION ASSESSMENT
// ─────────────────────────────────────────────
function assessDisruptions(weather) {
  const disruptions = [];

  // Heavy Rain: ≥ 64.5mm/hr (IMD threshold)
  if (weather.rainfall_mm_1h >= 115.6) {
    disruptions.push({
      trigger_type: "extreme_rain",
      display_name: "Extreme Rain / Cyclone",
      hourly_rate: 65,
      severity: Math.min(weather.rainfall_mm_1h / 115.6, 1.0),
      current_value: `${weather.rainfall_mm_1h}mm/hr`,
      threshold: "115.6mm/hr",
      source: weather._source,
      active: true,
    });
  } else if (weather.rainfall_mm_1h >= 64.5) {
    disruptions.push({
      trigger_type: "heavy_rain",
      display_name: "Heavy Rain",
      hourly_rate: 50,
      severity: Math.min(weather.rainfall_mm_1h / 115.6, 1.0),
      current_value: `${weather.rainfall_mm_1h}mm/hr`,
      threshold: "64.5mm/hr",
      source: weather._source,
      active: true,
    });
  } else if (weather.rainfall_mm_1h > 0) {
    // Demo mode — any rain shows alert (remove in production)
    disruptions.push({
      trigger_type: "heavy_rain",
      display_name: "Heavy Rain",
      hourly_rate: 50,
      severity: 0.6,
      current_value: `${weather.rainfall_mm_1h}mm/hr`,
      threshold: "64.5mm/hr",
      source: weather._source,
      active: true,
      demo_mode: true,
    });
  }

  // Heat Wave: ≥ 43°C
  if (weather.temp_celsius >= 43.0) {
    disruptions.push({
      trigger_type: "heat_wave",
      display_name: "Heat Wave",
      hourly_rate: 40,
      severity: Math.min((weather.temp_celsius - 43) / 5, 1.0),
      current_value: `${weather.temp_celsius}°C`,
      threshold: "43°C",
      source: weather._source,
      active: true,
    });
  }

  return disruptions;
}

// ─────────────────────────────────────────────
// PREDICTIVE NUDGE
// ─────────────────────────────────────────────
function buildPredictiveNudge(forecast) {
  if (!forecast || forecast.length < 3) return null;

  const next3 = Array.isArray(forecast) ? forecast.slice(0, 3) : [];
  if (next3.length === 0) return null;

  const highestRisk = next3.reduce(
    (max, day) => (day.rain_chance_pct > max.rain_chance_pct ? day : max),
    next3[0],
  );

  if (!highestRisk || highestRisk.rain_chance_pct < 60) return null;

  return {
    type: "rain_warning",
    message: `Heavy rain expected ${formatDate(highestRisk.date)} in your zone.`,
    sub_message: `Activate ₹49 Standard Shield now to protect ₹600+ earnings.`,
    rain_chance: highestRisk.rain_chance_pct,
    expected_mm: highestRisk.total_rain_mm,
    date: highestRisk.date,
    cta: "Activate Standard Shield",
    urgency: highestRisk.rain_chance_pct >= 80 ? "HIGH" : "MEDIUM",
  };
}

// ─────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────

// Estimate UV from OWM condition code (free tier has no UV in forecast)
function estimateUV(conditionId) {
  if (conditionId === 800) return 8;
  if (conditionId >= 801 && conditionId <= 802) return 6;
  if (conditionId >= 803 && conditionId <= 804) return 4;
  if (conditionId >= 500 && conditionId <= 531) return 2;
  if (conditionId >= 200 && conditionId <= 299) return 1;
  return 5;
}

function formatDate(dateStr) {
  const d = new Date(dateStr);
  const days = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];
  return days[d.getDay()];
}

module.exports = {
  getCurrentWeather,
  get7DayForecast,
  assessDisruptions,
  buildPredictiveNudge,
};

