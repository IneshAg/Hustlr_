// test_all_apis.js — Hustlr API Health Diagnostic
// Run with: node test_all_apis.js
require('dotenv').config();
const axios = require('axios');

const RESULTS = [];

function pass(name, detail) {
  console.log('  [PASS]  ' + name + ': ' + detail);
  RESULTS.push({ name, status: 'PASS', detail });
}
function fail(name, detail) {
  console.log('  [FAIL]  ' + name + ': ' + detail);
  RESULTS.push({ name, status: 'FAIL', detail });
}
function warn(name, detail) {
  console.log('  [WARN]  ' + name + ': ' + detail);
  RESULTS.push({ name, status: 'WARN', detail });
}

async function testOpenWeatherMap() {
  try {
    const r = await axios.get('https://api.openweathermap.org/data/2.5/weather', {
      params: { lat: 13.0827, lon: 80.2707, appid: process.env.OWM_API_KEY, units: 'metric' },
      timeout: 7000,
    });
    pass('OpenWeatherMap', `${r.data.name} — ${r.data.main.temp}°C, ${r.data.weather[0].description}`);
  } catch (e) {
    fail('OpenWeatherMap', e.response?.data?.message || e.message);
  }
}

async function testAQICN() {
  try {
    const r = await axios.get('https://api.waqi.info/feed/geo:13.0827;80.2707/', {
      params: { token: process.env.AQICN_API_KEY },
      timeout: 7000,
    });
    if (r.data.status !== 'ok') throw new Error(r.data.data);
    pass('AQICN (AQI)', `AQI=${r.data.data.aqi} at station: ${r.data.data.city?.name}`);
  } catch (e) {
    fail('AQICN (AQI)', e.message);
  }
}

async function testNewsAPI() {
  try {
    const r = await axios.get('https://newsapi.org/v2/everything', {
      params: { q: 'bandh chennai', pageSize: 3, apiKey: process.env.NEWSAPI_KEY },
      timeout: 7000,
    });
    pass('NewsAPI', `Status: ${r.data.status} | Articles returned: ${r.data.totalResults}`);
  } catch (e) {
    const msg = e.response?.data?.message || e.message;
    if (msg.includes('Developer accounts')) {
      warn('NewsAPI', `Key valid but plan restricted to localhost: "${msg}"`);
    } else {
      fail('NewsAPI', msg);
    }
  }
}

async function testMaxMind() {
  const accountId = (process.env.MAXMIND_ACCOUNT_ID || '').trim();
  const licenseKey = (process.env.MAXMIND_LICENSE_KEY || '').trim();
  if (!accountId || !licenseKey) {
    warn(
      'MaxMind GeoIP2',
      'Skipped — set MAXMIND_ACCOUNT_ID and MAXMIND_LICENSE_KEY (both required)'
    );
    return;
  }
  try {
    // Test with Google's public IP
    const r = await axios.get(`https://geolite.info/geoip/v2.1/city/8.8.8.8`, {
      auth: { username: accountId, password: licenseKey },
      timeout: 7000,
    });
    const loc = r.data.city?.names?.en || r.data.country?.names?.en || 'Unknown';
    pass('MaxMind GeoIP2', `Resolved 8.8.8.8 → ${loc}, ${r.data.country?.names?.en}`);
  } catch (e) {
    fail('MaxMind GeoIP2', e.response?.data?.error || e.message);
  }
}

async function testGoogleMaps() {
  try {
    const r = await axios.get('https://maps.googleapis.com/maps/api/directions/json', {
      params: {
        origin: '13.0827,80.2707',
        destination: '13.0569,80.2338',
        departure_time: 'now',
        traffic_model: 'best_guess',
        key: process.env.GOOGLE_MAPS_API_KEY,
      },
      timeout: 8000,
    });
    if (r.data.status !== 'OK') throw new Error(`Status: ${r.data.status} — ${r.data.error_message || ''}`);
    const leg = r.data.routes[0].legs[0];
    pass('Google Maps Directions', `Route: ${leg.distance.text}, normal=${leg.duration.text}, in-traffic=${leg.duration_in_traffic?.text || 'N/A'}`);
  } catch (e) {
    fail('Google Maps Directions', e.response?.data?.error_message || e.message);
  }
}

async function testSupabase() {
  try {
    const r = await axios.get(`${process.env.SUPABASE_URL}/rest/v1/users?limit=1`, {
      headers: {
        apikey: process.env.SUPABASE_SERVICE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_KEY}`,
      },
      timeout: 7000,
    });
    pass('Supabase (Postgres)', `Connected ✓ — users table accessible, HTTP ${r.status}`);
  } catch (e) {
    fail('Supabase (Postgres)', e.response?.data?.message || e.message);
  }
}

async function testUnwiredLabs() {
  try {
    const r = await axios.post('https://us1.unwiredlabs.com/v2/process.php', {
      token: process.env.CELL_LOCATION_API_KEY,
      radio: 'lte',
      mcc: 404,
      mnc: 20,
      cells: [{ lac: 1234, cid: 5678, psc: 0, signal: -80 }],
      address: 0,
    }, { timeout: 7000 });
    if (r.data.status === 'ok' || r.data.status === 'success') {
      pass('Unwired Labs (Cell Tower)', `Estimated location: lat=${r.data.lat}, lng=${r.data.lon}, accuracy=${r.data.accuracy}m`);
    } else {
      warn('Unwired Labs (Cell Tower)', `Responded but: ${r.data.message || r.data.status}`);
    }
  } catch (e) {
    fail('Unwired Labs (Cell Tower)', e.response?.data?.message || e.message);
  }
}

async function main() {
  console.log('\nHustlr API Health Check');
  console.log('--------------------------------------------------');
  await testSupabase();
  await testOpenWeatherMap();
  await testAQICN();
  await testNewsAPI();
  await testMaxMind();
  await testGoogleMaps();
  await testUnwiredLabs();

  console.log('\n--------------------------------------------------');
  const passed = RESULTS.filter(r => r.status === 'PASS').length;
  const warned = RESULTS.filter(r => r.status === 'WARN').length;
  const failed = RESULTS.filter(r => r.status === 'FAIL').length;
  console.log('\nSummary: ' + passed + ' passed  |  ' + warned + ' warnings  |  ' + failed + ' failed\n');
}

main().catch(console.error);
