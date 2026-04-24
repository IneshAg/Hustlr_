const express = require('express');
const router = express.Router();

const { fetchDisruptionBundle, getAQILevel } = require('../services/disruption-snapshot');
const { getAPIHealth } = require('../services/api-wrapper');
const mlService = require('../services/ml-service');
const { attachWorkAdvisor } = require('../services/work-advisor-service');

// Literal paths must be registered before `/:zone` so "forecast" is not treated as a zone name.

// In-memory store for demo disruptions
const demoDisruptions = [];

// ─── POST /disruptions/create ──────────────────
router.post('/create', (req, res) => {
  const { zone, trigger_type, severity } = req.body;
  demoDisruptions.push({
    trigger_type: trigger_type || 'extreme_cyclone',
    display_name: trigger_type === 'extreme_cyclone' ? 'Severe Cyclone Warning' : trigger_type,
    hourly_rate: 100,
    severity: severity || 1.0,
    current_value: 'IMD Alert Red',
    threshold: 'IMD Alert Orange+',
    payout_pct: 100,
    active: true,
    zone,
    trust_score: 95,
    trust_sufficient: true,
    data_sources: ['IMD_OFFICIAL', 'DEMO_INJECTED'],
    created_at: new Date().toISOString()
  });
  
  // Clear cache to ensure demo disruption is immediately visible
  const { _clearDisruptionCache } = require('../services/disruption-snapshot');
  _clearDisruptionCache();
  
  return res.json({ success: true });
});

// ─── GET /disruptions/forecast/:zone ──────────────────
router.get('/forecast/:zone', async (req, res) => {
  const { zone } = req.params;
  try {
    const forecast = await mlService.getForecast(zone);
    return res.json(forecast);
  } catch (e) {
    return res.status(500).json({ zone, forecast: [], error: e.message });
  }
});

// ─── Health check ─────────────────────────────
router.get('/health/apis', async (req, res) => {
  return res.json({
    api_health: getAPIHealth(),
    checked_at: new Date().toISOString(),
  });
});

// ─── Debug routes ─────────────────────────────
router.get('/weather/current', async (req, res) => {
  const { getCurrentWeather } = require('../services/weather-service');
  const data = await getCurrentWeather();
  return res.json(data);
});

router.get('/aqi/current', async (req, res) => {
  const { getCurrentAQI } = require('../services/aqi-service');
  const data = await getCurrentAQI();
  return res.json(data);
});

router.get('/news/check', async (req, res) => {
  const { checkBandhNLP } = require('../services/news-service');
  const zone = req.query.zone;
  const data = await checkBandhNLP(zone);
  return res.json(data);
});

// ─── GET /disruptions/:zone ───────────────────
router.get('/:zone', async (req, res) => {
  const { zone } = req.params;

  try {
    const body = await fetchDisruptionBundle(zone, { useCache: true });
    let issOpt;
    if (req.query.iss != null && req.query.iss !== '') {
      const n = parseInt(String(req.query.iss), 10);
      if (Number.isFinite(n)) issOpt = n;
    }
    body.work_advisor = await attachWorkAdvisor(zone, body, { iss_score: issOpt });

    const localDemos = demoDisruptions.filter(d => d.zone === zone);
    if (localDemos.length > 0) {
      body.active = true;
      body.disruptions.push(...localDemos);
    }

    return res.json(body);
  } catch (e) {
    console.error('[Disruptions] Critical error:', e.message);
    return res.status(500).json({
      zone,
      active: false,
      disruptions: [],
      error: 'Disruption service error',
    });
  }
});

module.exports = router;
module.exports.getAQILevel = getAQILevel;

