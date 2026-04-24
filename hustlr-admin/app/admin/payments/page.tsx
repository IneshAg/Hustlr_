'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const PaymentQueue = dynamic(() => import('@/components/PaymentQueue'));

export default function PaymentsPage() {
  return (
    <div className="h-full">
      <CompactCard title="Payments" accent="orange">
        <PaymentQueue />
      </CompactCard>
    </div>
  );
}