import MockAdminDataService, {
  AdminAnalytics,
  FraudCase,
  AdminUser,
  SystemHealth,
  PayoutRequest,
  AdminPolicy,
} from './mock-data';
import { API_BASE } from './constants';

const BASE_URL = `${API_BASE}/api/admin`;

class AdminApiService {
  static useMockData = false;

  private static normalizeFraudCase(raw: any): FraudCase {
    return {
      id: String(raw?.id ?? ''),
      userId: String(raw?.userId ?? raw?.user_id ?? ''),
      userName: String(raw?.userName ?? raw?.user?.name ?? 'Unknown User'),
      userPhone: String(raw?.userPhone ?? raw?.user?.phone ?? ''),
      trustScore: Number(raw?.trustScore ?? raw?.user?.trust_score ?? 0),
      trustTier: String(raw?.trustTier ?? raw?.user?.trust_tier ?? 'SILVER'),
      policyId: String(raw?.policyId ?? raw?.policy_id ?? ''),
      planTier: String(raw?.planTier ?? raw?.policy?.plan_tier ?? 'standard'),
      weeklyPremium: Number(raw?.weeklyPremium ?? raw?.policy?.weekly_premium ?? 0),
      fraudStatus: String(raw?.fraudStatus ?? raw?.fraud_status ?? raw?.status ?? 'FLAGGED'),
      fraudScore: Number(raw?.fraudScore ?? raw?.fraud_score ?? raw?.riskScore ?? 0),
      triggerType: String(raw?.triggerType ?? raw?.trigger_type ?? 'unknown'),
      zone: String(raw?.zone ?? ''),
      city: String(raw?.city ?? ''),
      severity: Number(raw?.severity ?? 0),
      grossPayout: Number(raw?.grossPayout ?? raw?.gross_payout ?? raw?.amount ?? 0),
      createdAt: new Date(raw?.createdAt ?? raw?.created_at ?? raw?.date ?? Date.now()),
      fraudSignals: Array.isArray(raw?.fraudSignals)
        ? raw.fraudSignals
        : Array.isArray(raw?.fraud_signal_logs)
          ? raw.fraud_signal_logs.map((s: any) => ({
              name: String(s?.signal_name ?? s?.name ?? 'signal'),
              value: Number(s?.signal_value ?? s?.value ?? 0),
              weight: Number(s?.weight_applied ?? s?.weight ?? 0),
              contribution: Number(s?.score_contribution ?? s?.contribution ?? 0),
            }))
          : [],
      reason: String(raw?.reason ?? 'No reason provided'),
    };
  }

  private static normalizePayout(raw: any): PayoutRequest {
    return {
      id: String(raw?.id ?? ''),
      claimId: String(raw?.claimId ?? raw?.claim_id ?? raw?.id ?? ''),
      userId: String(raw?.userId ?? raw?.user_id ?? ''),
      userName: String(raw?.userName ?? raw?.user?.name ?? 'Unknown User'),
      userPhone: String(raw?.userPhone ?? raw?.user?.phone ?? ''),
      amount: Number(raw?.amount ?? raw?.gross_payout ?? 0),
      status: String(raw?.status ?? 'APPROVED'),
      paymentMethod: String(raw?.paymentMethod ?? 'UPI'),
      upiRef: raw?.upiRef ?? raw?.upi_ref,
      createdAt: new Date(raw?.createdAt ?? raw?.created_at ?? raw?.date ?? Date.now()),
      processedAt: raw?.processedAt || raw?.processed_at
        ? new Date(raw?.processedAt ?? raw?.processed_at)
        : undefined,
    };
  }

  private static normalizeAdminUser(raw: any): AdminUser {
    const claimsCount =
      Number(raw?.claimsCount) ||
      Number(raw?.claims_count) ||
      (Array.isArray(raw?.claims) ? raw.claims.length : 0) ||
      Number(raw?.totalClaims) ||
      0;

    return {
      id: String(raw?.id ?? ''),
      name: String(raw?.name ?? 'Unknown'),
      phone: String(raw?.phone ?? raw?.userPhone ?? ''),
      zone: String(raw?.zone ?? ''),
      city: String(raw?.city ?? ''),
      trustScore: Number(raw?.trustScore ?? raw?.trust_score ?? 0),
      trustTier: String(raw?.trustTier ?? raw?.trust_tier ?? raw?.tier ?? 'SILVER'),
      cleanWeeks: Number(raw?.cleanWeeks ?? raw?.clean_weeks ?? 0),
      cashbackEarned: Number(raw?.cashbackEarned ?? raw?.cashback_earned ?? 0),
      cashbackPending: Number(raw?.cashbackPending ?? raw?.cashback_pending ?? 0),
      activePolicy: Boolean(raw?.activePolicy ?? raw?.active_policy ?? (raw?.activePolicies ?? 0) > 0),
      policyTier: String(raw?.policyTier ?? raw?.policy_tier ?? raw?.planTier ?? raw?.tier ?? 'NONE'),
      weeklyPremium: Number(raw?.weeklyPremium ?? raw?.weekly_premium ?? 0),
      claimsCount,
      lastClaimDate: raw?.lastClaimDate || raw?.last_claim_date
        ? new Date(raw?.lastClaimDate ?? raw?.last_claim_date)
        : undefined,
      kycStatus: String(raw?.kycStatus ?? raw?.kyc_status ?? 'pending'),
      createdAt: new Date(raw?.createdAt ?? raw?.created_at ?? Date.now()),
    };
  }

  static setUseMockData(useMock: boolean) {
    AdminApiService.useMockData = useMock;
  }

