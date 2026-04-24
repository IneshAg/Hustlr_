'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const ProfitSimulator = dynamic(() => import('@/components/tabs/ProfitSimulator'));

export default function PricingPage() {
  return (
    <div className="h-full">
      <CompactCard title="Plans & Pricing" accent="purple">
        <ProfitSimulator />
      </CompactCard>
    </div>
  );
}