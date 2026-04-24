const demoDisruptionControl = require('./src/services/demo_disruption_control');

// Test creating different disruption scenarios
async function testDemoDisruptions() {
  console.log('🎮 Testing Demo Disruption Control...');
  
  // Test 1: Heavy Rain
  console.log('\n🌧 Creating Heavy Rain disruption...');
  const heavyRain = await demoDisruptionControl.createDemoDisruption({
    body: {
      zone: 'Adyar Dark Store Zone',
      disruption_type: 'heavy_rain',
      severity: 0.7,
      duration_hours: 3
    }
  });
  console.log('✅ Heavy Rain:', heavyRain.success ? 'CREATED' : 'FAILED');

  // Test 2: Heat Wave
  console.log('\n🌡 Creating Heat Wave disruption...');
  const heatWave = await demoDisruptionControl.createDemoDisruption({
    body: {
      zone: 'Velachery',
      disruption_type: 'heat_wave',
      severity: 0.8,
      duration_hours: 4
    }
  });
  console.log('✅ Heat Wave:', heatWave.success ? 'CREATED' : 'FAILED');

  // Test 3: Get Active Disruptions
  console.log('\n📋 Getting Active Demo Disruptions...');
  const active = await demoDisruptionControl.getActiveDisruptions();
  console.log('✅ Active Disruptions:', active.disruptions?.length || 0);

  // Test 4: Get Demo Status
  console.log('\n📊 Getting Demo Status...');
  const status = await demoDisruptionControl.getDemoStatus();
  console.log('✅ Demo Status:', {
    active_disruptions: status.active_disruptions,
    total_today: status.total_today,
    available_zones: status.available_zones.length
  });

  console.log('\n🎉 Demo Disruption Control Test Complete!');
}

testDemoDisruptions();
