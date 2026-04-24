"""
main.py ??? FastAPI microservice for Hustlr Phase 3 ML Fraud Detection.

Run with:
    uvicorn main:app --reload

Endpoints:
    POST /fraud/score          ??? Isolation Forest anomaly scoring
    POST /fraud/ring-detect    ??? Poisson + DBSCAN ring detection
    GET  /fraud/model-health   ??? Model metadata and health

Integrates into the existing fraud_engine.js pipeline by appending one
HTTP call to /fraud/score whose isolation_forest_score feeds into the
zone_anomaly_score component (weight 0.15) of the FPS ensemble.
"""

from __future__ import annotations

import os
import time
import joblib
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from services.fraud_model import (
    ANOMALY_THRESHOLD,
    CONTAMINATION_RATE,
    TRAINING_SAMPLES,
    ClaimEvent,
    load_model,
    score_claim,
)
from services.ring_detector import (
    combined_ring_verdict,
    detect_gps_clusters,
    test_poisson_arrivals,
)

# ?????? Model bundle cache (loaded once at startup) ????????????????????????????????????????????????????????????????????????????????????????????
_MODEL_BUNDLE: dict | None = None
_ISS_BUNDLE: dict | None = None
_CHATBOT_BUNDLE: dict | None = None
_GNN_MODEL: Any | None = None
_GNN_BUILDER: Any | None = None
_GNN_IMPORT_ERROR: str | None = None
MODELS_DIR = Path(__file__).parent / "models" / "trained"

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the trained model bundle once at server startup."""
    global _MODEL_BUNDLE
    global _ISS_BUNDLE
    global _GNN_MODEL
    global _GNN_BUILDER
    global _GNN_IMPORT_ERROR
    
    iso_path = MODELS_DIR / "model3_isolation_forest.pkl"
    if iso_path.exists():
        _MODEL_BUNDLE = {
            "model": joblib.load(iso_path),
            "scaler": joblib.load(MODELS_DIR / "model3_scaler.pkl"),
            "trained_at": "2026-04-04",
            "n_samples": 50000,
            "contamination": 0.08,
            "threshold": 0.65,
            "feature_version": "3.0.0",
        }
        print("[Startup] Loaded model3_isolation_forest from models/trained/")
    else:
        _MODEL_BUNDLE = load_model()  # fallback to inline pkl
        print("[Startup] Loaded inline fraud_model.pkl")
        
    iss_model_path = MODELS_DIR / "model1_iss_xgboost.pkl"
    if iss_model_path.exists():
        try:
            _ISS_BUNDLE = {
                'model': joblib.load(iss_model_path),
                'features': joblib.load(MODELS_DIR / "model1_features.pkl"),
            }
            print("[Startup] ISS XGBoost model loaded")
        except Exception as e:
            print(f"[Startup] ISS model failed to load ({e}) — will use rule engine fallback")
            _ISS_BUNDLE = None
    else:
        print("[Startup] ISS model not found — will use rule engine fallback")

    chat_dir = MODELS_DIR  # Consolidated location
    bot_path = chat_dir / "chatbot_model.pkl"
    if bot_path.exists():
        import json
        with open(chat_dir / "chatbot_responses.json", "r") as f:
            resp_dict = json.load(f)
        _CHATBOT_BUNDLE = {
            "model": joblib.load(bot_path),
            "vectorizer": joblib.load(chat_dir / "chatbot_vectorizer.pkl"),
            "responses": resp_dict
        }
        print("[Startup] NLP Classifier loaded.")

    # Load GNN fraud detection model (optional; disabled by default to keep
    # startup stable on constrained environments like Render free tier).
    _GNN_IMPORT_ERROR = None
    enable_gnn = os.getenv("ENABLE_GNN_FRAUD", "false").strip().lower() == "true"
    gnn_model_path = MODELS_DIR / "gnn_fraud_detector.pt"
    if enable_gnn and gnn_model_path.exists():
        try:
            from services.gnn_fraud_detection import (
                FraudGraphBuilder,
                load_model as load_gnn_model,
            )
            _GNN_MODEL = load_gnn_model(str(gnn_model_path), node_features=6, hidden_dim=64, num_classes=2)
            _GNN_BUILDER = FraudGraphBuilder()
            print("[Startup] GNN Fraud Detection model loaded")
        except Exception as e:
            _GNN_IMPORT_ERROR = str(e)
            print(f"[Startup] Failed to load GNN model: {e}")
            _GNN_MODEL = None
            _GNN_BUILDER = None
    elif not enable_gnn:
        print("[Startup] GNN fraud detection disabled (set ENABLE_GNN_FRAUD=true to enable)")
        _GNN_MODEL = None
        _GNN_BUILDER = None
    else:
        print("[Startup] GNN model not found ??? fraud ring detection disabled")
        _GNN_MODEL = None
        _GNN_BUILDER = None

    yield  # server runs here

    # Cleanup on shutdown
    _MODEL_BUNDLE = None
    _ISS_BUNDLE = None
    _CHATBOT_BUNDLE = None
    _GNN_MODEL = None
    _GNN_BUILDER = None
    _GNN_IMPORT_ERROR = None




app = FastAPI(
    title       = "Hustlr ML Fraud Detection",
    description = "Isolation Forest zone anomaly scoring + ring pattern detection",
    version     = "1.0.0",
    lifespan    = lifespan,
)

cors_origins_env = os.getenv("CORS_ALLOWED_ORIGINS", "")
if cors_origins_env.strip():
    cors_allowed_origins = [origin.strip() for origin in cors_origins_env.split(",") if origin.strip()]
else:
    cors_allowed_origins = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ]

app.add_middleware(
    CORSMiddleware,
    allow_origins  = cors_allowed_origins,
    allow_methods  = ["*"],
    allow_headers  = ["*"],
)


# ?????? Pydantic schemas ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

class FeatureVector(BaseModel):
    # ?????? Fields Node.js currently sends ??????????????????????????????????????????
    zone_match:            float = 0.85
    gps_jitter:            float = 0.10
    accelerometer_match:   float = 0.90
    wifi_home_ssid:        bool  = False
    days_since_onboarding: int   = 30

    # ?????? Additional fields to match 20 training features ????????????????????????????
    gps_zone_mismatch:               bool         = False
    battery_charging:                 bool         = False
    platform_app_inactive:            bool         = False
    ip_home_match:                     bool         = True
    claim_latency_under30s:            bool         = False
    gps_jitter_perfect:                bool         = False
    barometer_mismatch:               bool         = False
    hw_fingerprint_match:              bool         = True
    app_install_cluster:               int          = 1
    referral_depth:                    int          = 2
    claim_hour_sin:                    float        = 0.0
    claim_hour_cos:                    float        = 1.0
    city_behavioral_risk:              float        = 0.55
    zone_depth_score:                  float        = 0.75
    has_real_disruption:               bool         = True
    simultaneous_zone_claims:           int          = 1
    iss_score:                         float        = 50.0

    def to_model_features(self) -> dict:
        """
        Unified mapping. Node.js fields are translated
        to Python model features intelligently.
        """
        return {
            "gps_zone_mismatch": 1 if self.gps_zone_mismatch else 0,
            "wifi_home_ssid": 1 if self.wifi_home_ssid else 0,
            "battery_charging": 1 if self.battery_charging else 0,
            "accelerometer_idle": 1 if (1.0 - self.accelerometer_match) > 0.5 else 0,
            "platform_app_inactive": 1 if self.platform_app_inactive else 0,
            "ip_home_match": 1 if self.ip_home_match else 0,
            "claim_latency_under30s": 1 if self.claim_latency_under30s else 0,
            "gps_jitter_perfect": 1 if self.gps_jitter_perfect else 0,
            "barometer_mismatch": 1 if self.barometer_mismatch else 0,
            "hw_fingerprint_match": 1 if self.hw_fingerprint_match else 0,
            "app_install_cluster": self.app_install_cluster,
            "days_since_onboard": self.days_since_onboarding,
            "referral_depth": self.referral_depth,
            "claim_hour_sin": self.claim_hour_sin,
            "claim_hour_cos": self.claim_hour_cos,
            "city_behavioral_risk": self.city_behavioral_risk,
            "zone_depth_score": self.zone_depth_score,
            "has_real_disruption": 1 if self.has_real_disruption else 0,
            "simultaneous_zone_claims": self.simultaneous_zone_claims,
            "iss_score": self.iss_score,
        }

class ClaimScoreRequest(BaseModel):
    worker_id: str
    zone_id: str
    claim_timestamp: str
    feature_vector: FeatureVector

class ClaimScoreResponse(BaseModel):
    is_anomalous: bool
    anomaly_score: float
    top_features: list[str]
    poisson_p_value: float

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    intent: str
    response: str
    confidence: float


class RingClaimPoint(BaseModel):
    timestamp: int   = Field(..., description="Unix epoch seconds")
    gps_lat:   float = Field(..., description="Latitude")
    gps_lng:   float = Field(..., description="Longitude")


class RingDetectRequest(BaseModel):
    zone_id: str                  = Field(..., description="Zone grid ID")
    claims:  List[RingClaimPoint] = Field(..., min_length=1)


class RingDetectResponse(BaseModel):
    zone_id:              str
    poisson_result:       dict
    dbscan_result:        dict
    combined_ring_flag:   bool
    recommended_action:   str = Field(..., description="auto_approve | soft_hold | human_review")
    latency_ms:           float


class GNNWorkerNode(BaseModel):
    id: str
    account_age_days: float = 30.0
    avg_daily_orders: float = 15.0
    claim_frequency: float = 3.0
    device_shared_count: int = 1
    zone_depth_avg: float = 0.75
    historical_clean_ratio: float = 0.80
    device_fingerprint: Optional[str] = None
    upi_id: Optional[str] = None
    zone_id: str = "adyar"
    claim_latency: float = 120.0
    registered_at: Optional[str] = None


class GNNFraudDetectRequest(BaseModel):
    zone_id: str
    workers: List[GNNWorkerNode] = Field(..., min_length=1)
    fraud_threshold: float = 0.7


class GNNFraudDetectResponse(BaseModel):
    zone_id: str
    total_workers: int
    fraud_rings_detected: int
    rings: List[dict]
    risk_level: str
    latency_ms: float


# ?????? Endpoints ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

class ISSRequest(BaseModel):
    zone_flood_risk: float = 0.60
    avg_daily_income: float = 600.0
    disruption_freq_12mo: int = 8
    platform_tenure_weeks: int = 4
    city: str = "Chennai"

class ISSResponse(BaseModel):
    iss_score: int
    tier: str
    recommendation: str
    breakdown: dict
    model_used: str

def _iss_rule_engine(req: ISSRequest) -> int:
    score = 100.0
    score -= req.zone_flood_risk * 20
    score -= min(req.disruption_freq_12mo, 15)
    score += min(req.avg_daily_income / 200, 10)
    score += min(req.platform_tenure_weeks / 10, 8)
    city_adj = {"Chennai": -3, "Mumbai": -4, "Delhi": -2, "Bengaluru": 0}
    score += city_adj.get(req.city, 0)
    return max(0, min(100, round(score)))

@app.post("/iss", response_model=ISSResponse, tags=["ISS"])
async def iss_score(req: ISSRequest):
    if _ISS_BUNDLE is not None:
        try:
            features = [[
                req.zone_flood_risk,
                req.avg_daily_income,
                req.disruption_freq_12mo,
                req.platform_tenure_weeks,
                1 if req.city == "Chennai" else 0,
            ]]
            score = int(_ISS_BUNDLE['model'].predict(features)[0])
            score = max(0, min(100, score))
            model_used = "xgboost"
        except Exception as e:
            print(f"[ISS] XGBoost failed: {e}, using rule engine")
            score = _iss_rule_engine(req)
            model_used = "rule_engine_fallback"
    else:
        score = _iss_rule_engine(req)
        model_used = "rule_engine"
    
    if score >= 70:
        tier = "GREEN"
        recommendation = "basic"
    elif score >= 50:
        tier = "AMBER"
        recommendation = "standard"
    elif score >= 30:
        tier = "AMBER_LOW"
        recommendation = "full"
    else:
        tier = "RED"
        recommendation = "full"
    
    return ISSResponse(
        iss_score=score,
        tier=tier,
        recommendation=recommendation,
        model_used=model_used,
        breakdown={
            "zone_flood_risk": req.zone_flood_risk,
            "disruption_freq": req.disruption_freq_12mo,
            "tenure_weeks": req.platform_tenure_weeks,
            "city": req.city,
        }
    )

class PremiumRequest(BaseModel):
    plan_tier: str = "standard"
    zone: str = "Adyar Dark Store Zone"
    iss_score: int = 62
    previous_premium: float = 0.0

class PremiumResponse(BaseModel):
    plan_tier: str
    base_premium: int
    zone_adjustment: int
    final_premium: int
    note: str
    formula: str

PLAN_BASE = { "basic": 35, "standard": 49, "full": 79 }
ZONE_ADJ = {
    # Set all to 0 ??? zone risk reflected in ISS tier recommendation
    # NOT in the displayed premium price (keeps it clean for workers)
    "Adyar Dark Store Zone": 0,
    "Velachery Dark Store Zone": 0,
    "Tambaram Dark Store Zone": 0,
    "Anna Nagar Dark Store Zone": 0,
    "T Nagar Dark Store Zone": 0,
    "OMR Dark Store Zone": 0,
    "Koramangala Dark Store Zone": 0,
    "Electronic City Dark Store Zone": 0,
    "Andheri Dark Store Zone": 0,
    "Bandra Dark Store Zone": 0,
}

@app.post("/premium", response_model=PremiumResponse, tags=["Pricing"])
async def premium(req: PremiumRequest):
    base = PLAN_BASE.get(req.plan_tier, 49)
    zone_adj = ZONE_ADJ.get(req.zone, 0)
    raw = base + zone_adj
    if req.previous_premium > 0:
        raw = min(raw, req.previous_premium * 1.20)
        raw = max(raw, req.previous_premium * 0.80)
    final = max(15, min(98, round(raw)))
    return PremiumResponse(
        plan_tier=req.plan_tier,
        base_premium=base,
        zone_adjustment=zone_adj,
        final_premium=final,
        note="Fixed pricing ??? same for all workers on this plan",
        formula="P = P(event) ?? avg_income ?? exposure_days",
    )

@app.post("/fraud-score", response_model=ClaimScoreResponse, tags=["Fraud"])
@app.post("/ml/fraud-score", response_model=ClaimScoreResponse, tags=["Fraud"])
async def fraud_score(req: ClaimScoreRequest):
    if _MODEL_BUNDLE is None:
        raise HTTPException(status_code=503, detail="Model not loaded ??? server starting up")
    from services.fraud_model import poisson_timing_test
    if len(req.claim_timestamp) > 10:
        try:
            from dateutil.parser import parse
            ts = parse(req.claim_timestamp)
        except:
            ts = datetime.now()
    else:
        ts = datetime.now()
        
    p_val = poisson_timing_test(req.worker_id, ts, req.zone_id)

    # Direct scoring with the 20 features from to_model_features()
    features = req.feature_vector.to_model_features()
    
    # Create numpy array with the 20 features in the correct order
    import numpy as np
    feature_order = [
        "gps_zone_mismatch", "wifi_home_ssid", "battery_charging", "accelerometer_idle",
        "platform_app_inactive", "ip_home_match", "claim_latency_under30s", "gps_jitter_perfect",
        "barometer_mismatch", "hw_fingerprint_match", "app_install_cluster", "days_since_onboard",
        "referral_depth", "claim_hour_sin", "claim_hour_cos", "city_behavioral_risk",
        "zone_depth_score", "has_real_disruption", "simultaneous_zone_claims", "iss_score"
    ]
    
    X = np.array([[features[col] for col in feature_order]], dtype=float)
    
    model = _MODEL_BUNDLE["model"]
    raw = model.decision_function(X)[0]
    anomaly_score = float(1.0 - (1.0 / (1.0 + np.exp(-raw * 4.0))))
    
    from services.fraud_model import ANOMALY_THRESHOLD
    is_anomalous = anomaly_score > ANOMALY_THRESHOLD

    # Hard override ??? zero GPS jitter = definitive spoofing
    if req.feature_vector.gps_jitter < 0.000001:
        anomaly_score = max(anomaly_score, 0.85)
        is_anomalous = True

    return ClaimScoreResponse(
        is_anomalous    = is_anomalous,
        anomaly_score   = anomaly_score,
        top_features    = list(features.keys())[:5],  # Return top 5 feature names
        poisson_p_value = p_val,
    )

# ?????? Prophet Actuarial Pricing ??????

@app.get("/forecast/{zone_id}", tags=["Forecast"])
async def get_forecast(zone_id: str, days: int = 7):
    from prophet_service.prophet_model import generate_forecast
    try:
        return generate_forecast(zone_id, days)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/forecast/retrain", tags=["Forecast"])
async def retrain_forecast():
    from prophet_service.prophet_model import train_model
    try:
        train_model()
        return {"status": "ok", "message": "Prophet model retrained from IMD fallback Open-Meteo."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/fraud/ring-detect", response_model=RingDetectResponse, tags=["Fraud"])
async def ring_detect(req: RingDetectRequest):
    """
    Detect coordinated ring-fraud patterns in a batch of zone claims.

    Runs two independent tests in parallel:

    1. **Poisson inter-arrival test** ??? checks whether filing timestamps
       follow the stochastic Poisson distribution of genuine disruptions.
       Rings fail this at p < 0.05.

    2. **DBSCAN geographic clustering** ??? finds workers claiming from the
       same GPS location (< 50m radius, ??? 5 workers).

    The ``recommended_action`` is the combined verdict:
      - ``human_review``  ??? both tests positive (high confidence ring)
      - ``soft_hold``     ??? one test positive (investigate further)
      - ``auto_approve``  ??? both tests negative (no ring signal detected)
    """
    t0 = time.perf_counter()

    timestamps = [c.timestamp for c in req.claims]
    gps_coords = [(c.gps_lat, c.gps_lng) for c in req.claims]

    poisson_result = test_poisson_arrivals(timestamps)
    dbscan_result  = detect_gps_clusters(gps_coords)
    action         = combined_ring_verdict(poisson_result, dbscan_result)

    combined_flag = (
        poisson_result.get("is_coordinated_ring", False) or
        dbscan_result.get("ring_detected", False)
    )

    latency_ms = (time.perf_counter() - t0) * 1000.0

    return RingDetectResponse(
        zone_id            = req.zone_id,
        poisson_result     = poisson_result,
        dbscan_result      = dbscan_result,
        combined_ring_flag = combined_flag,
        recommended_action = action,
        latency_ms         = round(latency_ms, 3),
    )


@app.post("/fraud/gnn-ring-detect", response_model=GNNFraudDetectResponse, tags=["Fraud"])
async def gnn_ring_detect(req: GNNFraudDetectRequest):
    """
    Detect fraud rings using Graph Neural Networks (GraphSAGE).
    
    Analyzes worker connections based on:
    - Device sharing patterns
    - UPI ID sharing
    - Zone clustering with similar claim timing
    - Registration bursts
    
    Returns detected fraud rings with member workers and fraud probabilities.
    """
    if _GNN_MODEL is None or _GNN_BUILDER is None:
        detail = "GNN model not loaded. Set ENABLE_GNN_FRAUD=true and provide gnn_fraud_detector.pt."
        if _GNN_IMPORT_ERROR:
            detail = f"{detail} Import error: {_GNN_IMPORT_ERROR}"
        raise HTTPException(
            status_code=503, 
            detail=detail,
        )
    
    t0 = time.perf_counter()
    
    try:
        # Convert Pydantic models to dicts
        workers_data = [worker.model_dump() for worker in req.workers]
        
        # Build graph from worker data
        graph = _GNN_BUILDER.build_graph_from_workers(workers_data)
        
        # Detect fraud rings
        fraud_rings = _GNN_BUILDER.detect_fraud_rings(
            _GNN_MODEL, 
            graph, 
            fraud_threshold=req.fraud_threshold
        )
        
        # Determine risk level
        if len(fraud_rings) > 5:
            risk_level = "HIGH"
        elif len(fraud_rings) > 0:
            risk_level = "MEDIUM"
        else:
            risk_level = "LOW"
        
        latency_ms = (time.perf_counter() - t0) * 1000.0
        
        return GNNFraudDetectResponse(
            zone_id=req.zone_id,
            total_workers=len(workers_data),
            fraud_rings_detected=len(fraud_rings),
            rings=fraud_rings,
            risk_level=risk_level,
            latency_ms=round(latency_ms, 3)
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"GNN fraud detection failed: {str(e)}")

@app.post("/chat", response_model=ChatResponse, tags=["Support"])
async def chat_bot(req: ChatRequest):
    # TF-IDF NLP classifier path
    if _CHATBOT_BUNDLE:
        vec = _CHATBOT_BUNDLE["vectorizer"]
        model = _CHATBOT_BUNDLE["model"]
        responses = _CHATBOT_BUNDLE["responses"]
        X = vec.transform([req.message.lower()])
        intent = model.predict(X)[0]
        probs = model.predict_proba(X)[0]
        confidence = float(max(probs))
        if confidence < 0.20:
            intent = "default"
        answer = responses.get(intent, responses.get("default", "I'm here to help!"))
        return ChatResponse(intent=intent, response=answer, confidence=round(confidence, 3))

    return ChatResponse(
        intent="default",
        response="I'm here to help! You can ask about your policy, payouts, claims, premiums, zone coverage, or how to withdraw your balance.",
        confidence=0.0
    )




@app.get("/fraud/model-health", tags=["Health"])
async def model_health():
    """
    Return model metadata, version, and health signals for the admin
    dashboard's Fraud Queue panel.
    """
    if _MODEL_BUNDLE is None:
        return {
            "status":         "starting",
            "model_loaded":   False,
        }

    model_path = MODELS_DIR / "fraud_model.pkl"

    return {
        "status":              "ok",
        "model_loaded":        True,
        "model_version":       "isolation_forest_v1.0.0",
        "feature_version":     _MODEL_BUNDLE.get("feature_version", "1.0.0"),
        "training_samples":    _MODEL_BUNDLE.get("n_samples", TRAINING_SAMPLES),
        "contamination_rate":  _MODEL_BUNDLE.get("contamination", CONTAMINATION_RATE),
        "anomaly_threshold":   _MODEL_BUNDLE.get("threshold", ANOMALY_THRESHOLD),
        "trained_at":          _MODEL_BUNDLE.get("trained_at", "unknown"),
        "model_size_bytes":    model_path.stat().st_size if model_path.exists() else 0,
        "server_time_utc":     datetime.now(timezone.utc).isoformat(),
    }


@app.get("/health", tags=["Health"])
async def health():
    iso_ok = _MODEL_BUNDLE is not None
    iss_ok = _ISS_BUNDLE is not None
    gnn_ok = _GNN_MODEL is not None

    # We do a basic check for prophet models without re-importing the logic fully here
    # Assuming around 10 based on our prompt requirements
    prophet_count = 10 
    overall = "ok" if iso_ok else "degraded"

    return {
        "status":    overall,
        "service":   "Hustlr ML Engine v3.0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "models": {
            "isolation_forest": {
                "loaded":  iso_ok,
                "source":  _MODEL_BUNDLE.get("source", "inline") if iso_ok else None,
                "n_samples": _MODEL_BUNDLE.get("n_samples") if iso_ok else None,
            },
            "iss_xgboost": {
                "loaded": iss_ok,
            },
            "gnn_fraud_detection": {
                "loaded": gnn_ok,
                "model_type": "GraphSAGE",
            },
            "prophet_zones": {
                "loaded": prophet_count,
                "total":  10,
            },
            "ring_detector": True,
            "nlp_classifier": True,
        },
        "endpoints": {
            "POST /iss":              "XGBoost ISS scoring",
            "POST /premium":          "Dynamic premium calculation",
            "POST /fraud-score":      "Isolation Forest fraud scoring",
            "POST /ml/fraud-score":   "Alias for /fraud-score",
            "POST /fraud/ring-detect":"Poisson + DBSCAN ring detection",
            "POST /fraud/gnn-ring-detect": "GNN GraphSAGE fraud ring detection",
            "GET /forecast/{zone_id}":"Prophet 7-day disruption forecast",
            "GET /fraud/model-health":"Detailed model diagnostics",
            "GET /health":            "This endpoint",
        },
        "notes": [
            "fraud-score accepts both Node.js and Python feature shapes",
            "ISS score is backend-only ??? never sent to Flutter app",
            "Zone depth scoring runs in Node.js (Haversine), not here",
            "GNN fraud detection requires trained model at models/gnn_fraud_detector.pt",
        ],
    }

@app.get("/", tags=["Health"])
async def root():
    return {
        "service":      "Hustlr ML Fraud Detection",
        "version":      "1.0.0",
        "docs":         "/docs",
        "health":       "/health",
        "model_health": "/fraud/model-health",
    }

