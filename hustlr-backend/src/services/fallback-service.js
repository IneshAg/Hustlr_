// services/fallback-service.js
// Realistic Chennai-specific fallback data for all external APIs.
// Returned whenever the real API fails — the Flutter app never sees an error.

function getFutureDate(daysAhead) {
  const d = new Date();
  d.setDate(d.getDate() + daysAhead);
  return d.toISOString().split('T')[0];
}

function isPeakHour() {
  const h = new Date().getHours();
  return (h >= 8 && h <= 11) || (h >= 17 && h <= 21);
}

const FALLBACKS = {

  weather: {
    temp_celsius:     31.5,
    feels_like:       35.2,
    rainfall_mm_1h:   0,        // OWM field: rain['1h'] (mm per hour)
    rainfall_mm_3h:   0,        // OWM field: rain['3h']
    humidity:         82,
    wind_kph:         14,
    condition:        'Partly cloudy',
    condition_id:     801,      // OWM condition code
    aqi_index:        2,        // OWM AQI: 1=Good 2=Fair 3=Moderate 4=Poor 5=VeryPoor
    pm25:             18.5,
    pm10:             42.0,
    city:             'Chennai',
    country:          'IN',
    local_time:       new Date().toISOString(),
    is_day:           new Date().getHours() > 6 && new Date().getHours() < 20,
    _source:          'fallback',
  },

  forecast: [
    {
      date:            getFutureDate(1),
      date_unix:       Math.floor(Date.now() / 1000) + 86400,
      max_temp:        34,
      min_temp:        26,
      total_rain_mm:   0,
      rain_chance_pct: 15,
      condition:       'Clear sky',
      condition_id:    800,
      uv_index:        7,
    },
    {
      date:            getFutureDate(2),
      date_unix:       Math.floor(Date.now() / 1000) + 172800,
      max_temp:        33,
      min_temp:        26,
      total_rain_mm:   2.4,
      rain_chance_pct: 45,
      condition:       'Light rain',
      condition_id:    500,
      uv_index:        6,
    },
    {
      date:            getFutureDate(3),
      date_unix:       Math.floor(Date.now() / 1000) + 259200,
      max_temp:        31,
      min_temp:        25,
      total_rain_mm:   18.6,
      rain_chance_pct: 72,
      condition:       'Moderate rain',
      condition_id:    501,
      uv_index:        4,
    },
    {
      date:            getFutureDate(4),
      date_unix:       Math.floor(Date.now() / 1000) + 345600,
      max_temp:        29,
      min_temp:        24,
      total_rain_mm:   42.0,
      rain_chance_pct: 88,
      condition:       'Heavy intensity rain',
      condition_id:    502,
      uv_index:        2,
    },
    {
      date:            getFutureDate(5),
      date_unix:       Math.floor(Date.now() / 1000) + 432000,
      max_temp:        28,
      min_temp:        24,
      total_rain_mm:   12.0,
      rain_chance_pct: 60,
      condition:       'Light rain',
      condition_id:    500,
      uv_index:        3,
    },
    {
      date:            getFutureDate(6),
      date_unix:       Math.floor(Date.now() / 1000) + 518400,
      max_temp:        30,
      min_temp:        25,
      total_rain_mm:   1.0,
      rain_chance_pct: 30,
      condition:       'Overcast clouds',
      condition_id:    804,
      uv_index:        5,
    },
    {
      date:            getFutureDate(7),
      date_unix:       Math.floor(Date.now() / 1000) + 604800,
      max_temp:        32,
      min_temp:        26,
      total_rain_mm:   0,
      rain_chance_pct: 10,
      condition:       'Clear sky',
      condition_id:    800,
      uv_index:        8,
    },
  ],

  aqi: {
    aqi:        68,
    aqi_owm:    2,
    pm25:       18.5,
    pm10:       42.0,
    no2:        12.0,
    o3:         60.0,
    station:    'OWM (13.0067,80.2574)',
    updated_at: new Date().toISOString(),
    _source:    'fallback',
  },

  news: {
    disruption_detected: false,
    confidence:          0,
    articles:            [],
    _source:             'fallback',
  },

  platform: {
    zone:               'Adyar Dark Store Zone',
    platform:           'Zepto',
    status:             'OPERATIONAL',
    order_failure_rate: 0.04,
    orders_last_hour:   634,
    avg_assignment_ms:  1100,
    dark_store_status:  'NORMAL',
    is_peak_hour:       isPeakHour(),
    _source:            'fallback',
  },

  internet: {
    avg_speed_mbps:     22.4,
    connectivity_pct:   98,
    trai_outage_logged: false,
    isp:                'Airtel / Jio / BSNL',
    tower_status:       'NORMAL',
    _source:            'fallback',
  },

  cell_tower: {
    lat: 13.0827,
    lng: 80.2707,
    accuracy: 500,
    source: 'fallback_cell_tower'
  },

  traffic: {
    source:              'fallback',
    zone:                'adyar_chennai',
    corridor:            'anna_salai_chennai',
    current_speed_kmh:   13.5,
    baseline_speed_kmh:  18,
    speed_drop_pct:      0.25,
    congestion_level:    'Moderate',
    congestion_multiplier: 1.35,
    distance_m:          4200,
    free_flow_secs:      840,
    timestamp:           new Date().toISOString(),
  },

};

module.exports = { FALLBACKS };

