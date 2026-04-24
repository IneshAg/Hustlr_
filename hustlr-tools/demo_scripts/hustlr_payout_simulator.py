"""
hustlr_payout_simulator.py
Instant Payout Demo Simulator — Phase 3
Code Crafters | Guidewire DEVTrails 2026
FLOW:
  1. inject_rain_event()   → Writes disruption to Supabase (triggers worker notification)
  2. run_fraud_check()     → Score claim via M3++ (score_claim from m3_fraud_detector.py)
  3. trigger_mock_payout() → POST mock Generic UPI webhook → Node.js handler → DB update
DEMO OUTCOME:
  Worker sees: "Heavy rain detected → Claim submitted → AI approved → ₹ 450 paid"
  Total elapsed: < 3 seconds in demo mode
"""
import time
import uuid
import hmac
import hashlib
import json
import requests
import os
from datetime import datetime, timezone
# ── Config (set via environment or hardcode for demo) ─────────────────────
SUPABASE_URL      = os.environ.get("SUPABASE_URL",  "http://localhost:54321")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_KEY",  "demo_key_123")
BACKEND_URL       = os.environ.get("BACKEND_URL",   "http://localhost:3001")
# Mock Generic UPI webhook secret — set in environment to match backend .env
MOCK_WEBHOOK_SECRET = os.environ.get("MOCK_WEBHOOK_SECRET", "")
# Generic UPI requirement stripped per user request
# Supabase headers
SB_HEADERS = {
    "apikey":        SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type":  "application/json",
    "Prefer":        "return=representation",
}
# Demo payout amount ( INR  per disruption hour — from insurance policy config)
PAYOUT_AMOUNT_PAISA = 45000  # INR 450 in paisa (Generic UPI uses paisa)
# ── PART A: Rain Event Injector ───────────────────────────────────────────
def inject_rain_event(
    worker_id:  str,
    zone_id:    str,
    precip_mm:  float = 8.5,   # above 5mm threshold → heavy_rain trigger
    latitude:   float = 13.0827,
    longitude:  float = 80.2707,
) -> dict:
    """
    Write a synthetic heavy_rain disruption event into Supabase.
    The platform's PostgreSQL trigger fires → Supabase realtime pushes
    to the worker's Flutter app within ~300ms.
    """
    event_id = str(uuid.uuid4())
    now_ist  = datetime.now(timezone.utc).isoformat()
    payload = {
        "id":               event_id,
        "worker_id":        worker_id,
        "zone_id":          zone_id,
        "disruption_type":  "heavy_rain",
        "precip_mm":        precip_mm,
        "latitude":         latitude,
        "longitude":        longitude,
        "detected_at":      now_ist,
        "source":           "DEMO_INJECTOR",    # flag for demo filtering
        "status":           "DETECTED",
    }
    print(f"\n[INJECTOR] Writing rain event for worker {worker_id} ...")
    print(f"           Zone     : {zone_id}")
    print(f"           Precip   : {precip_mm} mm/hr (threshold: 5.0 mm/hr)")
    print(f"           Location : ({latitude:.4f}, {longitude:.4f})")
    try:
        resp = requests.post(
            f"{SUPABASE_URL}/rest/v1/disruption_events",
            headers=SB_HEADERS,
            json=payload,
            timeout=5,
        )
        if resp.status_code in (200, 201):
            print(f"[INJECTOR] Supabase write OK → event_id={event_id}")
            print(f"[INJECTOR] Realtime push → worker Flutter app in ~300ms")
            return {"event_id": event_id, "payload": payload}
        else:
            print(f"[INJECTOR] ERROR: {resp.status_code} {resp.text}")
            return {"error": resp.text}
    except requests.exceptions.ConnectionError:
        print(f"[INJECTOR] (Demo mode: Supabase not reachable. Simulating rain event 8.5mm.)")
        return {"event_id": event_id, "payload": payload}
# ── M3++ Integration Bridge ────────────────────────────────────────────────
def run_fraud_check_demo(worker_id: str, event_id: str) -> dict:
    """
    In the demo, simulate a near-perfect clean claim (no fraud flags).
    In production, call score_claim() from m3_fraud_detector.py.
    Returns fraud decision dict.
    """
    print(f"\n[M3++]     Scoring claim for worker {worker_id} ...")
    time.sleep(0.4)   # simulate 400ms ML inference
    # Demo: clean claim scores 0.05 → AUTO_APPROVE
    result = {
        "claim_id":   f"CLM-{event_id[:8].upper()}",
        "risk_score": 0.05,
        "decision":   "AUTO_APPROVE",
        "flags":      [],
        "inference_ms": 412,
    }
    print(f"[M3++]     Risk Score : {result['risk_score']} (threshold: 0.30)")
    print(f"[M3++]     Decision   : {result['decision']}")
    print(f"[M3++]     Flags      : none — clean claim")
    return result
# ── PART B: Mock Generic UPI Webhook Sender ─────────────────────────────────
def _sign_webhook(body: bytes, secret: str) -> str:
    """Compute HMAC-SHA256 signature matching Generic UPI's webhook format."""
    return hmac.new(
        secret.encode("utf-8"), body, hashlib.sha256
    ).hexdigest()
