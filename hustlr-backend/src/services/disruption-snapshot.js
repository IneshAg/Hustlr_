const {
  getCurrentWeather,
  get7DayForecast,
  assessDisruptions,
  buildPredictiveNudge,
} = require("./weather-service");

const { getCurrentAQI, assessAQIDisruption } = require("./aqi-service");
const { checkBandhNLP } = require("./news-service");
const {
  getPlatformStatus,
  detectPlatformTrigger,
  getInternetStatus,
  detectInternetTrigger,
} = require("./platform-service");
const { isTrustSufficient } = require("./data-trust");

const cache = {};
const CACHE_MS = 10 * 60 * 1000;

async function getCached(key, fn) {
  const now = Date.now();
  if (cache[key] && now - cache[key].ts < CACHE_MS) {
    return cache[key].data;
  }
  const data = await fn();
  cache[key] = { data, ts: now };
  return data;
}

function getAQILevel(aqi) {
  if (aqi <= 50) return "Good";
  if (aqi <= 100) return "Moderate";
  if (aqi <= 150) return "Unhealthy for Sensitive Groups";
  if (aqi <= 200) return "Unhealthy";
  if (aqi <= 300) return "Very Unhealthy";
  return "Hazardous";
}

/**
 * Assembles the same JSON as GET /disruptions/:zone.
 * @param {string} zone
 * @param {{ useCache?: boolean }} [options] useCache=false for cron / fresh polls
 */
async function fetchDisruptionBundle(zone, options = {}) {
  const useCache = options.useCache !== false;

  const wrap = (suffix, fn) => {
    const key = `${suffix}:${zone}`;
    if (!useCache) return fn();
    return getCached(key, fn);
  };

  const [weather, forecast, aqi, news, platformStatus, internetStatus] =
    await Promise.all([
      wrap("weather", () => getCurrentWeather(zone)),
      wrap("forecast", () => get7DayForecast(zone)),
      wrap("aqi", () => getCurrentAQI(zone)),
      wrap("news", () => checkBandhNLP(zone)),
      getPlatformStatus(zone),
      getInternetStatus(zone),
    ]);

  const disruptions = assessDisruptions(weather);

  const aqiTrigger = assessAQIDisruption(aqi);
  if (aqiTrigger) disruptions.push(aqiTrigger);

  const platformTrigger = detectPlatformTrigger(platformStatus);
  if (platformTrigger) disruptions.push(platformTrigger);

  const internetTrigger = detectInternetTrigger(internetStatus);
  if (internetTrigger) disruptions.push(internetTrigger);

  if (news.bandh_detected && news.confidence >= 0.6) {
    disruptions.push({
      trigger_type: "bandh",
      display_name: "Bandh / Shutdown",
      hourly_rate: 50,
      severity: news.confidence,
      current_value:
        "News confidence: " + Math.round(news.confidence * 100) + "%",
      threshold: "60% news confidence",
      payout_pct: 70,
      active: true,
      source: news.source ?? "NewsAPI",
    });
  }

  const nudge = buildPredictiveNudge(forecast);

  disruptions.forEach((d) => {
    const sources = [];

    if (weather._source === "live_tomorrowio") {
      sources.push("TOMORROWIO_LIVE");
    } else if (weather._source === "live_openweathermap") {
      sources.push("OPENWEATHER_LIVE");
    } else if ((weather._source || "").startsWith("live_")) {
      sources.push("WEATHERAPI_LIVE");
    }

    if (d.trigger_type && d.trigger_type.includes("rain")) {
      sources.push("IMD_OFFICIAL");
    }

    if ((aqi._source || "").includes("aqicn")) {
      sources.push("AQICN_LIVE");
    }

    if ((news.source || "").startsWith("live_") && news.bandh_detected) {
      sources.push("NEWS_CORROBORATED");
    }

    if (platformStatus.order_failure_rate > 0.6) {
      sources.push("PLATFORM_ORDER_LOG");
    }

    const trust = isTrustSufficient(sources);
    d.trust_score = trust.score;
    d.trust_sufficient = trust.sufficient;
    d.data_sources = sources;

    if (!trust.sufficient) {
      d.requires_review = true;
      d.review_reason = `Trust score ${trust.score} below ${trust.threshold}`;
    }
  });

  const data_sources = {
    weather: weather._source ?? "live",
    aqi: aqi._source ?? "live",
    news: news.source ?? "live",
    platform: platformStatus._source ?? "inferred",
    internet: internetStatus._source ?? "inferred",
  };

  return {
    zone,
    active: disruptions.length > 0,
    disruptions,
    weather: {
      temp_celsius: weather.temp_celsius,
      rainfall_mm_1h: weather.rainfall_mm_1h,
      condition: weather.condition,
      humidity: weather.humidity,
      local_time: weather.local_time,
      is_day: weather.is_day,
    },
    aqi: {
      current: aqi.aqi,
      pm25: aqi.pm25,
      level: getAQILevel(aqi.aqi),
      station: aqi.station,
    },
    platform: {
      status: platformStatus.status,
      failure_rate: platformStatus.order_failure_rate,
      orders_active: platformStatus.orders_last_hour,
      is_peak: platformStatus.is_peak_hour,
    },
    news_alert: news.bandh_detected
      ? {
          detected: true,
          confidence: news.confidence,
          headline: news.matched_keywords.join(", ") || null,
        }
      : null,
    predictive_nudge: nudge,
    forecast,
    data_sources,
    checked_at: new Date().toISOString(),
  };
}

module.exports = {
  fetchDisruptionBundle,
  getAQILevel,
  /** @internal testing / admin */
  _clearDisruptionCache: () => {
    Object.keys(cache).forEach((k) => delete cache[k]);
  },
};

