'use client';
import { useEffect, useRef } from 'react';
import { useStressStore } from '@/lib/store';
import { SliderRow } from '@/components/ui';
import { fmt, bcrColor } from '@/lib/utils';
import { SimParams } from '@/lib/constants';
import { useAdminData } from '@/components/AdminContext';

const PRESETS: Array<{ label: string; emoji: string } & Partial<SimParams>> = [
  { label: 'Cyclone Michaung', emoji: '🌀', workers: 8000, days: 4, realizationRate: 80, pctBasic: 30, pctStandard: 50, pctFull: 20 },
  { label: '3-Day Monsoon',    emoji: '🌧', workers: 6000, days: 3, realizationRate: 75, pctBasic: 40, pctStandard: 45, pctFull: 15 },
  { label: 'Platform Outage',  emoji: '📱', workers: 4000, days: 1, realizationRate: 90, pctBasic: 20, pctStandard: 60, pctFull: 20 },
];

const STATUS_STYLES = {
  'SURVIVES':             { bg: 'rgba(63,255,139,0.08)',  border: 'rgba(63,255,139,0.35)',  text: '#3FFF8B', icon: '✓' },
  'STRESSED':             { bg: 'rgba(255,152,0,0.08)',   border: 'rgba(255,152,0,0.35)',   text: '#FF9800', icon: '⚠' },
  'REINSURANCE REQUIRED': { bg: 'rgba(33,150,243,0.08)',  border: 'rgba(33,150,243,0.35)',  text: '#2196F3', icon: '🔁' },
  'COLLAPSE':             { bg: 'rgba(226,75,74,0.08)',   border: 'rgba(226,75,74,0.35)',   text: '#E24B4A', icon: '✗' },
};

