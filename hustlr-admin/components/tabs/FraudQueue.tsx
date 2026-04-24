'use client';
import React, { useState, useEffect } from 'react';
import { MetricCard } from '@/components/ui';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, LineChart, Line, Dot } from 'recharts';
import { ChevronDown, ChevronUp, MapPin, AlertTriangle, ShieldCheck, CheckCircle2, UserCircle2, Clock, Camera } from 'lucide-react';
import { fetchFraudModelHealth } from '@/lib/api';

type ActionState = 'Approve' | 'Reject' | 'Reduce' | 'Evidence' | null;

// Mock Data strictly following the prompt's requirements
const QUEUE_DATA = [
  {
    id: 'CL-8842',
    worker: 'Suresh Kumar',
    zone: 'TN_ADYAR_07',
    trigger: 'Heavy Rain',
    amount: 320,
    timeInQueueMin: 280, // >4 hrs (amber)
    provisionalCredited: 120,
    fps: 0.88,
    status: 'FLAGGED',
    flags: ['impossible_speed', 'mock_location_detected', 'ring_detection_flagged'],
    history: { clean: 4, flagged: 1, rejected: 0 },
    frsBreakdown: [
      { layer: 'Geolocation', penalty: 45 },
      { layer: 'Network IP', penalty: 0 },
      { layer: 'ML Zone Anomaly', penalty: 25 },
      { layer: 'Ring Detect', penalty: 18 },
      { layer: 'Account Age', penalty: 0 },
    ],
    telemetryTimeline: Array.from({ length: 40 }).map((_, i) => i > 12 && i < 18 ? 'gap' : i === 35 ? 'gap' : 'ok'),
    gpsTrace: Array.from({ length: 20 }).map((_, i) => ({
      x: i,
      y: Math.sin(i * 0.5) + (i * 0.1),
      anomaly: i > 12 && i < 15, // corresponds to the gap jump
    })),
  },
  {
    id: 'CL-8845',
    worker: 'Rahul S.',
    zone: 'KA_KOR_02',
    trigger: 'Extreme Heat',
    amount: 180,
    timeInQueueMin: 510, // >8 hrs (red)
    provisionalCredited: 0,
    fps: 0.65,
    status: 'FLAGGED',
    flags: ['shift_gap_during_event'],
    history: { clean: 12, flagged: 0, rejected: 0 },
    frsBreakdown: [
      { layer: 'Geolocation', penalty: 20 },
      { layer: 'Network IP', penalty: 0 },
      { layer: 'ML Zone Anomaly', penalty: 0 },
      { layer: 'Ring Detect', penalty: 0 },
      { layer: 'Account Age', penalty: 45 },
    ],
    telemetryTimeline: Array.from({ length: 40 }).map((_, i) => i > 25 && i < 35 ? 'gap' : 'ok'),
    gpsTrace: Array.from({ length: 20 }).map((_, i) => ({
      x: i,
      y: Math.cos(i * 0.3) + (i * 0.1),
      anomaly: i > 15 && i < 18,
    })),
  },
  {
    id: 'CL-8890',
    worker: 'Vinod Kumar',
    zone: 'TN_OMR_12',
    trigger: 'Platform Outage',
    amount: 250,
    timeInQueueMin: 45, // <4 hrs
    provisionalCredited: 100,
    fps: 0.72,
    status: 'FLAGGED',
    flags: ['device_hardware_mismatch', 'ip_geolocation_mismatch'],
    history: { clean: 1, flagged: 2, rejected: 1 },
    frsBreakdown: [
      { layer: 'Geolocation', penalty: 0 },
      { layer: 'Network IP', penalty: 30 },
      { layer: 'Device Integrity', penalty: 42 },
      { layer: 'Ring Detect', penalty: 0 },
      { layer: 'Account Age', penalty: 0 },
    ],
    telemetryTimeline: Array.from({ length: 40 }).map(() => 'ok'),
    gpsTrace: Array.from({ length: 20 }).map((_, i) => ({ x: i, y: Math.sin(i * 0.2), anomaly: false })),
  }
];

