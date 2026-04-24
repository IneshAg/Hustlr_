'use client';
import { useEffect, useMemo, useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, PieChart, Pie, Cell,
} from 'recharts';
import { BCRGauge } from '@/components/BCRGauge';
import { MetricCard } from '@/components/ui';
import { useAdminData } from '@/components/AdminContext';
import AdminApiService from '@/lib/api-service';
import type { AdminPolicy } from '@/lib/mock-data';
import { PLAN_CONFIG, WEEKLY_HISTORY } from '@/lib/constants';
import { fmt, bcrColor } from '@/lib/utils';

interface Props {
  pool: { weeklyPool: number; bcr: number; activePolicies: number; reserve: number; circuitBreakerTripped: boolean } | null;
  loading: boolean;
}

export default function PoolHealth({ pool, loading }: Props) {
  const { analytics, useMockData, lastRefresh } = useAdminData();
  const [policies, setPolicies] = useState<AdminPolicy[]>([]);

  useEffect(() => {
    let alive = true;
    AdminApiService.getPolicies({ limit: 300 })
      .then((res) => {
        if (alive) setPolicies(Array.isArray(res) ? res : []);
      })
      .catch(() => {
        if (alive) setPolicies([]);
      });
    return () => {
      alive = false;
    };
  }, [useMockData, lastRefresh]);

  const bcr     = pool?.bcr ?? 0;
  const weekly  = pool?.weeklyPool ?? 0;
  const active  = pool?.activePolicies ?? 0;
  const reserve = pool?.reserve ?? 0;
  const tripped = pool?.circuitBreakerTripped ?? false;

  const weeklyHistory = useMemo(() => {
    const premiums = analytics?.premiumsTimeline || [];
    const losses = analytics?.lossRatioTimeline || [];
    if (premiums.length === 0) return WEEKLY_HISTORY;

    const lossByWeek = new Map(losses.map((l) => [l.week, l.payout]));
    return premiums.map((p, idx) => ({
      week: p.week || `Wk ${idx + 1}`,
      premiums: Number(p.amount ?? 0),
      claims: Number(lossByWeek.get(p.week) ?? 0),
    }));
  }, [analytics?.premiumsTimeline, analytics?.lossRatioTimeline]);

  const planBuckets = useMemo(() => {
    const buckets = {
      basic: { count: 0, weeklyPremium: 0 },
      standard: { count: 0, weeklyPremium: 0 },
      full: { count: 0, weeklyPremium: 0 },
    };

    for (const p of policies) {
      const tier = String((p as any).planTier || (p as any).plan_tier || '').toLowerCase();
      const weeklyPremium = Number((p as any).weeklyPremium ?? (p as any).weekly_premium ?? 0);
      if (tier.includes('basic')) {
        buckets.basic.count += 1;
        buckets.basic.weeklyPremium += weeklyPremium;
      } else if (tier.includes('full')) {
        buckets.full.count += 1;
        buckets.full.weeklyPremium += weeklyPremium;
      } else {
        buckets.standard.count += 1;
        buckets.standard.weeklyPremium += weeklyPremium;
      }
    }

    return buckets;
  }, [policies]);

  const totalPolicies = planBuckets.basic.count + planBuckets.standard.count + planBuckets.full.count;
  const planDist = totalPolicies > 0
    ? [
        { name: 'Basic', value: Math.round((planBuckets.basic.count / totalPolicies) * 100), color: '#3FFF8B66' },
        { name: 'Standard', value: Math.round((planBuckets.standard.count / totalPolicies) * 100), color: '#3FFF8B' },
        { name: 'Full', value: Math.round((planBuckets.full.count / totalPolicies) * 100), color: '#3FFF8BCC' },
      ]
    : [
        { name: 'Basic', value: 30, color: '#3FFF8B66' },
        { name: 'Standard', value: 50, color: '#3FFF8B' },
        { name: 'Full', value: 20, color: '#3FFF8BCC' },
      ];

  const planRows = [
    {
      key: 'basic' as const,
      pct: planDist[0].value,
      workers: totalPolicies > 0 ? planBuckets.basic.count : 3000,
    },
    {
      key: 'standard' as const,
      pct: planDist[1].value,
      workers: totalPolicies > 0 ? planBuckets.standard.count : 5000,
    },
    {
      key: 'full' as const,
      pct: planDist[2].value,
      workers: totalPolicies > 0 ? planBuckets.full.count : 2000,
    },
  ];

  return (
    <div className="space-y-6">
      {/* Metric row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard label="Weekly Pool" value={fmt(weekly)} sub={`${active.toLocaleString('en-IN')} active policies`} loading={loading} />
        <MetricCard label="Current BCR" value={`${bcr.toFixed(1)}%`} sub="85% = circuit breaker threshold" color={bcrColor(bcr)} loading={loading} />
        <MetricCard label="Active Policies" value={active.toLocaleString('en-IN')} sub="Across 6 Chennai zones" loading={loading} />
        <MetricCard label="Reserve Fund" value={fmt(reserve)} sub="2× weekly pool maintained" color="#2196F3" loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* BCR Gauge */}
        <div className="card p-6 flex flex-col items-center gap-4">
          <p className="text-xs font-bold tracking-widest uppercase self-start" style={{ color: '#91938D' }}>BCR GAUGE</p>
          <BCRGauge bcr={bcr} />
          <div className={`flex items-center gap-2 px-4 py-2 rounded-full border text-xs font-black ${
            tripped
              ? 'border-red-500/40 bg-red-500/10 text-red-400'
              : 'border-emerald-500/40 bg-emerald-500/10 text-emerald-400'
          }`}>
            <span className={`w-2 h-2 rounded-full ${tripped ? 'bg-red-400 pulse-red' : 'bg-emerald-400 pulse-green'}`} />
            CIRCUIT BREAKER {tripped ? 'OPEN — HALTED' : 'CLOSED — OPEN'}
          </div>
        </div>

        {/* Bar chart */}
        <div className="card p-6 lg:col-span-2">
          <p className="text-xs font-bold tracking-widest uppercase mb-4" style={{ color: '#91938D' }}>
            WEEKLY PREMIUMS vs CLAIMS (8 WEEKS)
          </p>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={weeklyHistory} barGap={4}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
              <XAxis dataKey="week" tick={{ fill: '#91938D', fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fill: '#91938D', fontSize: 10 }} axisLine={false} tickLine={false}
                tickFormatter={v => `₹${(v / 1000).toFixed(0)}K`} />
              <Tooltip
                contentStyle={{ background: '#111311', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8 }}
                labelStyle={{ color: '#E1E3DE' }}
                formatter={(value) => [fmt(typeof value === 'number' ? value : Number(value ?? 0)), 'Amount']}
              />
              <Legend wrapperStyle={{ fontSize: 12, color: '#91938D' }} />
              <Bar dataKey="premiums" name="Premiums" fill="#3FFF8B" radius={[4,4,0,0]} />
              <Bar dataKey="claims"   name="Claims"   fill="#E24B4A88" radius={[4,4,0,0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Plan distribution */}
      <div className="card p-6">
        <p className="text-xs font-bold tracking-widest uppercase mb-6" style={{ color: '#91938D' }}>PLAN DISTRIBUTION</p>
        <div className="flex flex-col lg:flex-row items-center gap-8">
          <PieChart width={200} height={200}>
            <Pie data={planDist} cx={100} cy={100} innerRadius={55} outerRadius={90} paddingAngle={3} dataKey="value">
              {planDist.map((e, i) => <Cell key={i} fill={e.color} />)}
            </Pie>
            <Tooltip
              contentStyle={{ background: '#111311', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8 }}
              formatter={(value) => [`${Number(value ?? 0)}%`, 'Share']}
            />
          </PieChart>

          <div className="flex-1 w-full space-y-4">
            {planRows.map(row => {
              const cfg = PLAN_CONFIG[row.key];
              return (
                <div key={row.key} className="card-sm p-4">
                  <div className="flex items-center justify-between mb-3">
                    <span className="font-bold text-sm">{cfg.name}</span>
                    <div className="flex gap-2">
                      <span className="badge-green">₹{cfg.base}/wk</span>
                      <span className="badge-blue">Cap ₹{cfg.max_payout}</span>
                      <span className="badge-amber">{cfg.multiplier}×</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="flex-1 bg-white/5 rounded-full h-2">
                      <div className="h-full rounded-full" style={{ width: `${row.pct}%`, background: '#3FFF8B' }} />
                    </div>
                    <span className="text-sm font-black w-10 text-right" style={{ color: '#3FFF8B' }}>{row.pct}%</span>
                    <span className="text-xs w-28" style={{ color: 'rgba(255,255,255,0.35)' }}>{row.workers.toLocaleString('en-IN')} workers</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
