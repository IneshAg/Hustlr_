'use client';
import { useAdminData } from '@/components/AdminContext';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const PoolHealth = dynamic(() => import('@/components/tabs/PoolHealth'));
const StressSimulator = dynamic(() => import('@/components/tabs/StressSimulator'));

export default function ReservesPage() {
  const { poolSummary } = useAdminData();
  return (
    <div className="space-y-6">
      <CompactCard title="Reserves & Stress" accent="emerald">
        <PoolHealth pool={poolSummary} loading={false} />
      </CompactCard>
      <CompactCard title="Stress Tests" accent="orange">
        <StressSimulator />
      </CompactCard>
    </div>
  );
}