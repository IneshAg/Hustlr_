'use client';
import { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  Activity, Briefcase, CreditCard, Database, FileText, HeartPulse,
  MonitorCheck, PlugZap, RefreshCw, Siren, SlidersHorizontal, TrendingUp, Users, Radar
} from 'lucide-react';
import { AdminProvider, useAdminData } from '@/components/AdminContext';
import { LoadingState, ErrorState } from '@/components/AdminShared';

const SIDEBAR = [
  {
    section: 'OPERATIONS',
    items: [
      { id: 'overview', path: '/admin/overview', label: 'Overview', icon: <Activity className="h-4 w-4" /> },
      { id: 'map', path: '/admin/map', label: 'Live Risk Map', icon: <Radar className="h-4 w-4" /> },
      { id: 'policies', path: '/admin/policies', label: 'Policies', icon: <FileText className="h-4 w-4" /> },
      { id: 'riders', path: '/admin/riders', label: 'Riders', icon: <Users className="h-4 w-4" /> },
    ]
  },
  {
    section: 'FINANCIAL',
    items: [
      { id: 'payments', path: '/admin/payments', label: 'Payments', icon: <CreditCard className="h-4 w-4" /> },
      { id: 'revenue', path: '/admin/revenue', label: 'Revenue & Loss', icon: <TrendingUp className="h-4 w-4" /> },
      { id: 'reserves', path: '/admin/reserves', label: 'Reserves & Stress', icon: <Database className="h-4 w-4" /> },
      { id: 'pricing', path: '/admin/pricing', label: 'Plans & Pricing', icon: <Briefcase className="h-4 w-4" /> },
    ]
  },
  {
    section: 'REVIEW',
    items: [
      { id: 'fraud', path: '/admin/fraud', label: 'Fraud Queue', icon: <Siren className="h-4 w-4" /> },
      { id: 'health', path: '/admin/health', label: 'System Health', icon: <HeartPulse className="h-4 w-4" /> },
      { id: 'demo', path: '/admin/demo', label: 'Demo Controls', icon: <SlidersHorizontal className="h-4 w-4" /> },
    ]
  }
];

function AdminLayoutInner({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { loading, errorMessage, lastRefresh, useMockData, connectionLabel, toggleDataSource, loadData } = useAdminData();

  const currentTab = SIDEBAR.flatMap(g => g.items).find(i => pathname.includes(i.path));

  return (
    <div className="flex h-screen bg-[#0a0a0a] text-white overflow-hidden">
      <aside className="hidden w-64 flex-col border-r border-white/5 bg-[#111111] py-6 md:flex overflow-y-auto">
        <div className="mb-8 flex items-center gap-3 px-6">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg border border-white/10 bg-white/5 text-emerald-300">
            <Database className="h-4 w-4" />
          </div>
          <div>
            <h1 className="font-semibold text-white">Hustlr</h1>
            <p className="text-[10px] uppercase tracking-wider text-white/40">Admin Console</p>
          </div>
        </div>
        <div className="flex-1 space-y-8">
          {SIDEBAR.map((group) => (
            <div key={group.section}>
              <h3 className="mb-2 px-6 text-[10px] font-bold uppercase tracking-widest text-white/40">{group.section}</h3>
              <nav className="flex flex-col gap-1 px-3">
                {group.items.map((item) => {
                  const isActive = pathname.startsWith(item.path);
                  return (
                    <Link key={item.id} href={item.path}
                      className={`mx-2 flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors ${isActive ? 'bg-white/10 text-white' : 'text-white/50 hover:bg-white/5 hover:text-white'}`}
                    >
                      <span className={isActive ? 'text-emerald-400' : 'text-white/40'}>{item.icon}</span>
                      {item.label}
                    </Link>
                  );
                })}
              </nav>
            </div>
          ))}
        </div>
        <div className="mt-8 px-6">
           <div className={`inline-flex w-full items-center justify-center gap-2 rounded-lg border px-3 py-2 text-xs font-semibold ${connectionLabel.tone}`}>
             <MonitorCheck className="h-3.5 w-3.5" />
             {connectionLabel.label}
           </div>
        </div>
      </aside>
      <div className="flex flex-1 flex-col overflow-hidden min-w-0">
        <header className="flex items-center justify-between border-b border-white/5 bg-[#111]/95 px-4 py-3 lg:hidden">
          <div className="flex items-center gap-2">
             <Database className="h-5 w-5 text-emerald-300" />
             <h1 className="font-semibold text-white">Hustlr Admin</h1>
          </div>
        </header>
        <header className="flex flex-wrap items-center justify-between border-b border-white/5 bg-[#0a0a0a] px-6 py-4 gap-4">
           <div>
             <h2 className="text-xl font-bold text-white capitalize">{currentTab?.label || 'Dashboard'}</h2>
             <p className="text-xs text-white/40 mt-1">Hustlr Dashboard Integration</p>
           </div>
           <div className="flex items-center gap-3">
             <span className="hidden rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs text-white/45 md:inline-flex">
               Updated {lastRefresh || '--:--:--'}
             </span>
             <button onClick={toggleDataSource} className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-semibold transition ${useMockData ? 'border-orange-500/25 bg-orange-500/10 text-orange-200' : 'border-emerald-500/25 bg-emerald-500/10 text-emerald-200'}`}>
               <PlugZap className="h-3.5 w-3.5" /> {useMockData ? 'Demo Mode' : 'Live Mode'}
             </button>
             <button onClick={() => loadData(true)} className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-semibold text-white/80 transition hover:bg-white/10">
               <RefreshCw className="h-3.5 w-3.5" /> Refresh
             </button>
           </div>
        </header>
        <main className="flex-1 overflow-y-auto p-6">
           <div className="mx-auto max-w-[1400px] h-full">
              {loading ? <LoadingState /> : errorMessage ? <ErrorState errorMessage={errorMessage} onRetry={() => loadData(true)} /> : children}
           </div>
        </main>
      </div>
    </div>
  );
}

export default function AdminLayout({ children }: { children: ReactNode }) {
  return <AdminProvider><AdminLayoutInner>{children}</AdminLayoutInner></AdminProvider>;
}
