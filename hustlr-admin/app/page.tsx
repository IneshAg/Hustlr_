'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    router.replace('/admin');
  }, [router]);

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#0a0a0a] text-white">
      <p className="text-sm text-white/70">Redirecting to the Hustlr admin console...</p>
    </main>
  );
}
