export function fmt(n: number): string {
  if (n >= 10000000) return '₹' + (n / 10000000).toFixed(2) + 'Cr';
  if (n >= 100000)   return '₹' + (n / 100000).toFixed(1) + 'L';
  if (n >= 1000)     return '₹' + (n / 1000).toFixed(1) + 'K';
  return '₹' + Math.round(n).toLocaleString('en-IN');
}

export function bcrColor(bcr: number): string {
  if (bcr < 65) return '#3FFF8B';
  if (bcr < 85) return '#FF9800';
  return '#E24B4A';
}

export function bcrBadge(bcr: number): string {
  if (bcr < 65) return 'badge-green';
  if (bcr < 85) return 'badge-amber';
  return 'badge-red';
}

export function riskBadge(r: string): string {
  if (r === 'LOW') return 'badge-green';
  if (r === 'MEDIUM') return 'badge-amber';
  return 'badge-red';
}

export function fpsBadge(fps: number): string {
  if (fps < 0.30) return 'badge-green';
  if (fps < 0.60) return 'badge-amber';
  return 'badge-red';
}
