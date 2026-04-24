# HUSTLR SQL Run Order (Judges)

These files are split from the consolidated schema for easier review.

## Recommended execution order

1. `01-core-schema.sql`
2. `02-fraud-telemetry.sql`
3. `03-disruption-shadow.sql`
4. `04-pool-health-settlements.sql`
5. `05-trust-notifications-referrals.sql`
6. `06-admin-audit.sql`
7. `07-indexes.sql`
8. `08-rls-baseline.sql`
9. `09-functions-triggers.sql`
10. `10-postgis-helpers.sql`
11. `11-verification-base.sql`
12. `12-h3-migration.sql`
13. `13-secure-auth-policies.sql`
14. `14-schema-meta.sql`
15. `15-extended-verification.sql`
16. `16-hardening-remediation-patch.sql`

## Optional backend helper SQL

- `../src/database/functions.sql`

This file contains extra backend utility functions and can be run after the main schema modules.

## Notes for judges

- Files are ordered by dependency (tables before FKs/indexes/policies/triggers).
- If reviewing only, read in numeric order.
- If executing on a fresh Supabase project, run in numeric order.
- If executing on an existing database, apply carefully and prefer `IF NOT EXISTS`/`ALTER` blocks as intended.
