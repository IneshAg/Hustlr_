'use client';
import { createContext, useContext, useEffect, useMemo, useState, ReactNode } from 'react';
import AdminApiService from '@/lib/api-service';
import { fetchPoolSummary } from '@/lib/api';
import type { AdminAnalytics, FraudCase, PayoutRequest, SystemHealth } from '@/lib/mock-data';

interface AdminContextType {
  analytics: AdminAnalytics | null;
  systemHealth: SystemHealth | null;
  poolSummary: Awaited<ReturnType<typeof fetchPoolSummary>> | null;
  fraudHighlights: FraudCase[];
  payoutHighlights: PayoutRequest[];
  loading: boolean;
  errorMessage: string | null;
  lastRefresh: string;
  useMockData: boolean;
  autoRefreshEnabled: boolean;
  refreshEverySec: number;
  healthMeta: { healthyApis: number; totalApis: number; livePct: number; degraded: boolean };
  connectionLabel: { label: string; tone: string };
  toggleDataSource: () => void;
  setAutoRefreshEnabled: (val: boolean) => void;
  setRefreshEverySec: (val: number) => void;
  loadData: (showLoader?: boolean) => Promise<void>;
}

const AdminContext = createContext<AdminContextType | undefined>(undefined);

export function AdminProvider({ children }: { children: ReactNode }) {
  const [analytics, setAnalytics] = useState<AdminAnalytics | null>(null);
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null);
  const [poolSummary, setPoolSummary] = useState<Awaited<ReturnType<typeof fetchPoolSummary>> | null>(null);
  const [fraudHighlights, setFraudHighlights] = useState<FraudCase[]>([]);
  const [payoutHighlights, setPayoutHighlights] = useState<PayoutRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [useMockData, setUseMockData] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<string>('');
  const [autoRefreshEnabled, setAutoRefreshEnabled] = useState(true);
  const [refreshEverySec, setRefreshEverySec] = useState(30);

  useEffect(() => {
    AdminApiService.setUseMockData(useMockData);
    loadData();
  }, [useMockData]);

  useEffect(() => {
    if (!autoRefreshEnabled || refreshEverySec < 10) return;
    const timer = setInterval(() => { loadData(false); }, refreshEverySec * 1000);
    return () => clearInterval(timer);
  }, [autoRefreshEnabled, refreshEverySec, useMockData]);

  const loadData = async (showLoader = true) => {
    if (showLoader) setLoading(true);
    setErrorMessage(null);
    try {
      const [analyticsRes, healthRes, poolRes, fraudRes, payoutRes] = await Promise.allSettled([
        AdminApiService.getAnalytics(),
        AdminApiService.getSystemHealth(),
        fetchPoolSummary(),
        AdminApiService.getFraudQueue({ limit: 5, status: 'FLAGGED' }),
        AdminApiService.getPayoutQueue({ limit: 5, status: 'APPROVED' }),
      ]);

      // Core cards must load; queue widgets can degrade to empty lists.
      if (analyticsRes.status !== 'fulfilled' || healthRes.status !== 'fulfilled') {
        throw new Error('Core admin endpoints unavailable');
      }

      const analyticsData = analyticsRes.value;
      const healthData = healthRes.value;
      const poolData = poolRes.status === 'fulfilled' ? poolRes.value : null;
      const fraudData = fraudRes.status === 'fulfilled' ? fraudRes.value : [];
      const payoutData = payoutRes.status === 'fulfilled' ? payoutRes.value : [];

      setAnalytics(analyticsData);
      setSystemHealth(healthData);
      setPoolSummary(poolData);
      setFraudHighlights(fraudData);
      setPayoutHighlights(payoutData);
      setLastRefresh(new Date().toLocaleTimeString('en-IN'));
    } catch {
      setErrorMessage('Failed to load data');
    } finally {
      if (showLoader) setLoading(false);
    }
  };

  const toggleDataSource = () => {
    setUseMockData(!useMockData);
    AdminApiService.setUseMockData(!useMockData);
  };

  const healthMeta = useMemo(() => {
    if (!systemHealth) return { healthyApis: 0, totalApis: 0, livePct: 0, degraded: false };
    const apis = Array.isArray(systemHealth.apis) ? systemHealth.apis : [];
    const healthyApis = apis.filter((api) => api.ok).length;
    const totalApis = apis.length;
    const livePct = totalApis > 0 ? Math.round((healthyApis / totalApis) * 100) : 0;
    return { healthyApis, totalApis, livePct, degraded: healthyApis !== totalApis };
  }, [systemHealth]);

  const connectionLabel = useMemo(() => {
    if (!systemHealth) return { label: 'DISCONNECTED', tone: 'border-red-500/30 bg-red-500/10 text-red-200' };
    return healthMeta.degraded
      ? { label: 'DEGRADED', tone: 'border-amber-500/30 bg-amber-500/10 text-amber-200' }
      : { label: 'LIVE', tone: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200' };
  }, [healthMeta.degraded, systemHealth]);

  return (
    <AdminContext.Provider value={{
      analytics, systemHealth, poolSummary, fraudHighlights, payoutHighlights,
      loading, errorMessage, lastRefresh, useMockData, autoRefreshEnabled, refreshEverySec,
      healthMeta, connectionLabel, toggleDataSource, setAutoRefreshEnabled, setRefreshEverySec, loadData
    }}>
      {children}
    </AdminContext.Provider>
  );
}

export function useAdminData() {
  const ctx = useContext(AdminContext);
  if (!ctx) throw new Error('useAdminData must be used within AdminProvider');
  return ctx;
}
