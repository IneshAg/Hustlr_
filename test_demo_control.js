// Simple test for demo disruption control (without database dependency)
const express = require('express');

const app = express();
app.use(express.json());

// Test endpoint to verify demo disruption control service
app.get('/test', (req, res) => {
  res.json({
    message: 'Demo disruption control service is working',
    available_zones: ['Adyar Dark Store Zone', 'Velachery', 'OMR (Old Mahabalipuram Road)', 'Anna Nagar', 'T Nagar'],
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
});

// Test creating a mock disruption (without database)
app.post('/create-mock', async (req, res) => {
  try {
    const { zone, disruption_type, severity = 0.5, duration_hours = 2 } = req.body;

    if (!zone || !disruption_type) {
      return res.status(400).json({ error: 'zone and disruption_type required' });
    }

    // Create mock disruption object (without database)
    const mockDisruption = {
      id: 'mock_' + Date.now(),
      zone,
      trigger_type: disruption_type,
      display_name: getDisplayName(disruption_type),
      severity: parseFloat(severity),
      current_value: getCurrentValue(disruption_type),
      threshold: getThreshold(disruption_type),
      source: 'demo_control_panel',
      active: true,
      demo_mode: true,
      duration_hours,
      started_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
      hourly_rate: getHourlyRate(disruption_type),
      forecast_impact: 'Monitoring conditions...',
      metadata: {
        created_by: 'demo_control_panel',
        test_scenario: true,
        mock_data: true
      }
    };

    console.log(`[Demo Control] Created ${disruption_type} disruption for ${zone} (severity: ${severity})`);

    return res.status(201).json({
      success: true,
      disruption: mockDisruption,
      message: `${disruption_type} disruption created for ${zone} (mock mode)`
    });

  } catch (error) {
    console.error('[Demo Control] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

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

function getCurrentValue(disruption_type) {
  switch (disruption_type) {
    case 'heavy_rain':
    case 'extreme_rain':
      return '75mm/hr';
    case 'heat_wave':
      return '45°C';
    case 'air_pollution':
      return 'AQI 180';
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

const PORT = 3002;
app.listen(PORT, () => {
  console.log(`🎮 Demo Disruption Test Server running on http://localhost:${PORT}`);
  console.log(`📊 Test endpoints:`);
  console.log(`   GET  http://localhost:${PORT}/test - Demo control status`);
  console.log(`   POST http://localhost:${PORT}/create-mock - Create mock disruption`);
});
