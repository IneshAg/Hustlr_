'use client';
import { useEffect, useRef, useState } from 'react';

type MapZone = {
  name: string;
  lat: number;
  lng: number;
  risk: number;
  claims: number;
  trigger: string;
  workers: number;
};

const BASE_ZONES: MapZone[] = [
  { name: 'Adyar',          lat: 13.0067, lng: 80.2206, risk: 87, claims: 12, trigger: 'Rain',     workers: 43 },
  { name: 'T. Nagar',       lat: 13.0418, lng: 80.2341, risk: 72, claims: 8,  trigger: 'Rain',     workers: 61 },
  { name: 'Anna Nagar',     lat: 13.0850, lng: 80.2101, risk: 55, claims: 5,  trigger: 'Heat',     workers: 34 },
  { name: 'Velachery',      lat: 12.9780, lng: 80.2209, risk: 91, claims: 18, trigger: 'Flood',    workers: 29 },
  { name: 'Porur',          lat: 13.0357, lng: 80.1566, risk: 46, claims: 3,  trigger: 'AQI',      workers: 22 },
  { name: 'Tambaram',       lat: 12.9249, lng: 80.1000, risk: 38, claims: 2,  trigger: 'Heat',     workers: 18 },
  { name: 'Sholinganallur', lat: 12.9010, lng: 80.2279, risk: 79, claims: 9,  trigger: 'Rain',     workers: 37 },
  { name: 'Chromepet',      lat: 12.9516, lng: 80.1462, risk: 62, claims: 6,  trigger: 'Rain',     workers: 25 },
  { name: 'Mylapore',       lat: 13.0339, lng: 80.2619, risk: 83, claims: 11, trigger: 'Platform', workers: 55 },
  { name: 'Guindy',         lat: 13.0067, lng: 80.2097, risk: 70, claims: 7,  trigger: 'Heat',     workers: 48 },
  { name: 'Perambur',       lat: 13.1175, lng: 80.2446, risk: 28, claims: 1,  trigger: 'None',     workers: 15 },
  { name: 'Kattankulathur', lat: 12.8185, lng: 80.0419, risk: 58, claims: 4,  trigger: 'Heat',     workers: 30 },
];

const byName: Record<string, Pick<MapZone, 'lat' | 'lng'>> = Object.fromEntries(
  BASE_ZONES.map((z) => [z.name, { lat: z.lat, lng: z.lng }]),
);

function riskColor(risk: number): string {
  if (risk >= 81) return '#ff3b59';
  if (risk >= 61) return '#ff8c42';
  if (risk >= 31) return '#ffe066';
  return '#3fff8b';
}

function riskLabel(risk: number): string {
  if (risk >= 81) return 'Critical';
  if (risk >= 61) return 'High';
  if (risk >= 31) return 'Moderate';
  return 'Low';
}

interface H3RiskMapProps {
  zones?: Array<{ name: string; risk: number; claims: number; trigger: string; workers: number }>;
}

