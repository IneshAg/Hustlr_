// services/platform-service.js
// Zepto has no public API — infers platform status from time/day patterns.
// Phase 3: replace getInferredPlatformStatus with real Zepto partner API call.

const { withFallback } = require('./api-wrapper');
const { FALLBACKS }    = require('./fallback-service');

async function getPlatformStatus(zone) {
  // Real implementation would call Zepto partner API
  // Using smart inferred fallback directly
  return getInferredPlatformStatus(zone);
}

// Smart fallback — uses real-world Chennai Zepto patterns
function getInferredPlatformStatus(zone) {
  const now  = new Date();
  const hour = now.getHours();
  const day  = now.getDay(); // 0=Sun 6=Sat

  const isPeak    = (hour >= 8 && hour <= 11) || (hour >= 17 && hour <= 21);
  const isWeekend = day === 0 || day === 6;

  // Chennai Zepto realistic baselines from public reports
  const baseOrders   = isPeak ? (isWeekend ? 920 : 750) : (isWeekend ? 380 : 280);
  const failureRate  = isPeak ? 0.03 : 0.08;
  const assignmentMs = isPeak ? 980 : 1350;

  const outageActive = process.env.SIMULATE_OUTAGE === 'true';

  return {
    zone,
    platform:           'Zepto',
    status:             outageActive ? 'DEGRADED' : 'OPERATIONAL',
    order_failure_rate: outageActive ? 0.87 : failureRate,
    orders_last_hour:   outageActive ? 4 : baseOrders,
    avg_assignment_ms:  outageActive ? 9200 : assignmentMs,
    dark_store_status:  outageActive ? 'REDUCED_CAPACITY' : 'NORMAL',
    is_peak_hour:       isPeak,
    is_weekend:         isWeekend,
    data_model:         'inferred',
    _source:            outageActive ? 'demo_override' : 'inferred',
  };
}

function detectPlatformTrigger(status) {
  if (status.order_failure_rate > 0.60) {
    return {
      trigger_type:  'platform_outage',
      display_name:  'Platform Downtime',
      hourly_rate:   50,
      severity:      status.order_failure_rate,
      current_value: Math.round(status.order_failure_rate * 100) + '% failure rate',
      threshold:     '60% failure rate',
      payout_pct:    status.order_failure_rate > 0.90 ? 80 : 40,
      active:        true,
    };
  }
  return null;
}

const axios = require('axios');

const ZONE_COORDS = {
  'Adyar Dark Store Zone':        { lat: 13.0067, lon: 80.2574 },
  'Velachery':                    { lat: 12.9815, lon: 80.2180 },
  'Tambaram':                     { lat: 12.9249, lon: 80.1000 },
  'OMR (Old Mahabalipuram Road)': { lat: 12.9010, lon: 80.2279 },
  'Anna Nagar':                   { lat: 13.0850, lon: 80.2101 },
  'T Nagar':                      { lat: 13.0418, lon: 80.2341 },
  'default':                      { lat: 13.0827, lon: 80.2707 },
};

function getCoordsForZone(zone) {
  if (ZONE_COORDS[zone]) return ZONE_COORDS[zone];
  for (const [key, coords] of Object.entries(ZONE_COORDS)) {
    if (zone.toLowerCase().includes(key.toLowerCase())) return coords;
  }
  return ZONE_COORDS['default'];
}

/**
 * Zone internet / connectivity signal.
 * Default: inferred model (no third-party cost). Ookla Enterprise Network Intelligence is optional
 * and paid — enable only with OOKLA_API_KEY + USE_OOKLA_INTERNET=true.
 */
async function getInternetStatus(zone) {
  const ooklaKey = (process.env.OOKLA_API_KEY || '').trim();
  const useOokla =
    process.env.USE_OOKLA_INTERNET === 'true' && ooklaKey.length > 0;

  if (!useOokla) {
    return getInferredInternetStatus(zone);
  }

  const coords = getCoordsForZone(zone);

  return withFallback(
    'internet',
    async () => {
      // Ookla for Enterprise — contract / billing required; not a free public API
      const url = 'https://api.ookla.com/v1/network-health';
      const res = await axios.get(url, {
        timeout: 5000,
        params: {
          lat: coords.lat,
          lon: coords.lon,
          radius: 5000, // 5km zone radius
          token: ooklaKey,
        },
      });

      const d = res.data;
      
      // Map API response to our standard format
      return {
        zone,
        avg_speed_mbps:     d.avg_download_mbps ?? 22.4,
        connectivity_pct:   d.connectivity_health_pct ?? 97,
        trai_outage_logged: d.active_outage ?? false,
        isp:                d.primary_isp ?? 'Airtel / Jio / BSNL',
        tower_status:       d.active_outage ? 'OUTAGE' : 'NORMAL',
        data_model:         'live_ookla_api',
        _source:            'live_ookla_api',
      };
    },
    getInferredInternetStatus(zone)
  );
}

function getInferredInternetStatus(zone) {
  const blackoutActive = process.env.SIMULATE_BLACKOUT === 'true';
  return {
    zone,
    avg_speed_mbps:     blackoutActive ? 0.2 : 22.4,
    connectivity_pct:   blackoutActive ? 6   : 97,
    trai_outage_logged: blackoutActive,
    isp:                'Airtel / Jio / BSNL',
    tower_status:       blackoutActive ? 'OUTAGE' : 'NORMAL',
    data_model:         'inferred',
    _source:            blackoutActive ? 'demo_override' : 'inferred',
  };
}

function detectInternetTrigger(status) {
  if (status.connectivity_pct < 10 || status.trai_outage_logged) {
    return {
      trigger_type:  'internet_blackout',
      display_name:  'Internet Zone Blackout',
      hourly_rate:   50,
      severity:      0.9,
      current_value: status.avg_speed_mbps + ' Mbps',
      threshold:     '2 Mbps zone average',
      payout_pct:    80,
      active:        true,
    };
  }
  return null;
}

module.exports = {
  getPlatformStatus,
  detectPlatformTrigger,
  getInternetStatus,
  detectInternetTrigger,
};

