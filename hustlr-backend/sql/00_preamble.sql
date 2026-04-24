-- NOTE: Destructive schema reset commands removed for live-safe usage.
-- If you need a full reset in a disposable environment, run that separately.

-- ═══════════════════════════════════════════════════════════════
-- HUSTLR — Complete Production Schema (All Phases)
-- Guidewire DEVTrails 2026
-- Run this ONCE in a fresh Supabase project.
-- If migrating from an existing DB run each ALTER TABLE
-- block individually and skip CREATE TABLE blocks that exist.
-- ═══════════════════════════════════════════════════════════════

-- ── Extensions ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
