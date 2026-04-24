// services/demo-disruption-control.js
// Demo control panel for creating mock disruption events
// Allows testing of rain, heat waves, and other disruption scenarios

const { supabase } = require('../config/supabase');
const { getCurrentWeather, get7DayForecast } = require('./weather-service');
const { getCurrentAQI, assessAQIDisruption } = require('./aqi-service');
const { checkBandhNLP } = require('./news-service');
const { getPlatformStatus, detectPlatformTrigger } = require('./platform-service');

const DEMO_ZONES = ['Adyar Dark Store Zone', 'Velachery', 'OMR (Old Mahabalipuram Road)', 'Anna Nagar', 'T Nagar'];

async function createDemoDisruption(req, res) {
  try {
    const { zone, disruption_type, severity, duration_hours = 2, demo_mode = false } = req.body;

    if (!zone || !disruption_type) {
      return res.status(400).json({ error: 'zone and disruption_type required' });
    }

    // Verify zone is monitored
    if (!DEMO_ZONES.includes(zone)) {
      return res.status(400).json({ error: 'Zone not supported for demo' });
    }

    // Get current weather for context
    const currentWeather = await getCurrentWeather(zone);
    const forecast = await get7DayForecast(zone);

    let disruptionEvent = {
      zone,
      trigger_type: disruption_type,
      display_name: getDisplayName(disruption_type),
      severity: parseFloat(severity),
      current_value: getCurrentValue(disruption_type, currentWeather),
      threshold: getThreshold(disruption_type),
      source: 'demo_control_panel',
      active: true,
      demo_mode: true,
      duration_hours,
      started_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
      hourly_rate: getHourlyRate(disruption_type),
      forecast_impact: getForecastImpact(disruption_type, forecast),
      current_conditions: currentWeather,
      metadata: {
        created_by: 'demo_control_panel',
        test_scenario: true,
        weather_context: currentWeather,
        forecast_context: forecast
      }
    };

    // Insert into disruption_events table
    const { data, error } = await supabase
      .from('disruption_events')
      .insert([disruptionEvent])
      .select();

    if (error) {
      console.error('[Demo Control] Failed to create disruption:', error);
      return res.status(500).json({ error: 'Failed to create disruption event' });
    }

    console.log(`[Demo Control] Created ${disruption_type} disruption for ${zone} (severity: ${severity})`);

    return res.status(201).json({
      success: true,
      disruption: data[0],
      message: `${disruption_type} disruption created for ${zone}`
    });

  } catch (error) {
    console.error('[Demo Control] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function getActiveDisruptions(req, res) {
  try {
    const { data, error } = await supabase
      .from('disruption_events')
      .select('*')
      .eq('active', true)
      .eq('demo_mode', true)
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) {
      return res.status(500).json({ error: 'Failed to fetch disruptions' });
    }

    return res.json({
      disruptions: data || [],
      total: data?.length || 0
    });

  } catch (error) {
    console.error('[Demo Control] Error fetching disruptions:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function deactivateDisruption(req, res) {
  try {
    const { disruption_id } = req.params;

    if (!disruption_id) {
      return res.status(400).json({ error: 'disruption_id required' });
    }

    const { data, error } = await supabase
      .from('disruption_events')
      .update({ 
        active: false,
        ended_at: new Date().toISOString(),
        metadata: {
          ...data[0]?.metadata,
          deactivated_by: 'demo_control_panel',
          deactivation_reason: 'Manual deactivation via demo control'
        }
      })
      .eq('id', disruption_id)
      .select();

    if (error) {
      return res.status(500).json({ error: 'Failed to deactivate disruption' });
    }

    console.log(`[Demo Control] Deactivated disruption ${disruption_id}`);

    return res.json({
      success: true,
      message: 'Disruption deactivated successfully'
    });

  } catch (error) {
    console.error('[Demo Control] Error deactivating disruption:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

function getDisplayName(disruption_type) {
  const names = {
    'heavy_rain': 'Heavy Rain',
    'extreme_rain': 'Extreme Rain / Cyclone',
    'heat_wave': 'Heat Wave',
    'air_pollution': 'Air Pollution',
    'bandh': 'Bandh/Strike',
    'power_outage': 'Power Outage',
    'internet_outage': 'Internet Outage',
    'platform_maintenance': 'Platform Maintenance'
  };
  return names[disruption_type] || disruption_type;
}

function getCurrentValue(disruption_type, weather) {
  switch (disruption_type) {
    case 'heavy_rain':
    case 'extreme_rain':
      return `${weather.rainfall_mm_1h || 0}mm/hr`;
    case 'heat_wave':
      return `${weather.temp_celsius || 0}°C`;
    case 'air_pollution':
      return 'AQI monitoring...';
    default:
      return 'Simulated';
  }
}

function getThreshold(disruption_type) {
  switch (disruption_type) {
    case 'heavy_rain':
      return '64.5mm/hr';
    case 'extreme_rain':
      return '115.6mm/hr';
    case 'heat_wave':
      return '43°C';
    case 'air_pollution':
      return 'AQI > 150';
    default:
      return 'Custom threshold';
  }
}

function getHourlyRate(disruption_type) {
  switch (disruption_type) {
    case 'heavy_rain':
      return 50;
    case 'extreme_rain':
      return 65;
    case 'heat_wave':
      return 40;
    case 'air_pollution':
      return 35;
    case 'bandh':
      return 60;
    case 'power_outage':
      return 45;
    case 'internet_outage':
      return 55;
    case 'platform_maintenance':
      return 25;
    default:
      return 30;
  }
}

function getForecastImpact(disruption_type, forecast) {
  if (!forecast || forecast.length === 0) return null;

  // Check if conditions will worsen/improve in next 48 hours
  const next48h = forecast.slice(0, 16); // 48 hours = 16 * 3-hour intervals
  
  switch (disruption_type) {
    case 'heavy_rain':
    case 'extreme_rain':
      const avgRain = next48h.reduce((sum, f) => sum + (f.total_rain_mm || 0), 0) / next48h.length;
      return `Expected rain: ${avgRain.toFixed(1)}mm in next 48h`;
    case 'heat_wave':
      const maxTemp = Math.max(...next48h.map(f => f.max_temp || 0));
      return `Expected max: ${maxTemp.toFixed(1)}°C in next 48h`;
    default:
      return 'Monitoring conditions...';
  }
}

async function getDemoStatus(req, res) {
  try {
    // Count active demo disruptions
    const { data: activeData, error: activeError } = await supabase
      .from('disruption_events')
      .select('id, zone, trigger_type, display_name, severity, created_at')
      .eq('active', true)
      .eq('demo_mode', true);

    // Count total demo disruptions created today
    const today = new Date().toISOString().split('T')[0];
    const { data: totalData, error: totalError } = await supabase
      .from('disruption_events')
      .select('id')
      .eq('demo_mode', true)
      .gte('created_at', today);

    if (activeError || totalError) {
      return res.status(500).json({ error: 'Failed to get demo status' });
    }

    return res.json({
      active_disruptions: activeData?.length || 0,
      total_today: totalData?.length || 0,
      available_zones: DEMO_ZONES,
      disruption_types: [
        { type: 'heavy_rain', name: 'Heavy Rain', description: 'Rainfall ≥ 64.5mm/hr' },
        { type: 'extreme_rain', name: 'Extreme Rain', description: 'Rainfall ≥ 115.6mm/hr' },
        { type: 'heat_wave', name: 'Heat Wave', description: 'Temperature ≥ 43°C' },
        { type: 'air_pollution', name: 'Air Pollution', description: 'AQI > 150' },
        { type: 'bandh', name: 'Bandh/Strike', description: 'Labor strike event' },
        { type: 'power_outage', name: 'Power Outage', description: 'Electrical grid failure' },
        { type: 'internet_outage', name: 'Internet Outage', description: 'Network connectivity failure' },
        { type: 'platform_maintenance', name: 'Platform Maintenance', description: 'Scheduled system maintenance' }
      ]
    });

  } catch (error) {
    console.error('[Demo Control] Error getting status:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

module.exports = {
  createDemoDisruption,
  getActiveDisruptions,
  deactivateDisruption,
  getDemoStatus
};