def trigger_mock_payout(
    worker_id:      str,
    event_id:       str,
    claim_id:       str,
    amount_paisa:   int = PAYOUT_AMOUNT_PAISA,
) -> dict:
    """
    POST a mock Generic UPI payment.captured webhook to the Node.js backend.
    The backend handler:
      1. Verifies HMAC signature
      2. Writes to Supabase payouts table
      3. Supabase realtime → Flutter app → shows " INR 450 paid"
    Node.js handler stub (server/routes/webhook.js):
    ─────────────────────────────────────────────────
    router.post('/upi', express.raw({type:'*/*'}), (req, res) => {
      const sig = req.headers['x-upi-signature'];
      const expected = hmac(MOCK_WEBHOOK_SECRET, req.body).hexdigest();
      if (sig !== expected) return res.status(400).send('Invalid sig');
      const evt = JSON.parse(req.body);
      if (evt.event === 'payment.captured') {
        supabase.from('payouts').insert({
          worker_id:   evt.payload.payment.entity.notes.worker_id,
          event_id:    evt.payload.payment.entity.notes.event_id,
          amount_inr:  evt.payload.payment.entity.amount / 100,
          status:      'PAID',
          paid_at:     new Date().toISOString(),
        });
      }
      res.json({ status: 'ok' });
    });
    """
    payment_id = f"pay_DEMO{uuid.uuid4().hex[:12].upper()}"
    order_id   = f"order_DEMO{uuid.uuid4().hex[:10].upper()}"
    webhook_body = {
        "event":   "payment.captured",
        "entity":  "event",
        "payload": {
            "payment": {
                "entity": {
                    "id":       payment_id,
                    "order_id": order_id,
                    "amount":   amount_paisa,
                    "currency": "INR",
                    "status":   "captured",
                    "method":   "upi",
                    "notes": {
                        "worker_id":       worker_id,
                        "event_id":        event_id,
                        "claim_id":        claim_id,
                        "disruption_type": "heavy_rain",
                        "platform":        "hustlr_demo",
                    },
                }
            }
        },
    }
    if not MOCK_WEBHOOK_SECRET:
        raise RuntimeError("MOCK_WEBHOOK_SECRET is required to sign payout webhooks")

    body_bytes = json.dumps(webhook_body, separators=(",", ":")).encode("utf-8")
    signature  = _sign_webhook(body_bytes, MOCK_WEBHOOK_SECRET)
    headers = {
        "Content-Type":            "application/json",
        "X-Hustlr-Signature":    signature,
        "X-Hustlr-Event-Id":     str(uuid.uuid4()),
    }
    print(f"\n[PAYOUT]   Sending mock Generic UPI webhook ...")
    print(f"           Payment ID : {payment_id}")
    print(f"           Amount     : INR {amount_paisa/100:.0f}")
    print(f"           Method     : UPI")
    try:
        resp = requests.post(
            f"{BACKEND_URL}/api/webhooks/payout",
            data=body_bytes,
            headers=headers,
            timeout=5,
        )
        if resp.status_code == 200:
            print(f"[PAYOUT]   Backend accepted webhook → Supabase payouts table updated")
            print(f"[PAYOUT]   Realtime → Worker UI shows 'Payment Captured'")
        else:
            print(f"[PAYOUT]   Backend response: {resp.status_code} {resp.text}")
    except requests.exceptions.ConnectionError:
        # Demo fallback: simulate success even if backend is not running
        print(f"[PAYOUT]   (Demo mode: backend not running — simulating success)")
    return {
        "payment_id": payment_id,
        "order_id":   order_id,
        "amount_inr": amount_paisa / 100,
        "status":     "captured",
        "signature":  signature[:16] + "...",
    }
# ── Full Demo Flow ─────────────────────────────────────────────────────────
def run_demo_flow():
    """
    Execute the full "Fake Storm → AI Approval → UPI Payout" flow.
    This is what runs during the demo video recording.
    Target: all three steps complete within 3 seconds on screen.
    """
    DEMO_WORKER = "WKR-DEMO-001"
    DEMO_ZONE   = "891e35a3cffffff"   # Chennai zone (H3 R9)
    print("\n" + "="*60)
    print("  HUSTLR DEMO FLOW — Phase 3 Payout Simulator")
    print("  Code Crafters | Guidewire DEVTrails 2026")
    print("="*60)
    t0 = time.time()
    # Step 1: Inject rain event (simulates real weather trigger)
    event_result = inject_rain_event(
        worker_id  = DEMO_WORKER,
        zone_id    = DEMO_ZONE,
        precip_mm  = 8.5,
        latitude   = 13.0827,
        longitude  = 80.2707,
    )
    event_id = event_result.get("event_id", "evt_fallback")
    time.sleep(0.3)  # simulate realtime propagation
    # Step 2: M3++ Fraud Check (auto-approve for demo clean claim)
    fraud_result = run_fraud_check_demo(DEMO_WORKER, event_id)
    claim_id     = fraud_result["claim_id"]
    if fraud_result["decision"] == "AUTO_APPROVE":
        time.sleep(0.2)  # brief pause for drama
        # Step 3: Trigger mock payout
        payout_result = trigger_mock_payout(
            worker_id    = DEMO_WORKER,
            event_id     = event_id,
            claim_id     = claim_id,
            amount_paisa = 45000,  # ₹ 450
        )
        elapsed = time.time() - t0
        print(f"\n{'='*60}")
        print(f"  DEMO COMPLETE in {elapsed:.2f}s")
        print(f"  Payment ID : {payout_result['payment_id']}")
        print(f"  Amount     : INR {payout_result['amount_inr']:.0f}")
        print(f"  Worker UI  : 'Payment Captured - INR 450 credited via UPI'")
        print(f"{'='*60}\n")
    else:
        print(f"\n[FLOW] Claim flagged for MANUAL_REVIEW — no payout in demo mode")
if __name__ == "__main__":
    run_demo_flow()
