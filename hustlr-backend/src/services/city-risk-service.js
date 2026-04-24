/**
 * City risk profiles (Chennai, Mumbai, Bengaluru, Kolkata) — underwriting-style priors for dashboards / ML context.
 */
const CITY_RISK_PROFILES = {
  Chennai: {
    city: 'Chennai',
    flood_rain_index: 0.82,
    heat_index: 0.71,
    aqi_index: 0.58,
    platform_index: 0.62,
    bandh_index: 0.55,
    summary: 'Coastal NE monsoon + cyclone tail risk; high rain-day count.',
  },
  Mumbai: {
    city: 'Mumbai',
    flood_rain_index: 0.88,
    heat_index: 0.52,
    aqi_index: 0.72,
    platform_index: 0.70,
    bandh_index: 0.48,
    summary: 'West-coast monsoon bursts; dense urban AQI stress during winter.',
  },
  Bengaluru: {
    city: 'Bengaluru',
    flood_rain_index: 0.55,
    heat_index: 0.48,
    aqi_index: 0.62,
    platform_index: 0.68,
    bandh_index: 0.42,
    summary: 'Convective bursts + lake-edge flooding; strong app-economy outage correlation.',
  },
  Kolkata: {
    city: 'Kolkata',
    flood_rain_index: 0.76,
    heat_index: 0.68,
    aqi_index: 0.65,
    platform_index: 0.55,
    bandh_index: 0.62,
    summary: 'Bay cyclone recurvature + high political-bandh cadence.',
  },
};

function listCityRiskProfiles() {
  return Object.values(CITY_RISK_PROFILES);
}

function getCityRiskProfile(cityName) {
  const key = Object.keys(CITY_RISK_PROFILES).find(
    (c) => c.toLowerCase() === (cityName || '').trim().toLowerCase(),
  );
  return key ? CITY_RISK_PROFILES[key] : null;
}

module.exports = { CITY_RISK_PROFILES, listCityRiskProfiles, getCityRiskProfile };
