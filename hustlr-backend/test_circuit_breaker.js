/**
 * Circuit Breaker Unit Test
 * Simulates 55 claims in adyar zone, checks that request 51 is blocked.
 */

require('dotenv').config();
const { checkCircuitBreaker } = require('./src/services/circuit_breaker');
const { supabase } = require('./src/config/supabase');

async function main() {
  const zone = 'adyar';
  const city = 'Chennai';
  const trigger = 'rain_heavy';

  console.log('Seeding 50 claims in last hour for zone:', zone);

  // Seed 50 claims directly in DB for adyar within the last hour
  const rows = Array.from({ length: 50 }, (_, i) => ({
    user_id:        'db268702-5a78-4c95-b133-67dc1560d03a',
    trigger_type:   trigger,
    zone,
    city,
    severity:       1.0,
    duration_hours: 3.0,
    gross_payout:   150,
    tranche1:       105,
    tranche2:       45,
    status:         'APPROVED',
    fraud_score:    5,
    fraud_status:   'CLEAN',
    created_at:     new Date(Date.now() - i * 60 * 1000).toISOString(), // within last hour
  }));

  const { error } = await supabase.from('claims').insert(rows);
  if (error) { console.error('Seed error:', error.message); process.exit(1); }
  console.log('✅ 50 claims seeded');

  // Now check circuit breaker — should be BLOCKED
  const result = await checkCircuitBreaker(zone, city, trigger);
  console.log('\nCircuit breaker result:', JSON.stringify(result, null, 2));

  if (result.blocked) {
    console.log('\n✅ Circuit breaker correctly TRIPPED — 429 would be returned to worker');
  } else {
    console.log('\n❌ Circuit breaker did NOT trip — investigate threshold logic');
  }

  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
setTimeout(() => { console.error('Timeout'); process.exit(1); }, 15000);
