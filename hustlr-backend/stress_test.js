#!/usr/bin/env node
/**
 * Hustlr API stress + integration suite.
 *
 * Prerequisites: Node API running (default http://127.0.0.1:3000).
 * Optional: ML service on ML_SERVICE_URL for /health/services to show ml ok.
 *
 *   cd hustlr-backend && node stress_test.js
 *   STRESS_BASE_URL=http://127.0.0.1:3000 node stress_test.js
 */
require('dotenv').config();
const axios = require('axios');
const fs = require('fs');
const path = require('path');

const BASE = process.env.STRESS_BASE_URL || 'http://127.0.0.1:3000';
const CONCURRENT_DISRUPTIONS = parseInt(process.env.STRESS_DISRUPTION_CONCURRENCY || '40', 10);
const log = [];

let _phoneSeq = 0;
function uniquePhone() {
  _phoneSeq += 1;
  const core = `${Date.now()}${_phoneSeq}${Math.floor(Math.random() * 1e4)}`.replace(/\D/g, '');
  return `9${core.slice(-9)}`;
}

async function run(name, fn) {
  const t0 = Date.now();
  try {
    const result = await fn();
    log.push({ test: name, status: 'PASS', ms: Date.now() - t0, detail: result });
    console.log('PASS:', name, `(${Date.now() - t0}ms)`, '-', result);
  } catch (e) {
    const err = e.response?.data ?? e.message;
    log.push({
      test: name,
      status: 'FAIL',
      ms: Date.now() - t0,
      detail: err,
      http: e.response?.status,
    });
    console.log('FAIL:', name, '-', e.response?.status, JSON.stringify(err).slice(0, 200));
  }
}

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const i = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, i)];
}

