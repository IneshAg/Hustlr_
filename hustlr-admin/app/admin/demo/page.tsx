'use client';
import { PlugZap } from 'lucide-react';
import { useAdminData } from '@/components/AdminContext';
import { CompactCard } from '@/components/AdminShared';

export default function DemoPage() {
  const { useMockData, toggleDataSource, autoRefreshEnabled, setAutoRefreshEnabled, refreshEverySec, setRefreshEverySec } = useAdminData();
  return (
    <div className="h-full">
      <CompactCard title="Demo Controls" accent="purple">
        <div className="space-y-4">
          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <p className="text-sm font-semibold text-white">Data Source</p>
            <p className="mt-1 text-xs text-white/45">Switch between mock and connected data.</p>
            <button
              onClick={toggleDataSource}
              className="mt-3 inline-flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm font-semibold text-white/80 hover:bg-white/10"
            >
              <PlugZap className="h-4 w-4" />
              {useMockData ? 'Demo' : 'Live'}
            </button>
          </div>

          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <p className="text-sm font-semibold text-white">Auto Refresh</p>
            <div className="mt-3 flex items-center gap-2">
              <button
                onClick={() => setAutoRefreshEnabled(!autoRefreshEnabled)}
                className={`rounded-lg px-3 py-2 text-sm font-semibold ${autoRefreshEnabled ? 'bg-emerald-500 text-white' : 'bg-white/10 text-white/70'}`}
              >
                {autoRefreshEnabled ? 'Enabled' : 'Disabled'}
              </button>
              <input
                type="number"
                min={10}
                max={180}
                value={refreshEverySec}
                onChange={(e) => setRefreshEverySec(Number(e.target.value))}
                className="w-24 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white outline-none"
              />
              <span className="text-xs text-white/45">seconds</span>
            </div>
          </div>
        </div>
      </CompactCard>
    </div>
  );
}