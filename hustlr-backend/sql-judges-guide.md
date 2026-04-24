# HUSTLR Backend SQL Guide (Judges)

SQL is now split into review-friendly modules inside `hustlr-backend/schema`.

## Primary Judge Folder

- `hustlr-backend/schema/`

Start with:

- `hustlr-backend/schema/00-run-order.md`

That file contains the exact numbered order (`01` to `16`) for reading/executing the schema modules.

## Canonical Source

- `supabase/hustlr_consolidated_schema.sql` remains the canonical full source.
- The files in `hustlr-backend/schema` are section-wise splits of that canonical script for easier judging.

## Execution Model

- Fresh environment: run the SQL files in numeric order from `01` to `16`.
- Existing environment: apply carefully and prefer idempotent `ALTER`/`IF NOT EXISTS` blocks.

## Optional Backend Helper SQL

- `hustlr-backend/src/database/functions.sql`

This file contains additional backend utility functions and can be run after the main schema modules.