async function main() {
  console.log('\n=== HUSTLR STRESS / LOAD TEST ===');
  console.log('BASE:', BASE, '| disruption concurrency:', CONCURRENT_DISRUPTIONS, '\n');

  let user1;
  let user2;
  let user3;

  await run('T1 — Register worker', async () => {
    const r = await axios.post(`${BASE}/workers/register`, {
      name: 'Stress T1',
      phone: uniquePhone(),
      zone: 'Adyar',
      city: 'Chennai',
      platform: 'Zepto',
    });
    user1 = r.data.user;
    if (!user1?.id) throw new Error('No user id');
    return `id=${user1.id.slice(0, 8)}…`;
  });

  await run('T2 — Create policy (full)', async () => {
    const r = await axios.post(`${BASE}/policies/create`, {
      user_id: user1.id,
      plan_tier: 'full',
    });
    const p = r.data.policy;
    if (!p) throw new Error('No policy');
    return `tier=${p.plan_tier} max_weekly=${p.max_weekly_payout}`;
  });

  await run('T3 — Single claim + fraud fields', async () => {
    const r = await axios.post(`${BASE}/claims/create`, {
      user_id: user1.id,
      plan_tier: 'full',
      trigger_type: 'rain_heavy',
      severity: 1.0,
      duration_hours: 3.0,
    });
    const c = r.data.claim;
    if (!c) throw new Error('No claim');
    return `payout=₹${c.gross_payout} fraud=${c.fraud_score} status=${c.fraud_status}`;
  });

  await run('T4 — Circuit breaker (hourly zone limit → 503)', async () => {
    const r = await axios.post(`${BASE}/workers/register`, {
      name: 'Stress CB',
      phone: uniquePhone(),
      zone: 'tambaram',
      city: 'Chennai',
      platform: 'Zepto',
    });
    user2 = r.data.user;
    await axios.post(`${BASE}/policies/create`, {
      user_id: user2.id,
      plan_tier: 'standard',
    });

    let trippedAt = -1;
    let lastStatus;
    for (let i = 1; i <= 60; i++) {
      try {
        await axios.post(`${BASE}/claims/create`, {
          user_id: user2.id,
          plan_tier: 'standard',
          trigger_type: 'rain_heavy',
          severity: 1.0,
          duration_hours: 1.0,
        });
      } catch (e) {
        lastStatus = e.response?.status;
        if (e.response?.status === 503) {
          trippedAt = i;
          break;
        }
      }
    }
    if (trippedAt === -1) {
      throw new Error(
        `Breaker did not return 503 in 60 tries (last HTTP ${lastStatus ?? 'n/a'})`,
      );
    }
    return `503 on claim #${trippedAt} (hourly zone cap)`;
  });

  await run('T5 — Parallel claims (12×, full + aqi_hazardous)', async () => {
    const r = await axios.post(`${BASE}/workers/register`, {
      name: 'Stress Parallel',
      phone: uniquePhone(),
      zone: 'Anna Nagar',
      city: 'Chennai',
      platform: 'Zepto',
    });
    user3 = r.data.user;
    await axios.post(`${BASE}/policies/create`, {
      user_id: user3.id,
      plan_tier: 'full',
    });

    const results = await Promise.allSettled(
      Array.from({ length: 12 }, () =>
        axios.post(`${BASE}/claims/create`, {
          user_id: user3.id,
          plan_tier: 'full',
          trigger_type: 'aqi_hazardous',
          severity: 0.8,
          duration_hours: 2.0,
        }),
      ),
    );
    const ok = results.filter((x) => x.status === 'fulfilled').length;
    const fail = results.filter((x) => x.status === 'rejected').length;
    return `${ok}/12 ok, ${fail}/12 rejected`;
  });

  await run('T6 — Disruptions JSON shape', async () => {
    const r = await axios.get(`${BASE}/disruptions/Adyar`);
    const d = r.data;
    const list = d.disruptions ?? [];
    const trust = list.length
      ? list.every((x) => x.trust_score !== undefined)
      : true;
    const wa = d.work_advisor?.earning_stability_index;
    return `disruptions=${list.length} trust_ok=${trust} work_advisor_esi=${wa ?? 'n/a'}`;
  });

  await run('T7 — Wallet read', async () => {
    const r = await axios.get(`${BASE}/wallet/${user1.id}`);
    return `balance=₹${r.data.balance}`;
  });

  await run(`T8 — Load: ${CONCURRENT_DISRUPTIONS} concurrent GET /disruptions/Velachery`, async () => {
    const latencies = [];
    const started = Date.now();
    const batch = Array.from({ length: CONCURRENT_DISRUPTIONS }, async () => {
      const t = Date.now();
      const res = await axios.get(`${BASE}/disruptions/Velachery`, { timeout: 60000 });
      latencies.push(Date.now() - t);
      return res.status;
    });
    const statuses = await Promise.all(batch);
    latencies.sort((a, b) => a - b);
    const bad = statuses.filter((s) => s !== 200).length;
    if (bad) throw new Error(`${bad} non-200 responses`);
    const total = Date.now() - started;
    return (
      `total_wall=${total}ms p50=${percentile(latencies, 50)}ms ` +
      `p95=${percentile(latencies, 95)}ms max=${latencies[latencies.length - 1]}ms`
    );
  });

  await run('T9 — GET /health + /health/services', async () => {
    const h = await axios.get(`${BASE}/health`);
    const s = await axios.get(`${BASE}/health/services`);
    return `api=${h.data.status} ml=${s.data.ml_service} supabase=${s.data.supabase}`;
  });

  const mlUrl = process.env.ML_SERVICE_URL;
  if (mlUrl && process.env.STRESS_INCLUDE_ML === 'true') {
    await run('T10 — ML: 15× concurrent GET /health', async () => {
      const base = mlUrl.replace(/\/$/, '');
      const jobs = Array.from({ length: 15 }, () =>
        axios.get(`${base}/health`, { timeout: 20000 }),
      );
      const out = await Promise.all(jobs);
      const bad = out.filter((r) => r.status !== 200).length;
      if (bad) throw new Error(`${bad} non-200`);
      return `status=${out[0].data?.status ?? 'n/a'}`;
    });
  }

  const passed = log.filter((x) => x.status === 'PASS').length;
  const failed = log.filter((x) => x.status === 'FAIL').length;
  console.log(`\n=== SUMMARY: ${passed} passed, ${failed} failed ===\n`);

  const out = path.join(__dirname, 'stress_result.json');
  fs.writeFileSync(out, JSON.stringify({ base: BASE, at: new Date().toISOString(), log }, null, 2), 'utf8');
  console.log('Wrote', out);

  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
