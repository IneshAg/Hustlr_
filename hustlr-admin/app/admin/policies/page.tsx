'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const PolicyManagement = dynamic(() => import('@/components/PolicyManagement'));

export default function PoliciesPage() {
  return (
    <div className="h-full">
      <CompactCard title="Policies" accent="green">
        <PolicyManagement />
      </CompactCard>
    </div>
  );
}