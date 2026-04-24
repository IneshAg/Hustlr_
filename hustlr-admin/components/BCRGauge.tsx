'use client';
import { bcrColor } from '@/lib/utils';

interface BCRGaugeProps { bcr: number; }

export function BCRGauge({ bcr }: BCRGaugeProps) {
  const color = bcrColor(bcr);
  const r = 80, cx = 100, cy = 108;

  function polarToXY(deg: number) {
    const rad = (deg - 90) * Math.PI / 180;
    return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
  }
  function arc(start: number, end: number, col: string) {
    const s = polarToXY(start), e = polarToXY(end);
    const large = end - start > 180 ? 1 : 0;
    return (
      <path
        d={`M${s.x},${s.y} A${r},${r} 0 ${large} 1 ${e.x},${e.y}`}
        fill="none" stroke={col} strokeWidth={14} strokeLinecap="round"
      />
    );
  }

  const needleAngle = -90 + (Math.min(bcr, 100) / 100) * 180;
  const needleRad   = needleAngle * Math.PI / 180;
  const nx = cx + 62 * Math.cos(needleRad);
  const ny = cy + 62 * Math.sin(needleRad);

  return (
    <div className="flex flex-col items-center gap-2">
      <svg width={200} height={130} viewBox="0 0 200 130">
        {/* Background arcs */}
        {arc(-90, -90 + 117, '#3FFF8B33')}
        {arc(-90 + 117, -90 + 153, '#FF980033')}
        {arc(-90 + 153, 90, '#E24B4A33')}
        {/* Fill arc */}
        {arc(-90, -90 + (Math.min(bcr, 100) / 100) * 180, color)}
        {/* Needle */}
        <line x1={cx} y1={cy} x2={nx} y2={ny} stroke="#fff" strokeWidth={2.5} strokeLinecap="round" />
        <circle cx={cx} cy={cy} r={5} fill="#fff" />
        {/* Labels */}
        <text x={cx} y={cy - 12} textAnchor="middle" fill={color} fontSize={22} fontWeight={900} fontFamily="Manrope">
          {bcr.toFixed(1)}%
        </text>
        <text x={18}  y={125} fill="#3FFF8B" fontSize={10} fontFamily="Manrope" fontWeight={700}>0%</text>
        <text x={87}  y={28}  fill="#FF9800" fontSize={10} fontFamily="Manrope" fontWeight={700}>65%</text>
        <text x={162} y={125} fill="#E24B4A" fontSize={10} fontFamily="Manrope" fontWeight={700}>100%</text>
      </svg>
      <span className="text-xs font-bold" style={{ color }}>
        {bcr < 65 ? '✓ HEALTHY' : bcr < 85 ? '⚠ ELEVATED' : '✗ CRITICAL'}
      </span>
    </div>
  );
}
