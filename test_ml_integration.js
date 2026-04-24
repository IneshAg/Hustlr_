const axios = require('axios');
const ML_URL = 'http://localhost:8001';

async function testMLIntegration() {
  try {
    console.log('Testing ML integration...');
    
    // Test health endpoint
    const healthResponse = await axios.get(`${ML_URL}/health`, { timeout: 10000 });
    console.log('✅ Health check:', healthResponse.data.status);
    
    // Test fraud scoring with normal claim
    const normalClaim = {
      worker_id: 'worker_123',
      zone_id: 'Adyar',
      claim_timestamp: '2026-04-16T10:30:00Z',
      feature_vector: {
        zone_match: 0.95,
        gps_jitter: 0.08,
        accelerometer_match: 0.90,
        wifi_home_ssid: false,
        days_since_onboarding: 30,
        gps_zone_mismatch: false,
        battery_charging: false,
        platform_app_inactive: false,
        ip_home_match: true,
        claim_latency_under30s: false,
        gps_jitter_perfect: false,
        barometer_mismatch: false,
        hw_fingerprint_match: true,
        app_install_cluster: 1,
        referral_depth: 2,
        claim_hour_sin: 0.0,
        claim_hour_cos: 1.0,
        city_behavioral_risk: 0.55,
        zone_depth_score: 0.75,
        has_real_disruption: true,
        simultaneous_zone_claims: 1,
        iss_score: 50.0
      }
    };
    
    const fraudResponse = await axios.post(`${ML_URL}/fraud-score`, normalClaim, { timeout: 10000 });
    console.log('✅ Fraud score result:', {
      is_anomalous: fraudResponse.data.is_anomalous,
      anomaly_score: fraudResponse.data.anomaly_score,
      poisson_p_value: fraudResponse.data.poisson_p_value
    });
    
    // Test suspicious GPS
    const suspiciousClaim = {
      ...normalClaim,
      worker_id: 'worker_456',
      feature_vector: {
        ...normalClaim.feature_vector,
        gps_jitter: 0.0,
        gps_zone_mismatch: true,
        simultaneous_zone_claims: 8
      }
    };
    
    const suspiciousResponse = await axios.post(`${ML_URL}/fraud-score`, suspiciousClaim, { timeout: 10000 });
    console.log('✅ Suspicious GPS result:', {
      is_anomalous: suspiciousResponse.data.is_anomalous,
      anomaly_score: suspiciousResponse.data.anomaly_score
    });
    
    console.log('🎉 ML Integration Test Complete - All endpoints working!');
    
  } catch (error) {
    console.error('❌ ML Integration Test Failed:', error.message);
    if (error.code === 'ECONNREFUSED') {
      console.log('💡 Make sure ML service is running on port 8001');
    }
  }
}

testMLIntegration();
