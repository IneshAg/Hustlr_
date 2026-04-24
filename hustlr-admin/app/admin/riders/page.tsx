'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const UserManagement = dynamic(() => import('@/components/UserManagement'));

export default function RidersPage() {
  return (
    <div className="h-full">
      <CompactCard title="Riders" accent="blue">
        <UserManagement />
      </CompactCard>
    </div>
  );
}