export default function H3RiskMap({ zones }: H3RiskMapProps) {
  const zonesData: MapZone[] =
    Array.isArray(zones) && zones.length > 0
      ? zones
          .map((z) => ({
            name: z.name,
            lat: byName[z.name]?.lat ?? 13.028,
            lng: byName[z.name]?.lng ?? 80.21,
            risk: Number(z.risk ?? 0),
            claims: Number(z.claims ?? 0),
            trigger: String(z.trigger ?? 'None'),
            workers: Number(z.workers ?? 0),
          }))
      : BASE_ZONES;

  const mapRef = useRef<HTMLDivElement>(null);
  const [selected, setSelected] = useState<MapZone | null>(null);
  const mapInstanceRef = useRef<any>(null);
  const initializingRef = useRef(false);

  useEffect(() => {
    if (typeof window === 'undefined' || !mapRef.current) return;
    if (mapInstanceRef.current || initializingRef.current) return; // already initialised or initializing
    
    initializingRef.current = true;

    // Dynamically import Leaflet so it doesn't SSR
    import('leaflet').then((L) => {
      // Fix the default icon path issue in Next.js
      delete (L.Icon.Default.prototype as any)._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
        iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
        shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      });

      const container = mapRef.current as any;
      if (container && container._leaflet_id) {
        // Prevent duplicate initialization error entirely
        container._leaflet_id = null;
      }

      const map = L.map(mapRef.current!, {
        center: [13.028, 80.21],
        zoom: 11,
        zoomControl: true,
        attributionControl: false,
      });

      mapInstanceRef.current = map;

      // Force Leaflet to recalculate its size after the container is revealed
      // (it may be hidden/zero-sized on first paint inside a lazy-loaded card)
      setTimeout(() => {
        map.invalidateSize({ animate: false });
      }, 400);

      // Also watch for container resize (e.g. sidebar or panel toggling)
      if (typeof ResizeObserver !== 'undefined' && mapRef.current) {
        const ro = new ResizeObserver(() => map.invalidateSize({ animate: false }));
        ro.observe(mapRef.current);
      }

      // Dark CartoDB basemap — same as DeckGL version
      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        maxZoom: 19,
        subdomains: 'abcd',
      }).addTo(map);

      // Add circle markers for each zone
      zonesData.forEach((zone) => {
        const color = riskColor(zone.risk);
        const radius = 800 + zone.risk * 8; // bigger = higher risk

        const circle = L.circle([zone.lat, zone.lng], {
          radius,
          color,
          fillColor: color,
          fillOpacity: 0.35,
          weight: 2,
          opacity: 0.8,
        }).addTo(map);

        // Pulsing dot at centre
        const icon = L.divIcon({
          html: `<div style="
            width:10px;height:10px;border-radius:50%;
            background:${color};
            box-shadow:0 0 10px ${color};
            border:2px solid rgba(255,255,255,0.6);
          "></div>`,
          iconSize: [10, 10],
          iconAnchor: [5, 5],
          className: '',
        });

        L.marker([zone.lat, zone.lng], { icon })
          .addTo(map)
          .bindPopup(`
            <div style="font-family:Inter,sans-serif;min-width:160px">
              <div style="color:${color};font-weight:700;font-size:13px;margin-bottom:6px">${zone.name}</div>
              <div style="color:#ccc;font-size:12px">Risk score: <b style="color:#fff">${zone.risk}</b></div>
              <div style="color:#ccc;font-size:12px">Claims: <b style="color:#fff">${zone.claims}</b></div>
              <div style="color:#ccc;font-size:12px">Trigger: <b style="color:#fff">${zone.trigger}</b></div>
              <div style="color:#ccc;font-size:12px">Workers: <b style="color:#fff">${zone.workers}</b></div>
            </div>
          `, {
            className: 'hustlr-popup',
            maxWidth: 220,
          });

        circle.on('click', () => setSelected(zone));
      });
    });

    // Inject Leaflet CSS
    if (!document.querySelector('#leaflet-css')) {
      const link = document.createElement('link');
      link.id = 'leaflet-css';
      link.rel = 'stylesheet';
      link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
      document.head.appendChild(link);
    }

    // Inject popup styles
    if (!document.querySelector('#hustlr-popup-css')) {
      const style = document.createElement('style');
      style.id = 'hustlr-popup-css';
      style.textContent = `
        .hustlr-popup .leaflet-popup-content-wrapper {
          background: rgba(5,10,18,0.95);
          border: 1px solid rgba(63,255,139,0.3);
          border-radius: 10px;
          color: #fff;
          backdrop-filter: blur(8px);
        }
        .hustlr-popup .leaflet-popup-tip { background: rgba(5,10,18,0.95); }
        .hustlr-popup .leaflet-popup-close-button { color: #888; }
        .leaflet-control-zoom a {
          background: #1a1a1a !important;
          color: #9ca3af !important;
          border-color: #333 !important;
        }
      `;
      document.head.appendChild(style);
    }

    return () => {
      mapInstanceRef.current?.remove();
      mapInstanceRef.current = null;
    };
  }, [zonesData]);

  const sorted = [...zonesData].sort((a, b) => b.risk - a.risk);

  return (
    <div className="space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-bold uppercase tracking-[0.2em] text-emerald-400">
          ⬡ Live Risk Map — Chennai &amp; Region
        </span>
        <div className="flex items-center gap-3 text-[10px] text-white/40">
          {[['#3fff8b','Low'],['#ffe066','Moderate'],['#ff8c42','High'],['#ff3b59','Critical']].map(([c,l]) => (
            <span key={l} className="flex items-center gap-1">
              <span style={{ background: c }} className="inline-block w-2 h-2 rounded-sm" />
              {l}
            </span>
          ))}
        </div>
      </div>

      {/* Map */}
      <div className="relative rounded-xl overflow-hidden border border-white/10" style={{ height: 460 }}>
        <div ref={mapRef} style={{ width: '100%', height: '100%' }} />

        {/* Selected zone overlay */}
        {selected && (
          <div className="absolute bottom-4 right-4 z-500 rounded-xl border border-white/20 bg-black/90 backdrop-blur-md p-4 min-w-45">
            <div className="flex items-center justify-between mb-2">
              <span style={{ color: riskColor(selected.risk) }} className="font-bold text-sm">{selected.name}</span>
              <button onClick={() => setSelected(null)} className="text-white/40 hover:text-white text-xs">✕</button>
            </div>
            <div className="space-y-1 text-xs text-white/60">
              <p>Risk: <span style={{ color: riskColor(selected.risk) }} className="font-bold">{selected.risk} — {riskLabel(selected.risk)}</span></p>
              <p>Claims: <span className="text-white font-semibold">{selected.claims}</span></p>
              <p>Trigger: <span className="text-white font-semibold">{selected.trigger}</span></p>
              <p>Workers: <span className="text-white font-semibold">{selected.workers}</span></p>
            </div>
          </div>
        )}
      </div>

      {/* Zone risk ranked list */}
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2">
        {sorted.map((z) => (
          <button
            key={z.name}
            onClick={() => setSelected(z)}
            className="flex items-center justify-between rounded-lg border border-white/8 bg-white/4 px-3 py-2 text-left transition hover:bg-white/8"
          >
            <div>
              <p className="text-xs font-semibold text-white">{z.name}</p>
              <p className="text-[10px] text-white/40">{z.trigger} · {z.workers}w</p>
            </div>
            <span
              className="text-[11px] font-bold ml-2 shrink-0"
              style={{ color: riskColor(z.risk) }}
            >
              {z.risk}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
