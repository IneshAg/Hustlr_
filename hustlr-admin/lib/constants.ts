// Mirrors hustlr-backend/src/config/constants.js exactly

const DEFAULT_API_BASE =
  process.env.NODE_ENV === 'development'
    ? 'http://127.0.0.1:3000'
    : 'https://hustlr-ad32.onrender.com';

const DEFAULT_ML_API_BASE =
  process.env.NODE_ENV === 'development'
    ? 'http://127.0.0.1:8000'
    : 'https://hustlr-2ppj.onrender.com';

export const API_BASE = process.env.NEXT_PUBLIC_API_BASE || DEFAULT_API_BASE;
export const ML_API_BASE = process.env.NEXT_PUBLIC_ML_API_BASE || DEFAULT_ML_API_BASE;

export const PLAN_CONFIG = {
  basic: {
    base: 35, max_payout: 210, daily_cap: 100,
    name: 'Basic Shield', target_bcr: 0.62, multiplier: 6.0,
    color: '#3FFF8B66',
  },
  standard: {
    base: 49, max_payout: 340, daily_cap: 150,
    name: 'Standard Shield', target_bcr: 0.63, multiplier: 6.9,
    color: '#3FFF8B',
  },
  full: {
    base: 79, max_payout: 500, daily_cap: 250,
    name: 'Full Shield', target_bcr: 0.65, multiplier: 6.3,
    color: '#3FFF8BCC',
  },
} as const;

export const BCR_CEILING = 85; // percent
export const REINSURANCE_MULTIPLE = 4; // × weekly pool

export const ZONES = [
  { name: 'Adyar',      workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
  { name: 'Velachery',  workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
  { name: 'Tambaram',   workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
  { name: 'Anna Nagar', workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
  { name: 'T Nagar',    workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
  { name: 'Perungudi',  workers: 0, risk: 'LOW' as const, disruption: false, bcr: 0, claims_today: 0 },
];

export const WEEKLY_HISTORY = [
  { week: 'Wk 1', premiums: 0, claims: 0 },
  { week: 'Wk 2', premiums: 0, claims: 0 },
  { week: 'Wk 3', premiums: 0, claims: 0 },
  { week: 'Wk 4', premiums: 0, claims: 0 },
  { week: 'Wk 5', premiums: 0, claims: 0 },
  { week: 'Wk 6', premiums: 0, claims: 0 },
  { week: 'Wk 7', premiums: 0, claims: 0 },
  { week: 'Wk 8', premiums: 0, claims: 0 },
];

export const FRAUD_QUEUE = [
  { id: 'WK-4821', zone: 'T Nagar',    trigger: 'Heavy Rain',        fps: 0.82, signals: ['GPS spoofed', 'Night shift mismatch', 'Duplicate device'], status: 'FLAGGED' as const },
  { id: 'WK-3109', zone: 'Velachery',  trigger: 'Platform Downtime', fps: 0.67, signals: ['IP mismatch', 'High velocity'],                          status: 'SOFT_HOLD' as const },
  { id: 'WK-7203', zone: 'Adyar',      trigger: 'Extreme Heat',      fps: 0.71, signals: ['Location outside zone', 'Claim during delivery'],        status: 'FLAGGED' as const },
  { id: 'WK-5518', zone: 'Perungudi',  trigger: 'Bandh / Curfew',    fps: 0.58, signals: ['NLP confidence low', 'Phone altitude anomaly'],          status: 'SOFT_HOLD' as const },
  { id: 'WK-6641', zone: 'Anna Nagar', trigger: 'Heavy Rain',        fps: 0.91, signals: ['Shared device ID', 'IMD zone mismatch', 'Rapid claims'], status: 'FLAGGED' as const },
  { id: 'WK-2987', zone: 'Tambaram',   trigger: 'Internet Blackout', fps: 0.44, signals: ['Signal strength borderline'],                            status: 'SOFT_HOLD' as const },
];

export type SimParams = {
  workers: number;
  days: number;
  pctBasic: number;
  pctStandard: number;
  pctFull: number;
  realizationRate: number;
};

export type SimResult = {
  grossExposure: number;
  adjustedPayout: number;
  weeklyPool: number;
  bcr: number;
  insurerRetention: number;
  reinsuranceRequired: number;
  needsReinsurance: boolean;
  status: 'SURVIVES' | 'STRESSED' | 'REINSURANCE REQUIRED' | 'COLLAPSE';
};

export function runSimulation(p: SimParams): SimResult {
  const basic    = p.workers * (p.pctBasic / 100);
  const standard = p.workers * (p.pctStandard / 100);
  const full     = p.workers * (p.pctFull / 100);

  const avgBasic    = Math.min(PLAN_CONFIG.basic.max_payout,    PLAN_CONFIG.basic.max_payout    * (p.days / 7));
  const avgStandard = Math.min(PLAN_CONFIG.standard.max_payout, PLAN_CONFIG.standard.max_payout * (p.days / 7));
  const avgFull     = Math.min(PLAN_CONFIG.full.max_payout,     PLAN_CONFIG.full.max_payout     * (p.days / 7));

  const grossExposure = (basic * avgBasic) + (standard * avgStandard) + (full * avgFull);
  const adjustedPayout = grossExposure * (p.realizationRate / 100);

  const totalWorkers = 10000;
  const weeklyPool = (totalWorkers * 0.30 * 35) + (totalWorkers * 0.50 * 49) + (totalWorkers * 0.20 * 79);

  const bcr = adjustedPayout / weeklyPool;
  const insurerRetention = weeklyPool * 2;
  const reinsuranceThreshold = weeklyPool * REINSURANCE_MULTIPLE;
  const reinsuranceRequired = Math.max(0, adjustedPayout - insurerRetention);
  const needsReinsurance = adjustedPayout > reinsuranceThreshold;

  let status: SimResult['status'];
  if (bcr < 0.85)    status = 'SURVIVES';
  else if (bcr < 1.5) status = 'STRESSED';
  else if (bcr < 2.5) status = 'REINSURANCE REQUIRED';
  else                status = 'COLLAPSE';

  return { grossExposure, adjustedPayout, weeklyPool, bcr: bcr * 100, insurerRetention, reinsuranceRequired, needsReinsurance, status };
}
