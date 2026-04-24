import { API_BASE, ML_API_BASE } from './constants';

export type PoolHealth = {
  city: string;
  total_premium: number;
  total_claims_paid: number;
  loss_ratio: number;
};

export type ApiHealth = {
  api_health: Record<string, { ok: boolean; source?: string }>;
  checked_at: string;
};

export type Claim = {
  id: string;
  user_id: string;
  trigger_type: string;
  zone: string;
  status: string;
  gross_payout: number;
  fraud_score: number;
  fraud_status: string;
  created_at: string;
  fps_signals?: Record<string, unknown>;
};

export type RiskPool = {
  id?: string;
  city?: string;
  zone?: string;
  risk_type?: string;
  loss_ratio?: number;
  bcr?: number;
  claims_count?: number;
  active_policies?: number;
};

// Render free-tier cold starts can take up to 60 s — retry with backoff
async function apiFetch<T>(path: string, init?: RequestInit, retries = 2): Promise<T> {
  const TIMEOUT_MS = 65_000; // 65 s covers Render cold-start window
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await fetch(`${API_BASE}${path}`, {
        ...init,
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      return res.json();
    } catch (err) {
      if (attempt === retries) throw err;
      // Wait 3 s between retries
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  throw new Error('unreachable');
}

/** GET /disruptions/health/apis — no auth required */
export async function fetchApiHealth(): Promise<ApiHealth> {
  return apiFetch<ApiHealth>('/disruptions/health/apis');
}

/** Aggregate pool health across zones by querying disruption data.
 *  Backend doesn't expose a public admin aggregate endpoint, so we
 *  use the API health check plus known Supabase structure. */
export async function fetchPoolSummary(): Promise<{
  weeklyPool: number;
  bcr: number;
  activePolicies: number;
  reserve: number;
  circuitBreakerTripped: boolean;
}> {
  try {
    const data = await apiFetch<any>('/api/admin/pool-summary');
    return {
      weeklyPool: Number(data.weeklyPool ?? 0),
      bcr: Number(data.bcr ?? 0),
      activePolicies: Number(data.activePolicies ?? 0),
      reserve: Number(data.reserve ?? 0),
      circuitBreakerTripped: Boolean(data.circuitBreakerTripped ?? false),
    };
  } catch (err) {
    console.error('Failed to fetch pool summary:', err);
    return {
      weeklyPool: 0,
      bcr: 0,
      activePolicies: 0,
      reserve: 0,
      circuitBreakerTripped: false,
    };
  }
}

/** GET /disruptions/:zone — live disruption status per zone */
export async function fetchZoneDisruption(zone: string) {
  return apiFetch<{
    active: boolean;
    disruptions: Array<{ trigger_type: string; display_name: string }>;
    weather?: { temp_celsius: number; rainfall_mm_1h: number };
  }>(`/disruptions/${encodeURIComponent(zone)}`);
}

/** ML GET /forecast/:zone — Python FastAPI Prophet endpoint */
export async function fetchProphetForecast(zoneId: string, days: number = 7) {
  for (let attempt = 0; attempt <= 2; attempt++) {
    try {
      const res = await fetch(`${ML_API_BASE}/forecast/${encodeURIComponent(zoneId)}?days=${days}`, {
        signal: AbortSignal.timeout(65_000),
        headers: { 'Content-Type': 'application/json' },
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      return res.json();
    } catch (err) {
      if (attempt === 2) throw err;
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
}

/** ML GET /fraud/model-health — Python FastAPI model diagnostic endpoint */
export async function fetchFraudModelHealth() {
  for (let attempt = 0; attempt <= 2; attempt++) {
    try {
      const res = await fetch(`${ML_API_BASE}/fraud/model-health`, {
        signal: AbortSignal.timeout(65_000),
        headers: { 'Content-Type': 'application/json' },
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      return res.json();
    } catch (err) {
      if (attempt === 2) throw err;
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
}

/** GET /api/admin/risk-pools — admin route used for live zone risk view */
export async function fetchRiskPools(): Promise<RiskPool[]> {
  const data = await apiFetch<{ pools?: RiskPool[] } | RiskPool[]>('/api/admin/risk-pools');
  if (Array.isArray(data)) return data;
  return Array.isArray(data?.pools) ? data.pools : [];
}
