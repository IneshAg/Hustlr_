'use client';
import { useState, useMemo, useEffect, useRef } from 'react';
import { MetricCard, SliderRow } from '@/components/ui';
import { fmt, bcrColor } from '@/lib/utils';
import { PieChart, Pie, Cell, ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts';
import { AlertCircle } from 'lucide-react';
import { useAdminData } from '@/components/AdminContext';
import AdminApiService from '@/lib/api-service';

type LivePremiums = { basic: number; standard: number; full: number };

export default function ProfitSimulator() {
  const { analytics, poolSummary } = useAdminData();
  // Inputs
  const [workers, setWorkers] = useState(10000);
  const [lossRatio, setLossRatio] = useState(0.40); // 40%
  const [fraudReduc, setFraudReduc] = useState(0.09); // 9%
  const [zones, setZones] = useState('all');
  const [premiums, setPremiums] = useState<LivePremiums>({
    basic: 35,
    standard: 49,
    full: 79,
  });
  
  // Plan mix
  const [pctBasic, setPctBasic] = useState(20);
  const [pctStandard, setPctStandard] = useState(50);
  const [pctFull, setPctFull] = useState(30);

  const rebalancePlanMix = (changed: 'basic' | 'standard' | 'full', rawValue: number) => {
    const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
    const next = {
      basic: pctBasic,
      standard: pctStandard,
      full: pctFull,
    };

    next[changed] = clamp(Math.round(rawValue), 0, 100);
    const keys: Array<'basic' | 'standard' | 'full'> = ['basic', 'standard', 'full'];
    const others = keys.filter((k) => k !== changed);
    const remaining = 100 - next[changed];
    const currentOtherTotal = next[others[0]] + next[others[1]];

    if (currentOtherTotal <= 0) {
      next[others[0]] = remaining;
      next[others[1]] = 0;
    } else {
      const scaledFirst = Math.round((next[others[0]] / currentOtherTotal) * remaining);
      next[others[0]] = clamp(scaledFirst, 0, remaining);
      next[others[1]] = remaining - next[others[0]];
    }

    setPctBasic(next.basic);
    setPctStandard(next.standard);
    setPctFull(next.full);
  };

  const planSum = pctBasic + pctStandard + pctFull;

  // Constants
  const MGA_FEE = 0.08;
  const PLATFORM_FEE_PER_WORKER = 150;
  const REINSURANCE_ALLOCATION = 0.02;
  const FIXED_COSTS = 50000;

  // Stress State
  const [isStressed, setIsStressed] = useState(false);
  const seededFromLiveRef = useRef(false);

  useEffect(() => {
    let alive = true;
    AdminApiService.getPolicies({ limit: 300 })
      .then((rows) => {
        if (!alive || !Array.isArray(rows) || rows.length === 0) return;

        const sums = { basic: 0, standard: 0, full: 0 };
        const counts = { basic: 0, standard: 0, full: 0 };

        for (const p of rows as any[]) {
          const tier = String(p?.planTier ?? p?.plan_tier ?? '').toLowerCase();
          const wp = Number(p?.weeklyPremium ?? p?.weekly_premium ?? 0);
          if (!Number.isFinite(wp) || wp <= 0) continue;
          if (tier.includes('basic')) {
            sums.basic += wp;
            counts.basic += 1;
          } else if (tier.includes('full')) {
            sums.full += wp;
            counts.full += 1;
          } else {
            sums.standard += wp;
            counts.standard += 1;
          }
        }

        setPremiums((prev) => ({
          basic: counts.basic > 0 ? Math.round(sums.basic / counts.basic) : prev.basic,
          standard:
            counts.standard > 0 ? Math.round(sums.standard / counts.standard) : prev.standard,
          full: counts.full > 0 ? Math.round(sums.full / counts.full) : prev.full,
        }));
      })
      .catch(() => undefined);

    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    if (seededFromLiveRef.current) return;
    const totalPremium = Number(analytics?.summary?.totalPremium ?? 0);
    const totalPayout = Number(analytics?.summary?.totalPayout ?? 0);
    const activePolicies = Number(poolSummary?.activePolicies ?? 0);
    if (totalPremium <= 0) return;

    setWorkers(activePolicies);
    setLossRatio(Math.max(0.25, Math.min(0.95, totalPayout / totalPremium)));

    const flagged = Number(analytics?.summary?.flaggedClaims ?? 0);
    const totalClaims = Number(analytics?.summary?.totalClaims ?? 0);
    const inferredFraudCut = totalClaims > 0 ? Math.min(0.25, Math.max(0.05, (flagged / totalClaims) * 0.3)) : 0.09;
    setFraudReduc(inferredFraudCut);

    seededFromLiveRef.current = true;
  }, [analytics?.summary, poolSummary?.activePolicies]);

  const activeLossRatio = isStressed ? 0.85 : lossRatio;

  // Math
  const blendedWeeklyPremium = (
    (premiums.basic * (pctBasic / 100)) +
    (premiums.standard * (pctStandard / 100)) +
    (premiums.full * (pctFull / 100))
  );

  const monthlyPremiumPool = workers * blendedWeeklyPremium * 4.33;
  const mgaRevenue = monthlyPremiumPool * MGA_FEE;
  const platformRevenue = workers * PLATFORM_FEE_PER_WORKER;
  const totalHustlrRev = mgaRevenue + platformRevenue;

  const estimatedClaimsOutflow = monthlyPremiumPool * activeLossRatio * (1 - fraudReduc);
  const bcr = estimatedClaimsOutflow / monthlyPremiumPool;
  
  const underwritingMargin = 1 - activeLossRatio - MGA_FEE - REINSURANCE_ALLOCATION;

  // Break-even: totalHustlrRev = mgaRevenue(workers) + platformRev(workers) = FIXED_COSTS
  // mgaRevenue(w) = w * blendedWeeklyPremium * 4.33 * 0.08
  // w * (blendedWeeklyPremium * 4.33 * 0.08 + 150) = 50000
  const breakEvenWorkers = Math.ceil(FIXED_COSTS / ((blendedWeeklyPremium * 4.33 * MGA_FEE) + PLATFORM_FEE_PER_WORKER));

  // Chart Data
  const chartData = useMemo(() => {
    return [10000, 25000, 50000, 75000, 100000].map(w => {
      const pPool = w * blendedWeeklyPremium * 4.33;
      return {
        workers: w.toLocaleString('en-IN'),
        revenue: Math.round((pPool * MGA_FEE) + (w * PLATFORM_FEE_PER_WORKER)),
        pool: Math.round(pPool)
      };
    });
  }, [blendedWeeklyPremium]);

  const runStressTest = () => {
    setIsStressed(true);
    setTimeout(() => setIsStressed(false), 5000);
  };

  return (
    <div className="space-y-6 pb-20">
      
      {isStressed && (
        <div className="bg-blue-500/10 border border-blue-500/30 p-4 rounded-xl flex items-start gap-4 animate-in fade-in slide-in-from-top-4">
          <AlertCircle className="text-blue-400 shrink-0 mt-0.5" />
          <div>
            <h3 className="text-blue-400 font-bold text-sm uppercase tracking-widest">Catastrophic Event Simulated</h3>
            <p className="text-white/60 text-sm mt-1">Loss ratio spiked to 85%. Circuit breaker tripped to halt new enrollment. Reinsurance clause activated as pool exposure hit 400% weekly limit.</p>
          </div>
        </div>
      )}

      {/* Top Metrics row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard label="Monthly Premium Pool" value={`₹${fmt(Math.round(monthlyPremiumPool))}`} sub="Gross actuarial inflow" color="#E1E3DE" />
        <MetricCard label="Hustlr Total Revenue" value={`₹${fmt(Math.round(totalHustlrRev))}`} sub="MGA + Licensing Fees" color="#3FFF8B" />
        <MetricCard label="Underwriting Margin" value={`${(underwritingMargin * 100).toFixed(1)}%`} sub="Gross insurer profit" color={underwritingMargin > 0 ? '#3FFF8B' : '#E24B4A'} />
        <MetricCard label="Break-Even Scale" value={`${breakEvenWorkers.toLocaleString('en-IN')}`} sub="Workers needed for ₹50k fixed cost" color="#2196F3" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        
        {/* Left Column: Inputs */}
        <div className="lg:col-span-5 space-y-6">
          <div className="card p-6 space-y-6">
            <div className="flex justify-between items-center">
              <p className="text-xs font-bold tracking-widest uppercase" style={{ color: '#91938D' }}>
                SCALE & RISK ASSUMPTIONS
              </p>
              <button 
                onClick={runStressTest}
                disabled={isStressed}
                className="text-[10px] font-bold px-3 py-1.5 rounded bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 uppercase transition-all whitespace-nowrap"
              >
                Stress Test ⚡
              </button>
            </div>
            
            <SliderRow label="Active Worker Pool" value={workers} min={100} max={50000} step={100} format={v => v.toLocaleString('en-IN')} onChange={setWorkers} />
            <SliderRow label="Base Loss Ratio" value={lossRatio * 100} min={25} max={75} format={v => `${v}%`} onChange={v => !isStressed && setLossRatio(v / 100)} />
            <SliderRow label="Fraud Filter Efficacy" value={fraudReduc * 100} min={0} max={25} format={v => `-${v}% Leakage`} onChange={v => setFraudReduc(v / 100)} />
            
            <div className="space-y-2">
              <label className="text-xs font-bold uppercase tracking-widest text-[#91938D] block mb-1">Geographical Mix</label>
              <select value={zones} onChange={e => setZones(e.target.value)} className="w-full bg-white/5 border border-white/10 rounded-lg p-2.5 text-sm outline-none font-bold text-white/80">
                <option value="chennai" className="bg-[#161B22] text-white" style={{ color: '#111827', backgroundColor: '#FFFFFF' }}>Chennai (High Flood Risk)</option>
                <option value="all" className="bg-[#161B22] text-white" style={{ color: '#111827', backgroundColor: '#FFFFFF' }}>Chennai + Bengaluru (Blended)</option>
                <option value="pan" className="bg-[#161B22] text-white" style={{ color: '#111827', backgroundColor: '#FFFFFF' }}>Pan-India Tier 1 Focus</option>
              </select>
            </div>
            
            <div className="pt-4 border-t space-y-4" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
              <p className="text-xs font-bold uppercase tracking-widest" style={{ color: planSum !== 100 ? '#FF9800' : '#91938D' }}>
                Plan Distribution {planSum !== 100 && `(Must sum to 100, currently ${planSum})`}
              </p>
              <SliderRow
                label={`Basic (₹${premiums.basic})`}
                value={pctBasic}
                min={0}
                max={100}
                format={v => `${v}%`}
                onChange={(v) => rebalancePlanMix('basic', v)}
              />
              <SliderRow
                label={`Standard (₹${premiums.standard})`}
                value={pctStandard}
                min={0}
                max={100}
                format={v => `${v}%`}
                onChange={(v) => rebalancePlanMix('standard', v)}
              />
              <SliderRow
                label={`Full Shield (₹${premiums.full})`}
                value={pctFull}
                min={0}
                max={100}
                format={v => `${v}%`}
                onChange={(v) => rebalancePlanMix('full', v)}
              />
            </div>
          </div>
        </div>

        {/* Right Column: Dynamic Outputs */}
        <div className="lg:col-span-7 space-y-6">
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* BCR Gauge */}
            <div className="card p-6 flex flex-col items-center justify-center">
              <p className="text-xs font-bold tracking-widest uppercase mb-4 w-full text-left" style={{ color: '#91938D' }}>
                Live Benefit-Cost Ratio (BCR)
              </p>
              <div className="relative w-40 h-40">
                <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                  <PieChart>
                    <Pie
                      data={[ { value: bcr }, { value: 1 - bcr > 0 ? 1 - bcr : 0 } ]}
                      cx="50%" cy="50%"
                      innerRadius={60} outerRadius={80}
                      startAngle={180} endAngle={0}
                      dataKey="value"
                      stroke="none"
                    >
                      <Cell fill={bcr > 0.85 ? '#E24B4A' : bcr > 0.65 ? '#FF9800' : '#3FFF8B'} />
                      <Cell fill="rgba(255,255,255,0.05)" />
                    </Pie>
                  </PieChart>
                </ResponsiveContainer>
                <div className="absolute inset-0 flex flex-col items-center justify-end pb-8">
                  <span className="text-3xl font-black" style={{ color: bcr > 0.85 ? '#E24B4A' : bcr > 0.65 ? '#FF9800' : '#3FFF8B' }}>
                    {(bcr * 100).toFixed(1)}%
                  </span>
                  <span className="text-[10px] uppercase font-bold text-white/30 mt-1">
                    {bcr > 0.85 ? 'Critical' : bcr > 0.65 ? 'Elevated' : 'Healthy'}
                  </span>
                </div>
              </div>
            </div>

            {/* Breakdown Stack */}
            <div className="card p-6 space-y-5">
               <p className="text-xs font-bold tracking-widest uppercase" style={{ color: '#91938D' }}>
                Monthly Ledger
              </p>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-white/50 font-medium">Claims Outflow</span>
                  <span className="font-bold text-red-400">₹{fmt(Math.round(estimatedClaimsOutflow))}</span>
                </div>
                <div className="w-full bg-white/5 h-2 rounded overflow-hidden">
                  <div className="bg-red-400/80 h-full" style={{ width: `${Math.min(100, bcr * 100)}%` }}></div>
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-white/50 font-medium">Hustlr MGA Fee (8%)</span>
                  <span className="font-bold text-emerald-400">₹{fmt(Math.round(mgaRevenue))}</span>
                </div>
                <div className="w-full bg-white/5 h-2 rounded overflow-hidden">
                  <div className="bg-emerald-400/80 h-full" style={{ width: `8%` }}></div>
                </div>
              </div>

              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-white/50 font-medium">Platform Licensing</span>
                  <span className="font-bold text-[#2196F3]">₹{fmt(Math.round(platformRevenue))}</span>
                </div>
                <div className="w-full bg-white/5 h-2 rounded overflow-hidden">
                  <div className="bg-[#2196F3]/80 h-full" style={{ width: `100%` }}></div>
                </div>
              </div>
            </div>
          </div>

          <div className="card p-6 border" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
            <p className="text-xs font-bold tracking-widest uppercase mb-6" style={{ color: '#91938D' }}>
              Hustlr Revenue Scale Projection
            </p>
            <div className="h-60 w-full">
              <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                <LineChart data={chartData} margin={{ top: 5, right: 20, bottom: 5, left: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                  <XAxis dataKey="workers" tick={{ fill: 'rgba(255,255,255,0.3)', fontSize: 10 }} tickLine={false} axisLine={false} />
                  <YAxis 
                    tick={{ fill: 'rgba(255,255,255,0.3)', fontSize: 10 }} 
                    tickLine={false} axisLine={false} 
                    tickFormatter={val => `₹${(val/100000).toFixed(1)}L`}
                  />
                  <Tooltip 
                    contentStyle={{ backgroundColor: '#0A0B0A', borderColor: 'rgba(255,255,255,0.1)', borderRadius: 8 }}
                    itemStyle={{ color: '#3FFF8B', fontWeight: 'bold' }}
                    formatter={(value) => [`₹${fmt(typeof value === 'number' ? value : Number(value ?? 0))}`, 'Revenue']}
                    labelStyle={{ color: 'rgba(255,255,255,0.5)', marginBottom: 4 }}
                  />
                  <Line type="monotone" dataKey="revenue" stroke="#3FFF8B" strokeWidth={3} dot={{ fill: '#0A0B0A', stroke: '#3FFF8B', strokeWidth: 2, r: 4 }} activeDot={{ r: 6 }} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}