  static async getAnalytics(): Promise<AdminAnalytics> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 800));
      return MockAdminDataService.getAnalytics();
    }

    try {
      const response = await fetch(`${BASE_URL}/analytics`, {
        headers: { 'Content-Type': 'application/json' },
      });
      
      if (response.ok) {
        const data = await response.json();
        return data as AdminAnalytics;
      }
      throw new Error(`Failed to load analytics: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async getFraudQueue(options: {
    page?: number;
    limit?: number;
    status?: string;
  } = {}): Promise<FraudCase[]> {
    const { page = 1, limit = 20, status = 'FLAGGED' } = options;

    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return MockAdminDataService.getFraudQueue(limit);
    }

    try {
      const response = await fetch(
        `${BASE_URL}/fraud-queue?page=${page}&limit=${limit}&status=${status}`,
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );

      if (response.ok) {
        const data = await response.json();
        return (Array.isArray(data?.claims) ? data.claims : []).map((c: any) =>
          AdminApiService.normalizeFraudCase(c),
        );
      }
      throw new Error(`Failed to load fraud queue: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async getUsers(options: {
    page?: number;
    limit?: number;
    search?: string;
    tier?: string;
  } = {}): Promise<AdminUser[]> {
    const { page = 1, limit = 50, search, tier } = options;

    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return MockAdminDataService.getUsers(limit);
    }

    try {
      let queryParams = `page=${page}&limit=${limit}`;
      if (search) queryParams += `&search=${search}`;
      if (tier) queryParams += `&tier=${tier}`;

      const response = await fetch(
        `${BASE_URL}/trust-scores?${queryParams}`,
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );

      if (response.ok) {
        const data = await response.json();
        return (Array.isArray(data.users) ? data.users : []).map((u: any) =>
          AdminApiService.normalizeAdminUser(u),
        );
      }
      throw new Error(`Failed to load users: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async getSystemHealth(): Promise<SystemHealth> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 300));
      return MockAdminDataService.getSystemHealth();
    }

    try {
      const response = await fetch(`${BASE_URL}/system-health`, {
        headers: { 'Content-Type': 'application/json' },
      });

      if (response.ok) {
        const data = await response.json();
        return data as SystemHealth;
      }
      throw new Error(`Failed to load system health: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async getPayoutQueue(options: {
    page?: number;
    limit?: number;
    status?: string;
  } = {}): Promise<PayoutRequest[]> {
    const { page = 1, limit = 20, status = 'APPROVED' } = options;

    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return MockAdminDataService.getPayoutQueue(limit);
    }

    try {
      const response = await fetch(
        `${BASE_URL}/payout-queue?page=${page}&limit=${limit}&status=${status}`,
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );

      if (response.ok) {
        const data = await response.json();
        return (Array.isArray(data?.payouts) ? data.payouts : []).map((p: any) =>
          AdminApiService.normalizePayout(p),
        );
      }
      throw new Error(`Failed to load payout queue: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async getPolicies(options: {
    page?: number;
    limit?: number;
    status?: string;
  } = {}): Promise<AdminPolicy[]> {
    const { page = 1, limit = 30, status } = options;

    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return MockAdminDataService.getPolicies(limit);
    }

    try {
      let queryParams = `page=${page}&limit=${limit}`;
      if (status) queryParams += `&status=${status}`;

      const response = await fetch(
        `${BASE_URL}/policies?${queryParams}`,
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );

      if (response.ok) {
        const data = await response.json();
        return (data.policies || []) as AdminPolicy[];
      }
      throw new Error(`Failed to load policies: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      throw e;
    }
  }

  static async updateFraudStatus(
    claimId: string,
    status: string,
    note?: string
  ): Promise<boolean> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 300));
      return true;
    }

    try {
      const response = await fetch(`${BASE_URL}/fraud/${claimId}/status`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status, adminNote: note }),
      });

      return response.ok;
    } catch (e) {
      console.error('API Error:', e);
      return false;
    }
  }

  static async updateTrustScore(
    userId: string,
    score: number,
    reason?: string
  ): Promise<boolean> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 300));
      return true;
    }

    try {
      const response = await fetch(`${BASE_URL}/trust/${userId}/score`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ score, reason }),
      });

      return response.ok;
    } catch (e) {
      console.error('API Error:', e);
      return false;
    }
  }

  static async processPayout(
    payoutId: string,
    paymentMethod: string,
    upiRef?: string
  ): Promise<boolean> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return true;
    }

    try {
      const response = await fetch(`${BASE_URL}/payout/${payoutId}/process`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ paymentMethod, upiRef }),
      });

      return response.ok;
    } catch (e) {
      console.error('API Error:', e);
      return false;
    }
  }

  static async runAdjudicator(): Promise<{
    success: boolean;
    claimsCreated?: number;
    durationMs?: number;
    error?: string;
  }> {
    if (AdminApiService.useMockData) {
      await new Promise(resolve => setTimeout(resolve, 2000));
      return {
        success: true,
        claimsCreated: Math.floor(Math.random() * 50) + 10,
        durationMs: Math.floor(Math.random() * 5000) + 1000,
      };
    }

    try {
      const response = await fetch(`${BASE_URL}/run-adjudicator`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      });

      if (response.ok) {
        const data = await response.json();
        return data;
      }
      throw new Error(`Failed to run adjudicator: ${response.status}`);
    } catch (e) {
      console.error('API Error:', e);
      return {
        success: false,
        error: e instanceof Error ? e.message : 'Unknown error',
      };
    }
  }
}

export default AdminApiService;
