'use client';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Cell, ResponsiveContainer, LineChart, Line, AreaChart, Area } from 'recharts';
import { ZONES } from '@/lib/constants';
import { bcrColor, riskBadge } from '@/lib/utils';
import { fetchProphetForecast, fetchRiskPools, fetchZoneDisruption } from '@/lib/api';
import { useState, useEffect } from 'react';
import dynamic from 'next/dynamic';
import { useAdminData } from '@/components/AdminContext';

const H3RiskMap = dynamic(() => import('@/components/H3RiskMap'), { ssr: false });

type ZoneView = {
  name: string;
  workers: number;
  risk: 'LOW' | 'MEDIUM' | 'HIGH';
  disruption: boolean;
  bcr: number;
  claims_today: number;
  trigger: string;
};

const toRiskBand = (bcr: number): 'LOW' | 'MEDIUM' | 'HIGH' => {
  if (bcr >= 70) return 'HIGH';
  if (bcr >= 50) return 'MEDIUM';
  return 'LOW';
};

export default function ZoneHeatmap() {
  const { analytics } = useAdminData();
  const [prophetData, setProphetData] = useState<any[]>([]);
  const [prophetLoading, setProphetLoading] = useState(true);
  const [zones, setZones] = useState<ZoneView[]>(
    ZONES.map((z) => ({ ...z, trigger: z.disruption ? 'Disruption' : 'None' })),
  );

  useEffect(() => {
    let alive = true;

    const hydrateLiveZones = async () => {
      const fallback = ZONES.map((z) => ({
        ...z,
        trigger: z.disruption ? 'Disruption' : 'None',
      }));

      try {
        const pools = await fetchRiskPools();
        const byName = new Map(
          pools
            .filter((p) => p && (p.zone || p.city))
            .map((p) => [String(p.zone || p.city), p]),
        );

        const disruptions = await Promise.all(
          ZONES.map(async (z) => {
            try {
              const d = await fetchZoneDisruption(z.name);
              return {
                name: z.name,
                active: Boolean(d?.active),
                trigger:
                  d?.disruptions?.[0]?.display_name ||
                  d?.disruptions?.[0]?.trigger_type ||
                  'None',
              };
            } catch {
              return { name: z.name, active: z.disruption, trigger: z.disruption ? 'Disruption' : 'None' };
            }
          }),
        );

        const disruptionByName = new Map(disruptions.map((d) => [d.name, d]));

        const liveZones: ZoneView[] = ZONES.map((z) => {
          const pool = byName.get(z.name) || byName.get('Chennai');
          const disruption = disruptionByName.get(z.name);
          const bcr = Number(pool?.loss_ratio ?? pool?.bcr ?? 0);
          return {
            ...z,
            bcr,
            risk: toRiskBand(bcr),
            disruption: disruption?.active ?? false,
            trigger: disruption?.trigger ?? 'None',
            claims_today: Number(pool?.claims_count ?? 0),
            workers: Number(pool?.active_policies ?? 0),
          };
        });

        if (alive) setZones(liveZones);
      } catch {
        if (alive) setZones(fallback);
      }
    };

    hydrateLiveZones();
    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    if (!analytics?.summary?.totalClaims) return;
    const total = analytics.summary.totalClaims;
    if (total <= 0) return;
    setZones((prev) => {
      const baseline = prev.reduce((acc, z) => acc + z.claims_today, 0);
      if (baseline <= 0) return prev;
      return prev.map((z) => ({
        ...z,
        claims_today: Math.max(0, Math.round((z.claims_today / baseline) * total)),
      }));
    });
  }, [analytics?.summary?.totalClaims]);

  useEffect(() => {
    fetchProphetForecast('Adyar Dark Store Zone', 7)
      .then(res => setProphetData(res.forecasts || []))
      .catch(console.error)
      .finally(() => setProphetLoading(false));
  }, []);
  return (
    <div className="space-y-6">
      <div className="card p-2 bg-black overflow-hidden shadow-[0_0_30px_rgba(63,255,139,0.05)] border-emerald-500/20">
        <H3RiskMap zones={zones.map((z) => ({ name: z.name, risk: z.bcr, claims: z.claims_today, trigger: z.trigger, workers: z.workers }))} />
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {zones.map(z => (
          <div key={z.name} className="card p-5 space-y-4">
            <div className="flex items-start justify-between">
              <div>
                <h3 className="font-black text-base">{z.name}</h3>
                <p className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,0.35)' }}>
                  {z.workers.toLocaleString('en-IN')} active workers
                </p>
              </div>
              <span className={riskBadge(z.risk)}>{z.risk} RISK</span>
            </div>

            {/* BCR bar */}
            <div>
              <div className="flex justify-between mb-1.5">
                <span className="text-xs" style={{ color: 'rgba(255,255,255,0.35)' }}>Zone BCR</span>
                <span className="text-xs font-bold" style={{ color: bcrColor(z.bcr) }}>{z.bcr}%</span>
              </div>
              <div className="w-full rounded-full h-2" style={{ background: 'rgba(255,255,255,0.07)' }}>
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{ width: `${z.bcr}%`, background: bcrColor(z.bcr) }}
                />
              </div>
              {z.bcr >= 85 && (
                <p className="text-xs font-bold mt-1.5" style={{ color: '#E24B4A' }}>⚠ Circuit Breaker OPEN</p>
              )}
            </div>

            <div className="flex items-center justify-between">
              {/* Disruption pill */}
              <div className={`flex items-center gap-2 px-3 py-1.5 rounded-full border ${
                z.disruption
                  ? 'bg-amber-500/10 border-amber-500/30'
                  : 'bg-emerald-500/10 border-emerald-500/30'
              }`}>
                <span className={`w-1.5 h-1.5 rounded-full ${z.disruption ? 'bg-amber-400 pulse-red' : 'bg-emerald-400'}`} />
                <span className={`text-xs font-bold ${z.disruption ? 'text-amber-400' : 'text-emerald-400'}`}>
                  {z.disruption ? 'DISRUPTION ACTIVE' : 'CLEAR'}
                </span>
              </div>
              {/* Claims today */}
              <div className="text-right">
                <p className="text-xl font-black">{z.claims_today}</p>
                <p className="text-xs" style={{ color: 'rgba(255,255,255,0.35)' }}>claims today</p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Bar chart */}
      <div className="card p-6">
        <p className="text-xs font-bold tracking-widest uppercase mb-4" style={{ color: '#91938D' }}>
          CLAIMS FILED TODAY — BY ZONE
        </p>
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={zones.map(z => ({ name: z.name, claims: z.claims_today, bcr: z.bcr }))}>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
            <XAxis dataKey="name" tick={{ fill: '#91938D', fontSize: 11 }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fill: '#91938D', fontSize: 10 }} axisLine={false} tickLine={false} />
            <Tooltip
              contentStyle={{ background: '#111311', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8 }}
              labelStyle={{ color: '#E1E3DE' }}
            />
            <Bar dataKey="claims" name="Claims Today" radius={[4,4,0,0]}>
              {zones.map((z, i) => <Cell key={i} fill={bcrColor(z.bcr)} />)}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Prophet Forecasting API Chart */}
      <div className="card p-6 border-emerald-500/30 shadow-[0_0_30px_rgba(63,255,139,0.05)]">
        <div className="flex justify-between items-start mb-6">
          <div>
            <h3 className="font-black text-lg text-emerald-400">Prophet AI: 7-Day Forecasting</h3>
            <p className="text-sm text-white/50">Predicting heavy rain probability for Adyar Dark Store Zone.</p>
          </div>
        <div className="flex items-center gap-3">
          {prophetLoading ? (
            <span className="text-xs text-white/40 animate-pulse border border-white/10 px-2 py-1 rounded">⚙️ Computing ML Vectors...</span>
          ) : prophetData.length > 0 ? (
            <span className="text-xs font-bold text-emerald-400 border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 rounded">✅ API Native (0ms)</span>
          ) : (
            <span className="text-xs font-bold text-red-400 border border-red-500/30 bg-red-500/10 px-2 py-1 rounded">❌ API Offline</span>
          )}
        </div>
        </div>
        
        {prophetData.length > 0 ? (
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={prophetData}>
              <defs>
                <linearGradient id="colorRisk" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3FFF8B" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="#3FFF8B" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
              <XAxis dataKey="date" tick={{ fill: '#91938D', fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis domain={[0, 1]} tick={{ fill: '#91938D', fontSize: 10 }} axisLine={false} tickLine={false} tickFormatter={val => `${val*100}%`} />
              <Tooltip
                contentStyle={{ background: '#111311', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8 }}
              />
              <Area type="monotone" dataKey="disruption_probability" name="Rain Risk" stroke="#3FFF8B" fillOpacity={1} fill="url(#colorRisk)" />
            </AreaChart>
          </ResponsiveContainer>
        ) : !prophetLoading && (
          <div className="text-center text-white/30 text-sm py-10">No Prophet dataset found. Try reloading to trigger cold start training.</div>
        )}
      </div>
    </div>
  );
}
