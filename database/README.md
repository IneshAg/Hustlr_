# HUSTLR Database SQL (Judge-Ready)

This folder has been simplified to one canonical schema file.

## Canonical Files

1. `supabase/hustlr_consolidated_schema.sql` (primary source of truth)
2. `database/hustlr_consolidated_schema.sql` (synced copy)

## Recommended Judge Flow

1. Open `supabase/hustlr_consolidated_schema.sql`.
2. Review sections in order: tables, indexes, RLS, functions/triggers, verification queries.
3. Optionally review `hustlr-backend/src/database/functions.sql` for helper procedures used by backend workflows.

## Notes

- Legacy temporary and split migration files were intentionally removed.
- The schema now avoids duplicate remediation blocks and stale contradictory constraints.
- The consolidated script includes post-run verification queries for quick validation.
