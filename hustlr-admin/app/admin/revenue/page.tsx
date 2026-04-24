'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const Financials = dynamic(() => import('@/components/tabs/Financials'));

export default function RevenuePage() {
  return (
    <div className="h-full">
      <CompactCard title="Revenue & Loss" accent="blue">
        <Financials />
      </CompactCard>
    </div>
  );
}