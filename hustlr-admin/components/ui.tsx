'use client';

interface MetricCardProps {
  label: string;
  value: string;
  sub?: string;
  color?: string;
  loading?: boolean;
}

export function MetricCard({ label, value, sub, color = '#3FFF8B', loading }: MetricCardProps) {
  return (
    <div className="card p-5">
      <p className="text-xs font-bold tracking-widest uppercase mb-2" style={{ color: '#91938D' }}>
        {label}
      </p>
      {loading ? (
        <div className="h-8 w-3/4 rounded bg-white/5 animate-pulse mb-2" />
      ) : (
        <p className="text-2xl font-black leading-none mb-1" style={{ color }}>
          {value}
        </p>
      )}
      {sub && <p className="text-xs mt-1" style={{ color: 'rgba(255,255,255,0.35)' }}>{sub}</p>}
    </div>
  );
}

interface SliderRowProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  format?: (v: number) => string;
  onChange: (v: number) => void;
}

export function SliderRow({ label, value, min, max, step = 1, format, onChange }: SliderRowProps) {
  return (
    <div className="space-y-2">
      <div className="flex justify-between">
        <span className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'rgba(255,255,255,0.4)' }}>
          {label}
        </span>
        <span className="text-sm font-black" style={{ color: '#3FFF8B' }}>
          {format ? format(value) : value}
        </span>
      </div>
      <input
        type="range" min={min} max={max} step={step} value={value}
        onChange={e => onChange(Number(e.target.value))}
      />
    </div>
  );
}
