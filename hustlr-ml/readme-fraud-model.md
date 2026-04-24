# Hustlr Phase 3 — ML Fraud Detection Microservice

> **Guidewire DEVTrails 2026** · Isolation Forest + Ring Detection · FastAPI

---

## Overview

This microservice is the machine learning layer of Hustlr's **7-layer Fraud Risk Score (FRS)** system. It runs **alongside** the existing rule engine in `fraud_engine.js` (layers 0–6) and contributes to the final weighted FPS score via the `zone_anomaly_score` component.

```
FPS = location_authenticity × 0.25
    + delivery_zone_match   × 0.20
    + news_corroboration    × 0.25
    + behavioral_fingerprint× 0.15
    + zone_anomaly_score    × 0.15   ← THIS SERVICE
```

---

## How Isolation Forest Works (Plain English)

**Isolation Forest** is an unsupervised anomaly detection algorithm that works by building many random decision trees and measuring how quickly a data point gets "isolated" into a leaf node. A normal claim event looks similar to thousands of others — it takes many random cuts to separate it. A fraudulent claim is statistically unusual (filed in 3 seconds, from a new account, inside a subnet with 80 other claimants) and gets isolated in very few cuts. The algorithm converts this isolation depth into an anomaly score from 0.0 (normal) to 1.0 (highly anomalous).

Hustlr trains the model on **50,000 synthetic Chennai Q-commerce worker events** — 95% clean behaviour (latency 180–900s, organic referrals, zero orders during disruption) and 5% simulated ring fraud (sub-15s latency, deep referral trees, shared device subnets, 40–200 simultaneous zone claims). The model learns the boundary between these populations without ever seeing labelled real fraud, making it immediately deployable without a historical fraud dataset. The trained model is serialised to `fraud_model.pkl` and loaded once at server startup for sub-millisecond inference.

---

## Integration with `fraud_engine.js`

Add **one `fetch` call** at the end of `calculateFraudScore` in `fraud_engine.js`:

```javascript
// At the top of fraud_engine.js
const ML_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

// Inside calculateFraudScore(), after the existing signal checks:
let zoneAnomalyScore = 0.0;
try {
  const mlRes = await fetch(`${ML_URL}/fraud/score`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      zone_id:                        zone,
      timestamp:                      Math.floor(Date.now() / 1000),
      device_hash:                    device_fingerprint?.substring(0, 16) ?? '',
      gps_lat:                        0.0,   // pass real GPS when available
      gps_lng:                        0.0,
      latency_seconds:                claim_latency_seconds ?? 300,
      orders_during_window:           0,
      days_since_onboarding:          daysSinceJoining,
      referral_depth:                 0,
      simultaneous_claims_zone_15min: zoneCount,
    }),
    signal: AbortSignal.timeout(3000),
  });
  const ml = await mlRes.json();
  zoneAnomalyScore = ml.isolation_forest_score;
  if (ml.is_anomalous) signals.push('ml_zone_anomaly');
} catch (_) { /* ML service offline — degrade gracefully */ }

// The existing rule score becomes the base; ML adds the zone anomaly layer
const fps = (cappedScore / 100) * 0.85 + zoneAnomalyScore * 0.15;
```

---

## The Poisson Test — Why Rings Fail It

When a genuine disruption (heavy rain, platform outage) hits a zone, workers notice it at different times depending on their shift, location, and app notification delay. Their claim filings arrive **stochastically** over the following 20–40 minutes — mathematically a **Poisson process**, where inter-arrival times follow an exponential distribution.

Coordinated fraud rings are scripted: a central bot fires all claims within a few seconds of each other, producing **uniform inter-arrival times** (near-zero variance). The ring detector runs a **Kolmogorov-Smirnov test** of the observed inter-arrival deltas against the exponential distribution implied by the sample mean. A p-value < 0.05 statistically rejects the Poisson null hypothesis — the arrivals are too uniform to be genuine. Combined with DBSCAN detecting > 5 workers within 50m of each other, both signals together trigger an immediate `human_review` recommendation.

---

## Running the Service

```bash
# Install dependencies
pip install -r requirements.txt

# Train the model (first run only — ~30s on a modern laptop)
python fraud_model.py

# Start the API server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

OpenAPI docs available at: **http://localhost:8000/docs**

---

## Sample curl Commands

### Score an individual claim

```bash
curl -X POST http://localhost:8000/fraud/score \
  -H "Content-Type: application/json" \
  -d '{
    "zone_id":                        "TN_ADYAR_07",
    "timestamp":                      1710000400,
    "device_hash":                    "a3f2e1d4c5b6a7e8",
    "gps_lat":                        13.0067,
    "gps_lng":                        80.2574,
    "latency_seconds":                420.0,
    "orders_during_window":           0,
    "days_since_onboarding":          90,
    "referral_depth":                 0,
    "simultaneous_claims_zone_15min": 8
  }'
```

Expected clean response:
```json
{
  "isolation_forest_score": 0.1823,
  "is_anomalous": false,
  "confidence": 0.6354,
  "raw_decision": 0.042,
  "threshold_used": 0.65,
  "latency_ms": 1.2
}
```

### Detect a ring across a group of claims

```bash
curl -X POST http://localhost:8000/fraud/ring-detect \
  -H "Content-Type: application/json" \
  -d '{
    "zone_id": "TN_T_NAGAR_05",
    "claims": [
      {"timestamp": 1710000400, "gps_lat": 13.0418, "gps_lng": 80.2341},
      {"timestamp": 1710000403, "gps_lat": 13.0419, "gps_lng": 80.2342},
      {"timestamp": 1710000405, "gps_lat": 13.0418, "gps_lng": 80.2340},
      {"timestamp": 1710000407, "gps_lat": 13.0417, "gps_lng": 80.2341},
      {"timestamp": 1710000408, "gps_lat": 13.0418, "gps_lng": 80.2343}
    ]
  }'
```

Expected ring response:
```json
{
  "zone_id": "TN_T_NAGAR_05",
  "poisson_result": {
    "is_coordinated_ring": true,
    "p_value": 0.0001,
    "filing_pattern": "burst",
    "mean_inter_arrival_s": 2.0
  },
  "dbscan_result": {
    "ring_detected": true,
    "cluster_count": 1,
    "tightest_cluster_radius_m": 8.2
  },
  "combined_ring_flag": true,
  "recommended_action": "human_review",
  "latency_ms": 4.7
}
```

### Check model health

```bash
curl http://localhost:8000/fraud/model-health
```

---

## File Structure

```
hustlr-ml/
├── fraud_model.py      # IsolationForest: training, feature prep, scoring
├── ring_detector.py    # Poisson inter-arrival test + DBSCAN GPS clustering
├── main.py             # FastAPI microservice (3 endpoints)
├── requirements.txt    # Python dependencies
├── fraud_model.pkl     # Trained model (auto-generated on first run)
└── readme-fraud-model.md
```

---

## Thresholds (Hustlr README aligned)

| Parameter | Value | Source |
|---|---|---|
| Anomaly threshold | 0.65 | FPS ensemble spec |
| Contamination rate | 5% | Hustlr actuarial data |
| Ring p-value ceiling | 0.05 | Statistical significance |
| DBSCAN radius | 50m | Spec requirement |
| DBSCAN min cluster | 5 workers | Spec requirement |
| Training samples | 50,000 | Spec requirement |
| Random state | 42 | Deterministic builds |
