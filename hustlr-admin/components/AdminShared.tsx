'use client';
import { Activity, RefreshCw } from 'lucide-react';
import { ReactNode } from 'react';

export function LoadingState() {
  return (
    <div className="flex h-full min-h-[50vh] items-center justify-center text-white">
      <div className="text-center">
        <RefreshCw className="mx-auto mb-4 h-12 w-12 animate-spin text-emerald-400" />
        <p className="text-white/80">Loading...</p>
      </div>
    </div>
  );
}

export function ErrorState({ errorMessage, onRetry }: { errorMessage: string; onRetry: () => void }) {
  return (
    <div className="flex h-full min-h-[50vh] items-center justify-center text-white">
      <div className="text-center">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-red-500/20">
          <Activity className="h-8 w-8 text-red-400" />
        </div>
        <p className="mb-2 text-xl font-semibold text-white">Error Loading Data</p>
        <p className="mb-6 text-gray-400">{errorMessage}</p>
        <button onClick={onRetry} className="rounded-lg bg-emerald-500 px-6 py-2 font-semibold text-white hover:bg-emerald-600">
          Retry
        </button>
      </div>
    </div>
  );
}

export function MetricCard({ title, value, subtitle, icon, tone }: { title: string; value: string; subtitle: string; icon: ReactNode; tone: 'blue' | 'green' | 'purple' | 'orange'; }) {
  const toneClasses: Record<typeof tone, string> = {
    blue: 'text-sky-300 border-sky-500/20 bg-sky-500/5',
    green: 'text-emerald-300 border-emerald-500/20 bg-emerald-500/5',
    purple: 'text-violet-300 border-violet-500/20 bg-violet-500/5',
    orange: 'text-orange-300 border-orange-500/20 bg-orange-500/5',
  };
  return (
    <div className={`rounded-2xl border p-4 ${toneClasses[tone]}`}>
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-wide text-white/45">{title}</p>
          <p className={`mt-2 text-2xl font-semibold ${toneClasses[tone].split(' ')[0]}`}>{value}</p>
          <p className="mt-1 text-xs text-white/45">{subtitle}</p>
        </div>
        <div className="text-white/70">{icon}</div>
      </div>
    </div>
  );
}

export function MiniStat({ icon, label, value, tone }: { icon: ReactNode; label: string; value: string | number; tone: 'red' | 'emerald' | 'blue'; }) {
  const classes: Record<typeof tone, string> = {
    red: 'border-red-500/20 bg-red-500/5 text-red-200',
    emerald: 'border-emerald-500/20 bg-emerald-500/5 text-emerald-200',
    blue: 'border-sky-500/20 bg-sky-500/5 text-sky-200',
  };
  return (
    <div className={`rounded-2xl border p-4 ${classes[tone]}`}>
      <div className="flex items-center gap-2 text-sm font-semibold">{icon}<span>{label}</span></div>
      <p className="mt-3 text-2xl font-semibold text-white">{value}</p>
    </div>
  );
}

export function CompactCard({ title, accent, children }: { title: string; accent: 'red' | 'blue' | 'green' | 'orange' | 'purple' | 'emerald'; children: ReactNode }) {
  const accentClasses: Record<typeof accent, string> = {
    red: 'border-red-500/20', blue: 'border-sky-500/20', green: 'border-emerald-500/20',
    orange: 'border-orange-500/20', purple: 'border-violet-500/20', emerald: 'border-emerald-500/20',
  };
  return (
    <div className={`rounded-2xl border ${accentClasses[accent]} bg-[#111111] p-4`}>
      <p className="mb-3 text-xs font-bold uppercase tracking-[0.24em] text-white/35">{title}</p>
      <div className="overflow-hidden rounded-xl">{children}</div>
    </div>
  );
}
