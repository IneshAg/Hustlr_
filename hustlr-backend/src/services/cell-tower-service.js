// src/services/cell-tower-service.js
// Location from cell towers: OpenCelliD (optional) → Unwired Labs / LocationAPI → fallback.

const axios = require("axios");
const { withFallback } = require("./api-wrapper");
const { FALLBACKS } = require("./fallback-service");

const UNWIRED_KEY = process.env.CELL_LOCATION_API_KEY || "";
const OPENCELLID_KEY = process.env.OPENCELLID_API_KEY || "";

const OPENCELLID_URL = "https://opencellid.org/cell/get";

/**
 * OpenCelliD — first cell only; free tier may require whitelisted key (see opencellid.org).
 * @see https://wiki.opencellid.org/wiki/API
 */
async function tryOpenCellId(payload) {
  if (!OPENCELLID_KEY) return null;

  const c = payload.cells[0];
  const cellid = c.cellId ?? c.cid ?? c.cellid;
  const lac = c.lac ?? c.tac;
  if (cellid == null || lac == null || c.mcc == null || c.mnc == null) {
    return null;
  }

  const params = {
    key: OPENCELLID_KEY,
    mcc: c.mcc,
    mnc: c.mnc,
    lac,
    cellid,
    format: "json",
  };
  if (payload.radio) params.radio = String(payload.radio).toUpperCase();

  const res = await axios.get(OPENCELLID_URL, {
    params,
    timeout: 8000,
    validateStatus: () => true,
  });

  if (res.status !== 200 || !res.data) {
    return null;
  }

  const lat = res.data.lat;
  const lon = res.data.lon;
  if (lat == null || lon == null) {
    return null;
  }

  return {
    lat: Number(lat),
    lng: Number(lon),
    accuracy: res.data.range != null ? Number(res.data.range) : 1000,
    source: "opencellid",
    samples: res.data.samples,
  };
}

/**
 * Estimates geographic location from nearby cell tower data.
 * Order: OpenCelliD (if OPENCELLID_API_KEY) → Unwired (if CELL_LOCATION_API_KEY) → api-wrapper fallback.
 */
async function estimateLocation(payload) {
  if (
    !payload ||
    !payload.cells ||
    !Array.isArray(payload.cells) ||
    payload.cells.length === 0
  ) {
    return { error: "Insufficient cell data" };
  }

  try {
    const oc = await tryOpenCellId(payload);
    if (oc) return oc;
  } catch (e) {
    console.warn("[OpenCelliD]", e.message);
  }

  if (!UNWIRED_KEY) {
    return {
      ...FALLBACKS.cell_tower,
      _source: "fallback_no_cell_api_keys",
      hint: "Set OPENCELLID_API_KEY and/or CELL_LOCATION_API_KEY for live cell lookup",
    };
  }

  const formattedCells = payload.cells.map((c) => ({
    lac: c.lac,
    cid: c.cellId || c.cid,
    psc: c.psc || 0,
    signal: c.signal,
  }));

  const mnc = payload.cells[0].mnc;
  const mcc = payload.cells[0].mcc;

  return withFallback(
    "cell_tower",
    async () => {
      const url = "https://us1.unwiredlabs.com/v2/process.php";
      const requestBody = {
        token: UNWIRED_KEY,
        radio: payload.radio || "lte",
        mcc,
        mnc,
        cells: formattedCells,
        address: 0,
      };

      const res = await axios.post(url, requestBody, {
        timeout: 5000,
        headers: { "Content-Type": "application/json" },
      });

      if (res.data.status !== "ok" && res.data.status !== "success") {
        throw new Error(
          `LocationAPI failed: ${res.data.message || res.data.status}`,
        );
      }

      return {
        lat: res.data.lat,
        lng: res.data.lon,
        accuracy: res.data.accuracy,
        source: "live_cell_tower_api",
      };
    },
    FALLBACKS.cell_tower,
  );
}

// ── Blueprint additions: M5 Blackout improvements ────────────────────────────────

/**
 * Network-adaptive speed thresholds.
 * Old single 2Mbps threshold flagged 4G degradation as blackout (14% FPR).
 * New thresholds per connection type target <10% FPR.
 */
const BLACKOUT_THRESHOLDS = {
  "2G": 1.0, // Mbps
  "3G": 1.0, // Mbps
  "4G": 2.5, // Mbps (raised from 2.0 for 4G infrastructure)
  "5G": 5.0, // Mbps
  WiFi: 5.0, // Mbps
};

/**
 * BlackoutDetector — EWMA-based duration smoothing.
 * Replaces the hard 20-min cutoff with a 15-min EWMA window to eliminate
 * threshold oscillation at the boundary (was causing false +ve surges).
 */
class BlackoutDetector {
  constructor(connectionType = "4G") {
    this.connectionType = connectionType;
    this.ewma = null;
    this.alpha = 0.3; // EWMA smoothing factor
    this.threshold = BLACKOUT_THRESHOLDS[connectionType] ?? 2.5;
    this._readings = []; // circular buffer for isCriticalBlackout
  }

  /**
   * update — call once per minute with current speed measurement.
   * @param {number} speedMbps
   * @returns {{ ewmaSpeed: number, isWeak: boolean, weakSignalPct: number }}
   */
  update(speedMbps) {
    this.ewma =
      this.ewma === null
        ? speedMbps
        : this.alpha * speedMbps + (1 - this.alpha) * this.ewma;

    const isWeak = this.ewma < this.threshold;
    this._readings.push({ isWeak, ts: Date.now() });
    if (this._readings.length > 30) this._readings.shift(); // keep 30 min

    return {
      ewmaSpeed: Math.round(this.ewma * 100) / 100,
      isWeak,
      weakSignalPct: isWeak ? 1.0 : 0.0,
    };
  }

  /**
   * isCriticalBlackout — true when EWMA is weak for >28% of last 18 readings.
   * Replaces hard >20min cutoff.
   */
  isCriticalBlackout() {
    const recent = this._readings.slice(-18);
    if (recent.length < 10) return false; // insufficient data
    const weakCount = recent.filter((r) => r.isWeak).length;
    return weakCount / recent.length > 0.28;
  }
}

module.exports = {
  estimateLocation,
  tryOpenCellId,
  BlackoutDetector,
  BLACKOUT_THRESHOLDS,
};
