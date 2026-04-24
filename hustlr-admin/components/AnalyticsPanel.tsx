'use client';

import {
  AreaChart, Area, BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Line,
} from 'recharts';
import { TrendingUp, TrendingDown, BarChart2, Loader2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { AdminAnalytics } from '@/lib/mock-data';

const NEON = {
  cyan:    '#7dd3fc',
  violet:  '#a78bfa',
  amber:   '#f59e0b',
  red:     '#ef4444',
  emerald: '#22c55e',
};

const TOOLTIP_STYLE = {
  backgroundColor: '#161616',
  border: '1px solid #2d2d2d',
  borderRadius: '10px',
  fontSize: '12px',
  color: '#9ca3af',
};
const TOOLTIP_LABEL  = { color: '#e4e4e7' };
const TOOLTIP_ITEM   = { color: '#9ca3af' };
const TOOLTIP_CURSOR = { fill: 'rgba(255,255,255,0.02)' };

function fmt(n: number) { return `₹${n.toLocaleString('en-IN')}`; }
function fmtDate(d: string) {
  if (!d) return '';
  // If already in short form like "Apr 5" return as-is
  if (/^[A-Za-z]{3}\s\d{1,2}/.test(d)) return d;
  try {
    const dt = new Date(d);
    if (isNaN(dt.getTime())) return d;
    return dt.toLocaleDateString('en-IN', { month: 'short', day: 'numeric' });
  } catch { return d; }
}

interface Props { analytics: AdminAnalytics | null; }

export default function AnalyticsPanel({ analytics }: Props) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loader2 className="h-5 w-5 animate-spin text-[#7dd3fc]" />
      </div>
    );
  }

  if (!analytics) {
    return (
      <div className="rounded-xl border border-[#2d2d2d] bg-[#161616] px-5 py-10 text-center">
        <p className="text-sm text-[#555]">No analytics data available</p>
      </div>
    );
  }

  const { summary, claimsTimeline, triggerBreakdown, severityBuckets } = analytics;
  const flaggedPct = summary.totalClaims > 0
    ? Math.round((summary.flaggedClaims / summary.totalClaims) * 100)
    : 0;

  const severityData = [
    { name: 'Low',    value: severityBuckets.low },
    { name: 'Medium', value: severityBuckets.medium },
    { name: 'High',   value: severityBuckets.high },
  ].filter(d => d.value > 0);

  const triggerData = triggerBreakdown.map(t => ({
    ...t,
    label: t.type.charAt(0).toUpperCase() + t.type.slice(1),
  }));

  const PIE_COLORS = [NEON.cyan, NEON.amber, NEON.violet];

  const summaryCards = [
    { label: 'Total Claims', value: summary.totalClaims.toString(), sub: `${summary.flaggedClaims} flagged`, color: 'text-white', accent: 'bg-[#262626] text-[#666]' },
    { label: 'Payouts', value: fmt(summary.totalPayout), sub: 'parametric', color: 'text-[#7dd3fc]', accent: 'bg-[#7dd3fc]/10 text-[#7dd3fc]' },
    { label: 'Premiums', value: fmt(summary.totalPremium), sub: 'collected', color: 'text-[#a78bfa]', accent: 'bg-[#a78bfa]/10 text-[#a78bfa]' },
    {
      label: 'Loss Ratio',
      value: `${summary.lossRatio.toFixed(1)}%`,
      sub: summary.lossRatio > 80 ? 'Above threshold' : 'Within range',
      color: summary.lossRatio > 80 ? 'text-[#f59e0b]' : 'text-[#22c55e]',
      accent: summary.lossRatio > 80 ? 'bg-[#f59e0b]/10 text-[#f59e0b]' : 'bg-[#22c55e]/10 text-[#22c55e]',
    },
    { label: 'Flagged %', value: `${flaggedPct}%`, sub: `${summary.flaggedClaims} of ${summary.totalClaims}`, color: summary.flaggedClaims > 0 ? 'text-[#f59e0b]' : 'text-[#22c55e]', accent: summary.flaggedClaims > 0 ? 'bg-[#f59e0b]/10 text-[#f59e0b]' : 'bg-[#22c55e]/10 text-[#22c55e]' },
  ];

  return (
    <div className="space-y-5">
      {/* Summary strip */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {summaryCards.map(s => (
          <div key={s.label} className="bg-[#161616] border border-[#2d2d2d] rounded-xl px-4 py-4 flex flex-col items-center text-center gap-2">
            <p className="text-[10px] font-semibold text-[#555] uppercase tracking-widest truncate w-full">{s.label}</p>
            <p className={`text-xl font-bold tabular-nums ${s.color}`}>{s.value}</p>
            <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${s.accent}`}>{s.sub}</span>
          </div>
        ))}
      </div>

      {/* Claims & Payouts over time */}
      <div className="bg-[#161616] border border-[#2d2d2d] rounded-xl p-5">
        <div className="flex items-center gap-2.5 mb-5">
          <TrendingUp className="h-4 w-4 text-[#7dd3fc]" />
          <p className="text-sm font-semibold text-white">Claims &amp; Payouts</p>
          <span className="text-[10px] text-[#666] ml-auto">Last 30 days</span>
        </div>
        {claimsTimeline.length === 0 ? (
          <p className="text-sm text-[#555] text-center py-8">No data yet</p>
        ) : (
          <>
            <div className="min-w-0 w-full" style={{ height: 200 }}>
              <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                <AreaChart data={claimsTimeline} margin={{ top: 4, right: 0, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="payoutG" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%"  stopColor={NEON.cyan}   stopOpacity={0.18} />
                      <stop offset="95%" stopColor={NEON.cyan}   stopOpacity={0}    />
                    </linearGradient>
                    <linearGradient id="claimG" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%"  stopColor={NEON.violet} stopOpacity={0.18} />
                      <stop offset="95%" stopColor={NEON.violet} stopOpacity={0}    />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2d2d2d" vertical={false} />
                  <XAxis dataKey="date" tickFormatter={fmtDate} tick={{ fill: '#666', fontSize: 10 }} axisLine={false} tickLine={false} />
                  <YAxis yAxisId="p" orientation="right" tick={{ fill: '#666', fontSize: 10 }} axisLine={false} tickLine={false} tickFormatter={v => `₹${v}`} />
                  <YAxis yAxisId="c" tick={{ fill: '#666', fontSize: 10 }} axisLine={false} tickLine={false} />
                  <Tooltip
                    contentStyle={TOOLTIP_STYLE} labelStyle={TOOLTIP_LABEL} itemStyle={TOOLTIP_ITEM} cursor={TOOLTIP_CURSOR}
                    formatter={(v, n) => n === 'payout' ? [fmt(Number(v)), 'Payout'] : [v, 'Claims']}
                    labelFormatter={l => fmtDate(String(l))}
                  />
                  <Area yAxisId="p" type="monotone" dataKey="payout"  stroke={NEON.cyan}   fill="url(#payoutG)" strokeWidth={1.5} dot={false} />
                  <Area yAxisId="c" type="monotone" dataKey="claims"  stroke={NEON.violet} fill="url(#claimG)"  strokeWidth={1.5} dot={false} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
            <div className="flex items-center gap-4 mt-3 pt-3 border-t border-[#2d2d2d]">
              <div className="flex items-center gap-1.5"><span className="h-px w-6 bg-[#7dd3fc] inline-block" /><span className="text-[10px] text-[#666]">Payouts</span></div>
              <div className="flex items-center gap-1.5"><span className="h-px w-6 bg-[#a78bfa] inline-block" /><span className="text-[10px] text-[#666]">Claims</span></div>
            </div>
          </>
        )}
      </div>

      {/* Loss ratio + trigger breakdown */}
      <div className="grid lg:grid-cols-2 gap-4">
        {/* Loss ratio bar */}
        <div className="bg-[#161616] border border-[#2d2d2d] rounded-xl p-5">
          <div className="flex items-center gap-2.5 mb-5">
            {summary.lossRatio > 80
              ? <TrendingUp  className="h-4 w-4 text-[#f59e0b]" />
              : <TrendingDown className="h-4 w-4 text-[#22c55e]" />}
            <p className="text-sm font-semibold text-white">Loss Ratio by Trigger</p>
          </div>
          {triggerData.length === 0 ? (
            <p className="text-sm text-[#555] text-center py-8">No events yet</p>
          ) : (
            <div className="min-w-0 w-full" style={{ height: 180 }}>
              <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                <BarChart data={triggerData} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2d2d2d" vertical={false} />
                  <XAxis dataKey="label" tick={{ fill: '#666', fontSize: 10 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: '#666', fontSize: 10 }} axisLine={false} tickLine={false} />
                  <Tooltip contentStyle={TOOLTIP_STYLE} labelStyle={TOOLTIP_LABEL} itemStyle={TOOLTIP_ITEM} cursor={TOOLTIP_CURSOR} formatter={v => [v, 'Events']} />
                  <Bar dataKey="count" radius={[3, 3, 0, 0]} maxBarSize={36} opacity={0.85}>
                    {triggerData.map((_, i) => (
                      <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                    ))}
                  </Bar>
                  {/* 80% threshold reference */}
                  <Line type="monotone" dataKey={() => 80} stroke={NEON.red} strokeDasharray="4 4" strokeWidth={1} dot={false} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </div>

        {/* Severity donut */}
        <div className="bg-[#161616] border border-[#2d2d2d] rounded-xl p-5">
          <div className="flex items-center gap-2.5 mb-5">
            <BarChart2 className="h-4 w-4 text-[#666]" />
            <p className="text-sm font-semibold text-white">Severity Distribution</p>
          </div>
          {severityData.length === 0 ? (
            <p className="text-sm text-[#555] text-center py-8">No data</p>
          ) : (
            <div className="flex items-center justify-around">
              <div className="min-w-0 w-[55%]" style={{ height: 180 }}>
                <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                  <PieChart>
                    <Pie data={severityData} cx="50%" cy="50%" innerRadius={42} outerRadius={68} dataKey="value" strokeWidth={0}>
                      {severityData.map((_, i) => (
                        <Cell key={i} fill={i === 0 ? NEON.cyan : i === 1 ? NEON.amber : NEON.violet} opacity={0.85} />
                      ))}
                    </Pie>
                    <Tooltip contentStyle={TOOLTIP_STYLE} labelStyle={TOOLTIP_LABEL} itemStyle={TOOLTIP_ITEM} formatter={(v, n) => [v, n]} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              <div className="space-y-2">
                {severityData.map((d, i) => (
                  <div key={d.name} className="flex items-center gap-2 text-xs text-[#9ca3af]">
                    <span className="w-2.5 h-2.5 rounded-full inline-block" style={{ background: i === 0 ? NEON.cyan : i === 1 ? NEON.amber : NEON.violet }} />
                    <span>{d.name}</span>
                    <span className="ml-auto font-semibold text-white">{d.value}</span>
                  </div>
                ))}
                <div className="pt-2 border-t border-[#2d2d2d] text-[11px] text-[#555]">
                  Total: {severityData.reduce((a,b)=>a+b.value,0)}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
