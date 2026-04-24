'use client';
import { Database, DollarSign, Briefcase, TrendingUp } from 'lucide-react';
import { useAdminData } from '@/components/AdminContext';
import { MetricCard, CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const AnalyticsPanel = dynamic(() => import('@/components/AnalyticsPanel'));

export default function OverviewPage() {
  const { analytics } = useAdminData();
  return (
    <div className="space-y-6">
      <section className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard title="Total Claims" value={analytics?.summary.totalClaims.toString() ?? '0'} subtitle={`${analytics?.summary.flaggedClaims ?? 0} flagged`} icon={<Database className="h-5 w-5" />} tone="blue" />
        <MetricCard title="Total Payouts" value={`₹${((analytics?.summary.totalPayout ?? 0) / 100000).toFixed(1)}L`} subtitle="Last 30 days" icon={<DollarSign className="h-5 w-5" />} tone="green" />
        <MetricCard title="Premiums" value={`₹${((analytics?.summary.totalPremium ?? 0) / 100000).toFixed(1)}L`} subtitle="Collected" icon={<Briefcase className="h-5 w-5" />} tone="purple" />
        <MetricCard title="Loss Ratio" value={`${analytics?.summary.lossRatio.toFixed(1) ?? 0}%`} subtitle={(analytics?.summary.lossRatio ?? 0) > 80 ? 'High' : 'Normal'} icon={<TrendingUp className="h-5 w-5" />} tone={(analytics?.summary.lossRatio ?? 0) > 80 ? 'orange' : 'green'} />
      </section>
      <div className="h-full">
        <CompactCard title="Analytics" accent="emerald">
          {analytics && <AnalyticsPanel analytics={analytics} />}
        </CompactCard>
      </div>
    </div>
  );
}