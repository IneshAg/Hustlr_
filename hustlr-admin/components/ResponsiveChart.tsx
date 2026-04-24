'use client';

import { useEffect, useRef, useState, type ReactNode, type CSSProperties } from 'react';

type Props = {
  className?: string;
  style?: CSSProperties;
  minHeight?: number;
  children: ReactNode;
};

export default function ResponsiveChart({
  className,
  style,
  minHeight = 1,
  children,
}: Props) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    const check = () => {
      const rect = host.getBoundingClientRect();
      setReady(rect.width > 0 && rect.height >= minHeight);
    };

    check();
    const ro = new ResizeObserver(check);
    ro.observe(host);
    return () => ro.disconnect();
  }, [minHeight]);

  return (
    <div ref={hostRef} className={className} style={style}>
      {ready ? children : null}
    </div>
  );
}