const fpsBadge = (score: number) => 
  score >= 0.60 ? 'badge-red' : score >= 0.30 ? 'badge-amber' : 'badge-green';

const slaBadge = (mins: number) => {
  if (mins >= 480) return <span className="badge-red ml-2 bg-red-500/20 text-red-400">8h+ SLA SLACH</span>;
  if (mins >= 240) return <span className="badge-amber ml-2 bg-orange-500/20 text-orange-400">4h+ SLA</span>;
  return null;
};

export default function FraudQueue() {
  const [queue, setQueue] = useState(QUEUE_DATA.map(f => ({ ...f, decision: null as ActionState })));
  const [expandedRow, setExpandedRow] = useState<string | null>(null);
  const [modelHealth, setModelHealth] = useState<any>(null);
  const [healthStatus, setHealthStatus] = useState('connecting');
  
  useEffect(() => {
    fetchFraudModelHealth()
      .then(res => {
        setModelHealth(res);
        setHealthStatus(res.status === 'ok' ? 'live' : 'degraded');
      })
      .catch(() => setHealthStatus('offline'));
  }, []);
  
  // Modals
  const [activeModal, setActiveModal] = useState<'Reject' | 'Reduce' | null>(null);
  const [modalClaimId, setModalClaimId] = useState<string | null>(null);
  const [reductionPct, setReductionPct] = useState(50);
  const [reason, setReason] = useState('suspicious_gps');

  const act = (id: string, action: ActionState) => {
    if (action === 'Reject' || action === 'Reduce') {
      setActiveModal(action);
      setModalClaimId(id);
    } else {
      // Direct actions (Approve, Request Evidence)
      setQueue(prev => prev.map(f => f.id === id ? { ...f, decision: action } : f));
    }
  };

  const confirmModalAction = () => {
    if (activeModal && modalClaimId) {
      setQueue(prev => prev.map(f => f.id === modalClaimId ? { ...f, decision: activeModal } : f));
    }
    closeModal();
  };

  const closeModal = () => {
    setActiveModal(null);
    setModalClaimId(null);
    setReason('suspicious_gps');
    setReductionPct(50);
  };

  return (
    <div className="space-y-6 pb-20">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MetricCard label="Auto-Approved Today" value="1,492" sub="FPS < 0.30 — GREEN tier" color="#3FFF8B" />
        <MetricCard label="Soft Holds" value="84" sub="FPS 0.30–0.60 — AMBER tier" color="#FF9800" />
        <MetricCard label="Manual Review Queue" value={queue.filter(q => !q.decision).length.toString()} sub="FPS > 0.60 — RED tier" color="#E24B4A" />
      </div>

      <div className="card overflow-hidden border" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
        <div className="px-6 py-4 border-b bg-white/[0.01] flex justify-between items-center" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
          <p className="text-xs font-bold tracking-widest uppercase" style={{ color: '#91938D' }}>
            MANUAL FRAUD REVIEW QUEUE
          </p>
          <div className="flex items-center gap-4 text-[10px] uppercase tracking-widest font-bold">
             {healthStatus === 'live' && modelHealth ? (
               <span className="text-emerald-400">✅ ML Engine: {modelHealth.model_version}</span>
             ) : healthStatus === 'connecting' ? (
               <span className="text-orange-400">⏳ Connecting to AI...</span>
             ) : (
               <span className="text-red-400">❌ AI Engine Offline</span>
             )}
          </div>
        </div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
                {['ID / Worker', 'Zone & Trigger', 'Claim / Time', 'FRS & Flags', 'Action'].map(h => (
                  <th key={h} className="px-4 py-3 text-xs font-bold tracking-wider uppercase text-white/30 whitespace-nowrap">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {queue.map(row => {
                const isExpanded = expandedRow === row.id;
                const hrs = Math.floor(row.timeInQueueMin / 60);
                const mins = row.timeInQueueMin % 60;
                
                return (
                  <React.Fragment key={row.id}>
                    <tr 
                      className={`border-b transition-colors cursor-pointer ${row.decision ? 'opacity-30 grayscale' : 'hover:bg-white/[0.02]'}`}
                      style={{ borderColor: 'rgba(255,255,255,0.07)' }}
                      onClick={() => !row.decision && setExpandedRow(isExpanded ? null : row.id)}
                    >
                      <td className="px-4 py-4 align-top">
                        <div className="font-mono text-sm font-bold text-emerald-400 mb-1">{row.id}</div>
                        <div className="text-sm text-white/80 font-medium">{row.worker}</div>
                        <div className="text-xs text-white/40 flex items-center gap-1 mt-1">
                          {isExpanded ? <ChevronUp size={14}/> : <ChevronDown size={14}/>} Details
                        </div>
                      </td>
                      <td className="px-4 py-4 align-top">
                        <div className="text-sm font-bold text-white/80">{row.zone}</div>
                        <div className="text-sm text-white/50">{row.trigger}</div>
                      </td>
                      <td className="px-4 py-4 align-top">
                        <div className="text-sm font-black text-white/90">₹{row.amount}</div>
                        <div className="text-xs text-white/50 mt-1 flex items-center">
                          <Clock size={12} className="mr-1 inline opacity-50"/> {hrs}h {mins}m {slaBadge(row.timeInQueueMin)}
                        </div>
                        {row.provisionalCredited > 0 && (
                          <div className="text-[10px] uppercase tracking-wider font-bold text-emerald-500/70 mt-2">
                            ₹{row.provisionalCredited} Prov. Released
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-4 align-top max-w-[280px]">
                        <div className="flex items-center gap-2 mb-2">
                          <span className={fpsBadge(row.fps)}>{(row.fps * 100).toFixed(0)} FRS</span>
                          <span className="text-xs text-red-400 font-bold tracking-wide uppercase">Requires Review</span>
                        </div>
                        <div className="flex flex-wrap gap-1.5">
                          {row.flags.map(flag => (
                            <span key={flag} className="text-[10px] px-2 py-0.5 rounded uppercase border border-red-500/20 text-red-400/80 bg-red-500/5">
                              {flag.replace(/_/g, ' ')}
                            </span>
                          ))}
                        </div>
                      </td>
                      <td className="px-4 py-4 align-top">
                        {row.decision ? (
                          <div className="text-sm font-bold opacity-80 uppercase tracking-widest text-[#3FFF8B]">
                            ✓ {row.decision} Processed
                          </div>
                        ) : (
                          <div className="flex flex-col gap-2" onClick={e => e.stopPropagation()}>
                            <div className="flex gap-2">
                              <button onClick={() => act(row.id, 'Approve')} className="btn-action bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border-emerald-500/30">
                                Approve (70%)
                              </button>
                              <button onClick={() => act(row.id, 'Reject')} className="btn-action bg-red-500/10 text-red-400 hover:bg-red-500/20 border-red-500/30">
                                Reject
                              </button>
                            </div>
                            <div className="flex gap-2">
                              <button onClick={() => act(row.id, 'Reduce')} className="btn-action bg-orange-500/10 text-orange-400 hover:bg-orange-500/20 border-orange-500/30">
                                Approve w/ Reduction
                              </button>
                              <button onClick={() => act(row.id, 'Evidence')} className="btn-action bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border-blue-500/30">
                                Req. Evidence
                              </button>
                            </div>
                          </div>
                        )}
                      </td>
                    </tr>
                    
                    {/* Expandable Detail Panel */}
                    {isExpanded && !row.decision && (
                      <tr className="bg-[#050605] border-b" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
                        <td colSpan={5} className="p-6">
                          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                            
                            {/* Panel 1: GPS & Telemetry */}
                            <div className="space-y-4">
                              <h4 className="text-xs font-bold uppercase tracking-widest text-white/40 flex items-center gap-1.5"><MapPin size={14}/> Background Shift Route</h4>
                              <div className="h-40 bg-[#0A0B0A] border rounded-lg overflow-hidden relative" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
                                <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                                  <LineChart data={row.gpsTrace} margin={{ top: 10, right: 10, bottom: 10, left: 10 }}>
                                    <XAxis dataKey="x" hide />
                                    <YAxis dataKey="y" hide domain={['dataMin', 'dataMax']} />
                                    <Line type="monotone" dataKey="y" stroke="#3FFF8B" strokeWidth={2} dot={(props: any) => {
                                      const { cx, cy, payload } = props;
                                      if (payload.anomaly) return <circle cx={cx} cy={cy} r={4} fill="#E24B4A" />;
                                      return <circle cx={cx} cy={cy} r={2} fill="#3FFF8B" opacity={0.5} />;
                                    }} />
                                  </LineChart>
                                </ResponsiveContainer>
                                <div className="absolute bottom-2 left-2 text-[10px] font-bold text-white/30 uppercase">Simulated GPS Trace</div>
                              </div>

                              <div className="space-y-2">
                                <h4 className="text-[10px] font-bold uppercase tracking-widest text-white/40">Watchdog Heartbeat Timeline</h4>
                                <div className="flex gap-1 h-3 w-full">
                                  {row.telemetryTimeline.map((status, i) => (
                                    <div key={i} className={`flex-1 rounded-sm ${status === 'ok' ? 'bg-emerald-500/30' : 'bg-red-500/80 pulse-red'}`} title={status === 'ok' ? 'Connected' : 'GPS Gap'} />
                                  ))}
                                </div>
                                <div className="flex justify-between text-[10px] text-white/30">
                                  <span>Shift Start</span>
                                  <span>Claim Event</span>
                                </div>
                              </div>
                            </div>
                            
                            {/* Panel 2: FRS Breakdown */}
                            <div className="space-y-4">
                              <h4 className="text-xs font-bold uppercase tracking-widest text-white/40 flex items-center gap-1.5"><AlertTriangle size={14}/> FRS Weight Breakdown</h4>
                              <div className="h-48">
                                <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={1}>
                                  <BarChart data={row.frsBreakdown} layout="vertical" margin={{ left: -10, right: 20 }}>
                                    <XAxis type="number" hide domain={[0, 100]} />
                                    <YAxis dataKey="layer" type="category" axisLine={false} tickLine={false} tick={{ fontSize: 10, fill: 'rgba(255,255,255,0.4)' }} width={110} />
                                    <Bar dataKey="penalty" radius={[0, 4, 4, 0]} barSize={16}>
                                      {row.frsBreakdown.map((entry, index) => (
                                        <Cell key={`cell-${index}`} fill={entry.penalty > 0 ? '#E24B4A' : 'rgba(255,255,255,0.05)'} />
                                      ))}
                                    </Bar>
                                  </BarChart>
                                </ResponsiveContainer>
                              </div>
                              <div className="text-xs text-white/50 bg-white/5 p-3 rounded-lg border border-white/10 flex items-start gap-2">
                                <ShieldCheck size={16} className="text-[#3FFF8B] shrink-0 mt-0.5" />
                                <span>Worker History: {row.history.clean} Clean, {row.history.flagged} Flagged, {row.history.rejected} Rejected. Long-term trust score remains acceptable.</span>
                              </div>
                            </div>

                            {/* Panel 3: Identity Verification */}
                            <div className="space-y-4">
                              <h4 className="text-xs font-bold uppercase tracking-widest text-white/40 flex items-center gap-1.5"><Camera size={14}/> AWS Step-Up Auth</h4>
                              
                              <div className="grid grid-cols-2 gap-3 pb-2">
                                <div className="space-y-1.5">
                                  <div className="aspect-square bg-white/[0.03] border border-white/10 rounded-xl flex items-center justify-center flex-col gap-2 overflow-hidden relative">
                                    <UserCircle2 size={32} className="text-white/20" />
                                    <div className="absolute inset-0 bg-gradient-to-t from-black/50 to-transparent" />
                                  </div>
                                  <div className="text-center text-[10px] font-bold text-white/40 uppercase tracking-widest">KYC Registration</div>
                                </div>
                                <div className="space-y-1.5">
                                  <div className="aspect-square bg-emerald-500/5 border border-emerald-500/20 rounded-xl flex items-center justify-center flex-col gap-2 relative overflow-hidden">
                                    <UserCircle2 size={32} className="text-emerald-500/30" />
                                    <div className="absolute top-2 right-2 bg-emerald-500/20 text-emerald-400 text-[10px] font-black px-1.5 py-0.5 rounded">94% Match</div>
                                    <div className="absolute inset-0 bg-gradient-to-t from-emerald-900/20 to-transparent" />
                                  </div>
                                  <div className="text-center text-[10px] font-bold text-white/40 uppercase tracking-widest">Claim Selfie</div>
                                </div>
                              </div>
                              
                              <div className="flex gap-2 items-center text-xs text-white/60 p-3 bg-red-500/5 border border-red-500/10 rounded-lg">
                                <AlertTriangle size={16} className="text-red-400 shrink-0" />
                                <div>Identity verified, but severe Mock Location signals present during the shift. Recommend heavy scrutiny.</div>
                              </div>
                            </div>

                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
            </tbody>
          </table>
          
          {queue.length === 0 && (
            <div className="py-20 text-center text-white/30 text-sm flex flex-col items-center">
              <CheckCircle2 size={32} className="mb-2 opacity-50" />
              Queue is empty. All claims processed.
            </div>
          )}
        </div>
      </div>

      {/* Action Modals */}
      {activeModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-md bg-[#0A0B0A] border rounded-2xl p-6 shadow-2xl" style={{ borderColor: 'rgba(255,255,255,0.1)' }}>
            <h3 className="text-lg font-black text-white">
              {activeModal === 'Reject' ? 'Reject Claim' : 'Approve with Reduction'}
            </h3>
            <p className="text-sm text-white/40 mt-1 mb-6">Claim ID: {modalClaimId}</p>

            {activeModal === 'Reduce' && (
              <div className="mb-6 space-y-2">
                <label className="text-xs font-bold uppercase tracking-widest text-[#91938D]">Reduction Percentage: {reductionPct}%</label>
                <input 
                  type="range" min="10" max="90" step="10" 
                  value={reductionPct} onChange={e => setReductionPct(parseInt(e.target.value))}
                  className="w-full accent-orange-500"
                />
                <div className="flex justify-between text-xs text-white/30">
                  <span>Pay 90%</span><span>Pay 10%</span>
                </div>
              </div>
            )}

            <div className="mb-6 space-y-2">
              <label className="text-xs font-bold uppercase tracking-widest text-[#91938D]">Reason Code</label>
              <select 
                value={reason} onChange={e => setReason(e.target.value)}
                className="w-full bg-white/5 border rounded-lg p-3 text-sm text-white outline-none focus:border-white/30"
                style={{ borderColor: 'rgba(255,255,255,0.1)' }}
              >
                <option value="suspicious_gps">Suspicious GPS Telemetry</option>
                <option value="ring_pattern">Collusion / Ring Pattern Detected</option>
                <option value="policy_abuse">General Policy Abuse</option>
                <option value="fake_evidence">Fabricated Evidence</option>
              </select>
            </div>

            <div className="flex gap-3 justify-end pt-4 border-t" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
              <button onClick={closeModal} className="px-4 py-2 rounded-lg text-sm font-bold text-white/50 hover:text-white">Cancel</button>
              <button 
                onClick={confirmModalAction}
                className={`px-6 py-2 rounded-lg text-sm font-black text-black ${activeModal === 'Reject' ? 'bg-red-400 hover:bg-red-300' : 'bg-orange-400 hover:bg-orange-300'}`}
              >
                Confirm {activeModal}
              </button>
            </div>
          </div>
        </div>
      )}

      <style jsx>{`
        .btn-action {
          @apply text-[10px] font-bold px-2 py-1 rounded transition-all flex-1 text-center border;
        }
      `}</style>
    </div>
  );
}
