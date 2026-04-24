'use client';
import { HeartPulse } from 'lucide-react';
import { useAdminData } from '@/components/AdminContext';
import { CompactCard, MiniStat } from '@/components/AdminShared';
import type { SystemHealth } from '@/lib/mock-data';

function SystemHealthPanel({
  systemHealth, healthMeta, totalClaims, flaggedClaims,
}: {
  systemHealth: SystemHealth | null;
  healthMeta: { healthyApis: number; totalApis: number; livePct: number; degraded: boolean };
  totalClaims: number;
  flaggedClaims: number;
}) {
  if (!systemHealth) return null;
  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-white/10 bg-black/20 p-4">
        <div className="flex items-center justify-between gap-3">
          <h4 className="text-sm font-semibold text-white">System Monitoring</h4>
          <span className={`rounded-full border px-3 py-1 text-xs font-semibold ${healthMeta.degraded ? 'border-amber-500/20 bg-amber-500/10 text-amber-200' : 'border-emerald-500/20 bg-emerald-500/10 text-emerald-200'}`}>
            {healthMeta.degraded ? 'DEGRADED' : 'OPERATIONAL'}
          </span>
        </div>
        <p className="mt-2 text-sm text-white/45">
          {healthMeta.healthyApis}/{healthMeta.totalApis} services healthy, {healthMeta.livePct}% live.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          {systemHealth.apis.map((api) => (
            <span key={api.name} className={`rounded-full border px-2.5 py-1 text-xs ${api.ok ? 'border-emerald-500/20 bg-emerald-500/10 text-emerald-200' : 'border-red-500/20 bg-red-500/10 text-red-200'}`}>
              {api.name}
            </span>
          ))}
        </div>
      </div>
      <div className="rounded-xl border border-white/10 bg-black/20 p-4">
        <h4 className="text-sm font-semibold text-white">Live Queue Snapshot</h4>
        <div className="mt-3 space-y-2 text-sm text-white/70">
          <p>Flagged cases: {flaggedClaims}</p>
          <p>Total claims tracked: {totalClaims}</p>
          <p>Last adjudicator run: {systemHealth.lastAdjudicatorRun ? `${systemHealth.lastAdjudicatorRun.durationMs}ms` : '—'}</p>
          <p>24h errors: {systemHealth.errors24h}</p>
        </div>
      </div>
    </div>
  );
}

export default function HealthPage() {
  const { systemHealth, healthMeta, analytics } = useAdminData();
  const totalClaims = Number(analytics?.summary?.totalClaims ?? 0);
  const flaggedClaims = Number(analytics?.summary?.flaggedClaims ?? 0);
  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <CompactCard title="System Health" accent="blue">
        <SystemHealthPanel
          systemHealth={systemHealth}
          healthMeta={healthMeta}
          totalClaims={totalClaims}
          flaggedClaims={flaggedClaims}
        />
      </CompactCard>
      <div >
        <CompactCard title="API Live Rate" accent="emerald">
          <MiniStat icon={<HeartPulse className="h-4 w-4" />} label="API Live Rate" value={`${healthMeta.livePct}%`} tone="emerald" />
        </CompactCard>
      </div>
    </div>
  );
}