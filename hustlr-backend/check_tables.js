const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_KEY;

const supabase = createClient(url, key, { auth: { persistSession: false } });

async function check() {
  const tables = [
    "users","policies","claims","wallet_transactions","risk_pools","shadow_policies",
    "fraud_baselines","weekly_settlements","notifications","referrals","appeal_requests",
    "admin_actions","reinsurance_triggers"
  ];
  
  for (let t of tables) {
    const { count, error } = await supabase.from(t).select('*', { count: 'exact', head: true });
    if (error) {
      console.log(`❌ ${t} — ${error.message}`);
    } else {
      console.log(`✅ ${t} — OK, ${count} rows`);
    }
  }
}

check().then(() => process.exit(0)).catch(console.error);