export default function StressSimulator() {
  const { analytics, poolSummary } = useAdminData();
  const { params, result, computing, setParam, loadPreset } = useStressStore();
  const seededFromLiveRef = useRef(false);
  const planSum = params.pctBasic + params.pctStandard + params.pctFull;
  const sc = result ? STATUS_STYLES[result.status] : null;

  useEffect(() => {
    if (seededFromLiveRef.current) return;
    const totalPremium = Number(analytics?.summary?.totalPremium ?? 0);
    const totalPayout = Number(analytics?.summary?.totalPayout ?? 0);
    const activePolicies = Number(poolSummary?.activePolicies ?? 0);
    if (totalPremium <= 0) return;

    const inferredRealization = Math.max(
      50,
      Math.min(100, Math.round((totalPayout / totalPremium) * 100)),
    );

    loadPreset({
      workers: activePolicies > 0 ? activePolicies : params.workers,
      realizationRate: inferredRealization,
    });
    seededFromLiveRef.current = true;
  }, [analytics?.summary, poolSummary?.activePolicies, loadPreset, params.workers]);

  return (
    <div className="space-y-6">
      {/* Preset buttons */}
      <div className="flex gap-3 flex-wrap">
        {PRESETS.map(p => (
          <button
            key={p.label}
            onClick={() => loadPreset(p)}
            className="px-4 py-2 rounded-xl border text-sm font-bold transition-all"
            style={{
              background: 'rgba(255,255,255,0.04)',
              borderColor: 'rgba(255,255,255,0.12)',
              color: '#E1E3DE',
            }}
            onMouseEnter={e => {
              (e.target as HTMLElement).style.borderColor = 'rgba(63,255,139,0.5)';
              (e.target as HTMLElement).style.color = '#3FFF8B';
            }}
            onMouseLeave={e => {
              (e.target as HTMLElement).style.borderColor = 'rgba(255,255,255,0.12)';
              (e.target as HTMLElement).style.color = '#E1E3DE';
            }}
          >
            {p.emoji} {p.label}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Sliders */}
        <div className="card p-6 space-y-6">
          <p className="text-xs font-bold tracking-widest uppercase" style={{ color: '#91938D' }}>
            STORM PARAMETERS
          </p>
          <SliderRow
            label="Workers Affected" value={params.workers} min={0} max={10000} step={100}
            format={v => `${v.toLocaleString('en-IN')} workers`}
            onChange={v => setParam('workers', v)}
          />
          <SliderRow
            label="Event Duration" value={params.days} min={1} max={7}
            format={v => `${v} day${v > 1 ? 's' : ''}`}
            onChange={v => setParam('days', v)}
          />
          <SliderRow
            label="Payout Realization Rate" value={params.realizationRate} min={50} max={100}
            format={v => `${v}%`}
            onChange={v => setParam('realizationRate', v)}
          />

          <div className="pt-4 border-t space-y-4" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
            <p className="text-xs font-bold" style={{ color: planSum !== 100 ? '#FF9800' : 'rgba(255,255,255,0.28)' }}>
              PLAN MIX — must sum to 100% (currently {planSum}%)
              {planSum !== 100 && ' ⚠'}
            </p>
            <SliderRow label="Basic %"    value={params.pctBasic}    min={0} max={100} format={v => `${v}%`} onChange={v => setParam('pctBasic', v)} />
            <SliderRow label="Standard %" value={params.pctStandard} min={0} max={100} format={v => `${v}%`} onChange={v => setParam('pctStandard', v)} />
            <SliderRow label="Full %"     value={params.pctFull}     min={0} max={100} format={v => `${v}%`} onChange={v => setParam('pctFull', v)} />
          </div>
        </div>

        {/* Live outputs */}
        <div className="space-y-4">
          {result && sc && (
            <>
              {/* Status card */}
              <div
                className="p-5 rounded-2xl border"
                style={{ background: sc.bg, borderColor: sc.border }}
              >
                <div className="flex items-center gap-3 mb-2">
                  <span className="text-2xl">{sc.icon}</span>
                  <span className="text-xl font-black" style={{ color: sc.text }}>
                    {result.status}
                    {computing && <span className="ml-2 text-sm font-normal opacity-50">computing…</span>}
                  </span>
                </div>
                <p className="text-sm" style={{ color: 'rgba(255,255,255,0.45)' }}>
                  {result.status === 'SURVIVES'             && 'Pool absorbs the event within operating envelope.'}
                  {result.status === 'STRESSED'             && 'BCR breaches 85% — circuit breaker trips, new enrollment halted.'}
                  {result.status === 'REINSURANCE REQUIRED' && 'Event exceeds 4× weekly pool. Reinsurance layer activates.'}
                  {result.status === 'COLLAPSE'             && 'Catastrophic exposure — reinsurance insufficient. Regulatory intervention required.'}
                </p>
              </div>

              {/* Output rows */}
              {[
                { label: 'Gross Payout Exposure',   value: fmt(result.grossExposure),   color: '#E1E3DE' },
                { label: 'Post-Filter Adjusted',     value: fmt(result.adjustedPayout),   color: '#E24B4A' },
                { label: 'Weekly Pool Inflow',       value: fmt(result.weeklyPool),       color: '#3FFF8B' },
                { label: 'Event BCR',                value: `${result.bcr.toFixed(1)}%`, color: bcrColor(result.bcr) },
                { label: 'Insurer Retention (2×)',   value: fmt(result.insurerRetention), color: '#FF9800' },
                {
                  label: 'Reinsurance Required',
                  value: result.needsReinsurance ? fmt(result.reinsuranceRequired) : '—',
                  color: result.needsReinsurance ? '#2196F3' : '#3FFF8B',
                  badge: result.needsReinsurance ? 'ACTIVATED' : 'NOT REQUIRED',
                  badgeCls: result.needsReinsurance ? 'badge-blue' : 'badge-green',
                },
              ].map(o => (
                <div key={o.label} className="card-sm px-4 py-3 flex items-center justify-between">
                  <span className="text-xs font-semibold" style={{ color: 'rgba(255,255,255,0.38)' }}>{o.label}</span>
                  <div className="flex items-center gap-2">
                    <span className="font-black text-sm" style={{ color: o.color }}>{o.value}</span>
                    {o.badge && <span className={o.badgeCls}>{o.badge}</span>}
                  </div>
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
