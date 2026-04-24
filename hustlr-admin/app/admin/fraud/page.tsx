'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const FraudQueue = dynamic(() => import('@/components/FraudQueue'));

export default function FraudPage() {
  return (
    <div className="h-full">
      <CompactCard title="Fraud Queue" accent="red">
        <FraudQueue />
      </CompactCard>
    </div>
  );
}