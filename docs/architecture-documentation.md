# Hustlr: Complete System Architecture & Documentation

## 1. Executive Summary
**Hustlr** is a parametric micro-insurance platform designed to protect the incomes of gig-economy and delivery workers. In exchange for a small weekly premium (₹20 to ₹49), the system continuously monitors external conditions via APIs. When an extreme disruption occurs (like a heavy rainstorm), payouts are issued automatically with zero manual claims processing required.

To achieve this profitably, the platform relies heavily on autonomous algorithmic engines encompassing Fraud Detection, Data Trust validation, and Economic Circuit Breakers.

---

## 2. Global Architecture Stack

### Frontend (User App)
- **Framework:** Flutter / Dart
- **Design System:** Ethereal Night (Premium, dark-mode focused, glassmorphism UI)
- **State Management & Routing:** `flutter_bloc` / `Provider` and `go_router`
- **Integrations:** Google Maps, Geolocator, FL Chart, Firebase Messaging, Localizations, Hive/SharedPreferences.

### Backend (Parametric Engine)
- **Framework:** Node.js / Express
- **Database / Auth:** Supabase (PostgreSQL)
- **Orchestration:** Independent modular services acting as "Actuaries" and "Adjusters".

---

## 3. The Backend Micro-Services Ecosystem

The core intelligence lives in `hustlr-backend/src/services/`.

### A. The Data Sources
The backend constantly polls external APIs to track real-world disruptions.
- **`weather_service.js`:** Connects to OpenWeatherMap. Specifically monitors for rainfall rates (e.g., > 64.5mm/hr for Heavy Rain, > 115.6mm/hr for Cyclonic Extreme Rain) and Heat Waves (> 43°C).
- **`aqi_service.js`:** Monitors severe air quality events.
- **`traffic_service.js`:** Monitors gridlock / map disruptions.
- **`cell_tower_service.js` & `news_service.js`:** Additional context sources used for data corroboration.
- **`api_wrapper.js`:** A vital resiliency layer. If an API (like Weather) fails 3 consecutive times, it is marked as `DEGRADED`, and the system uses fallback cache data for exactly 5 minutes before retrying.

### B. The "Data Trust" Engine (`data_trust.js`)
GPS and device accelerometers are highly spoofable. Thus, Hutszr grades data on a **Trust Matrix**.
- **Tier 1 (Govt / Official - 0.90 to 1.00 Trust):** IMD data, NDMA advisories.
- **Tier 2 (Third Party - 0.70 to 0.85 Trust):** Platform logs, News, AQICN, OpenWeatherMap.
- **Tier 4 (Device Sensors - 0.20 to 0.30 Trust):** GPS, Accelerometers.

**Rule:** A single source is cross-referenced, and their combined trust must mathematically exceed a `0.75` threshold to be considered valid to trigger a payout. GPS alone is structurally incapable of triggering a claim.

### C. The Fraud Engine (`fraud_engine.js`)
To maintain zero-overhead costs, claims must self-regulate against bad actors.
The `fraud_engine` calculates an abuse score from 0-100 based on worker history:
1. **Red Flags Appended to Score:** New accounts (<14 days), mass claim spikes in a single zone, user location/zone mismatch, or claiming outside working hours (8 AM - 10 PM).
2. **Auto-Decision Router:**
   - **Score < 30:** Clean. Payout is instantly auto-approved.
   - **Score 30-60:** Soft Hold. Payout delayed for 2 hours, and payout amount is restricted.
   - **Score > 60:** Flagged. Sent immediately for manual admin review.

### D. The Economic Circuit Breaker (`circuit_breaker.js`)
An failsafe protecting the liquidity pool.
- It tracks the **Burning Cost Rate (BCR)** – which is the ratio of `Claims Paid` vs `Premiums Collected`.
- Limits are hardcoded: e.g. Max 50 claims/hour per zone, and a maximum pool BCR of 85%.
- If the fund health worsens past the 85% limit, the system forcibly halts all new policy enrollments for that city to prevent insolvency.

### E. The Payout Dispatch (`payout_service.js` & `instamojo_payout.js`)
Once cleared, the payout is triggered:
- **Tranches:** Payouts rely on an immediate 70% tranche (transferred instantly to cover urgent costs like food/petrol) and a 30% safety tranche given at the end of the week.
- Failure resilience: Transfers are retried up to 3 times before issuing a fatal `PAYOUT_FAILED` state to the Supabase database.

---

## 4. Supabase Database Logic (`supabase/hustlr_consolidated_schema.sql`)
The backend heavily delegates logic to the database layer via PostgreSQL schema-level logic and triggers:
- **Automatic Metadata:** Always syncing `updated_at`.
- **Pool Synchronization:** Automatically increments/decrements active_policies counts in `risk_pools` when policies change state.
- **Financial Auto-Compute:** When a claim status updates to `SETTLED`, a trigger computes and adds the loss amount directly replacing `total_claims_paid` and re-computing `loss_ratio` locally on the DB side.
- **Baseline Generation:** Automatically creates a `fraud_baselines` entry and a formatted short `referral_code` when a new user signs up.

---

## 5. Frontend App (Key Modules)

Located in `lib/features/`:

- **Auth & Onboarding:** Handles initial phone/email registration and basic KYC setups.
- **Dashboard (`dashboard`):** Realtime tracking of active weather, wallet balances, and current disruptions.
- **Policy Management (`policy`):** Screen for gig workers to read Actuary logic and choose weekly plans (Basic vs. Standard).
- **Wallet (`wallet`):** Financial ledger tracking payouts vs premiums.
- **Claims Module (`claims`):**
  - Most claims are automated.
  - **Manual Fallback System:** Should automatic APIs miss highly localized events (like a fallen tree), a worker can lodge a manual claim.
  - The manual flow involves screens like `manual_claim_camera_screen.dart` featuring an enforced AI reticle over the camera pane, which mandates live capture of photos avoiding gallery uploads, followed by an evidence submission flow (`manual_evidence_screen.dart`).

## 6. How a Claim Actually Works (End-to-End Run)

1. **Purchase:** Worker buys a £29 shield for the week mapping to a designated Zone. (Added to DB, DB Trigger updates pool liquidity).
2. **Adverse Event:** Heat wave registers 44°C on `weather_service.js`.
3. **Assessment Check:** The event throws an assessed disruption. The API reliability is confirmed (`api_wrapper.js`). Trust factor ensures it comes from a verified source (`data_trust.js`).
4. **Fraud Check:** System checks the timestamp, the user's location, and their recent history. (Yields a score of 12 = Auto-Approve).
5. **Circuit Failsafe:** System checks if the city's pool BCR isn't crashing (BCR: 44%).
6. **Execution:** The Instamojo API sends ₹250 directly to the driver's linked account while they are safely waiting in the shade.
