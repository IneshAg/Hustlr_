// services/api-wrapper.js
// Wraps every external API call with try/catch and automatic fallback.
// Logs every failure. Never throws — always returns data.

const { FALLBACKS } = require('./fallback-service');

// Track which APIs are currently degraded
const apiStatus = {
  weather:    { healthy: true, failures: 0, last_failure: null },
  aqi:        { healthy: true, failures: 0, last_failure: null },
  news:       { healthy: true, failures: 0, last_failure: null },
  platform:   { healthy: true, failures: 0, last_failure: null },
  internet:   { healthy: true, failures: 0, last_failure: null },
  cell_tower: { healthy: true, failures: 0, last_failure: null },
  traffic:    { healthy: true, failures: 0, last_failure: null },
};

const MAX_FAILURES_BEFORE_SKIP = 3;
const RECOVERY_WINDOW_MS = 5 * 60 * 1000; // 5 minutes

function recordFailure(apiName, error) {
  const s = apiStatus[apiName];
  if (!s) return;
  s.failures++;
  s.last_failure = Date.now();

  if (s.failures >= MAX_FAILURES_BEFORE_SKIP) {
    s.healthy = false;
    console.warn(
      `[APIWrapper] ${apiName} marked DEGRADED after ` +
      `${s.failures} failures. Using fallback for 5 mins.`
    );
  }

  console.error(`[APIWrapper] ${apiName} failed:`, error.message);
}

function recordSuccess(apiName) {
  const s = apiStatus[apiName];
  if (!s) return;
  s.failures = 0;
  s.healthy  = true;
}

function shouldSkipAPI(apiName) {
  const s = apiStatus[apiName];
  if (!s || s.healthy) return false;

  // Auto-recover after 5 minutes
  if (Date.now() - s.last_failure > RECOVERY_WINDOW_MS) {
    s.healthy  = true;
    s.failures = 0;
    console.log(`[APIWrapper] ${apiName} recovered — retrying real API`);
    return false;
  }

  return true;
}

async function withFallback(apiName, apiFn, fallbackData) {
  // Skip real API if it has been failing repeatedly
  if (shouldSkipAPI(apiName)) {
    console.warn(`[APIWrapper] ${apiName} degraded — using fallback`);
    if (Array.isArray(fallbackData)) {
      return fallbackData.map(item => ({ ...item, _source: 'fallback_degraded' }));
    }
    return { ...fallbackData, _source: 'fallback_degraded' };
  }

  try {
    const result = await apiFn();
    recordSuccess(apiName);
    return result;
  } catch (e) {
    recordFailure(apiName, e);
    console.warn(`[APIWrapper] ${apiName} failed — using fallback`);
    if (Array.isArray(fallbackData)) {
      return fallbackData.map(item => ({ ...item, _source: 'fallback' }));
    }
    return { ...fallbackData, _source: 'fallback' };
  }
}

// Health check endpoint data
function getAPIHealth() {
  return Object.fromEntries(
    Object.entries(apiStatus).map(([name, s]) => [
      name,
      {
        healthy:      s.healthy,
        failures:     s.failures,
        last_failure: s.last_failure
          ? new Date(s.last_failure).toISOString()
          : null,
      },
    ])
  );
}

module.exports = { withFallback, getAPIHealth };

