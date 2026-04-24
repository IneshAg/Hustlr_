'use client';
import { CompactCard } from '@/components/AdminShared';
import dynamic from 'next/dynamic';
const ZoneHeatmap = dynamic(() => import('@/components/tabs/ZoneHeatmap'), { ssr: false });

export default function MapPage() {
  return (
    <div className="h-full">
      <CompactCard title="Live Risk Map" accent="red">
        <ZoneHeatmap />
      </CompactCard>
    </div>
  );
}