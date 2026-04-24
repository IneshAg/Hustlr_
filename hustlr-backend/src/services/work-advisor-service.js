/**
 * Guidewire-style preventive intelligence: earning-stability + shift-window hints.
 * Calls Python /work-advisor with live bundle fields + optional Prophet risk.
 */

const mlService = require("./ml-service");
const { personalizeAdvisorCopy } = require("./advisor-copy-service");

function _tomorrowForecastDay(forecast) {
  if (!Array.isArray(forecast) || forecast.length === 0) return null;
  if (forecast.length > 1) return forecast[1];
  return forecast[0];
}

/**
 * @param {string} zone
 * @param {object} bundle — output of fetchDisruptionBundle
 * @param {{ iss_score?: number }} [opts]
 */
async function buildWorkAdvisorPayload(zone, bundle, opts = {}) {
  const weather = bundle.weather || {};
  const aqi = bundle.aqi || {};
  const disruptions = bundle.disruptions || [];
  const forecast = bundle.forecast || [];
  const tomorrow = _tomorrowForecastDay(forecast);

  let mlTomorrowRisk = null;
  try {
    const mlFc = await mlService.getForecast(zone);
    const rows = mlFc?.forecast || [];
    if (rows[0] && typeof rows[0].risk_score === "number") {
      mlTomorrowRisk = rows[0].risk_score;
    }
  } catch {
    /* ignore */
  }

  const activeCount = disruptions.filter((d) => d.active !== false).length;

  return {
    zone,
    city: "Chennai",
    iss_score: opts.iss_score,
    tomorrow_rain_chance_pct: tomorrow?.rain_chance_pct ?? 0,
    tomorrow_rain_mm: tomorrow?.total_rain_mm ?? 0,
    today_rain_mm_1h: weather.rainfall_mm_1h ?? 0,
    aqi: typeof aqi.current === "number" ? aqi.current : 50,
    ml_tomorrow_risk: mlTomorrowRisk,
    active_disruption_count: activeCount,
  };
}

async function attachWorkAdvisor(zone, bundle, opts = {}) {
  try {
    const payload = await buildWorkAdvisorPayload(zone, bundle, opts);
    const advisor = await mlService.getWorkAdvisor(payload);

    const rewritten = await personalizeAdvisorCopy(advisor, {
      zone,
      city: payload.city,
      weather: bundle.weather,
      nudge: bundle.predictive_nudge,
    });

    if (rewritten) {
      return {
        ...advisor,
        headline: rewritten.headline,
        coverage_nudge: rewritten.coverage_nudge,
        copy_source: rewritten._copy_source,
      };
    }

    return advisor;
  } catch (e) {
    console.warn("[WorkAdvisor]", e.message);
    return {
      earning_stability_index: 60,
      stability_band: "ELEVATED",
      stability_band_label: "Elevated disruption risk",
      headline: "Advisory temporarily unavailable — using safe defaults.",
      suggest_activate_coverage: true,
      recommended_shift_windows: [
        { label: "Mid-morning", time: "9 AM – 12 PM", demand: "Medium" },
        { label: "Evening", time: "6 PM – 9 PM", demand: "High" }
      ],
      _source: "fallback",
    };
  }
}

module.exports = { attachWorkAdvisor, buildWorkAdvisorPayload };
