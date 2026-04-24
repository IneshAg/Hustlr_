# Chennai zones in Hustlr ML

## What is in code today

- **`ml_cherry_picks.CHENNAI_LOCALITY_PRIORS`** — ~160+ locality and corridor **substring needles** with an actuarial-style **prior** (0–1). Used by:
  - `/forecast/{zone}` rule fallback (with a deterministic weekly shape)
  - `compute_work_route_advisory` via `zone_actuarial_prior(zone)`
- **`ml_cherry_picks.CHENNAI_ZONES`** — same needles, **sorted longest-first**, for `/nlp` zone extraction from free text.
- **`ml_cherry_picks.CHENNAI_NLP_RULE_ZONE_HINTS`** — a shorter list merged into rain-related **keyword rule** `zone_keywords` in `main.py`.
- **`main.py` `CHENNAI_FORECAST_ZONE_SLUGS`** — the **10 zones** that have **Prophet** artifacts from your CSVs (`model7_prophet_*.pkl`). Any other locality still gets **fallback** priors; it does **not** require a Prophet file.

Matching uses `needle in zone.lower()`. **Longer needles are tried first** so compound names beat shorter substrings.

## How to grow full ML coverage (datasets)

To train **per-zone** Prophet (or other models) beyond the default grid:

1. Add a **`zone`** column (consistent spelling) to:
   - `hustlr-ml/outputs/datasets/prophet_training.csv`
   - `hustlr-ml/outputs/datasets/traffic_accidents.csv`, `connectivity_dataset.csv`, `claims_fraud.csv`, `nlp_disruption_events.csv`, etc.
2. Run `python hustlr-ml/scripts/train_all_local.py`.
3. For Prophet, either:
   - extend **`CHENNAI_FORECAST_ZONE_SLUGS`** in `main.py` to list every new slug (`"my zone".lower().replace(" ", "_")`), **or**
   - relax health checks / load models dynamically (code change).

Priors in `CHENNAI_LOCALITY_PRIORS` are **heuristic underwriting-style weights**, not census data. Tune them with your own loss / claims experience when you have production stats.
