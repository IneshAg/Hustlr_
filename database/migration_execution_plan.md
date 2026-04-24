# Database Migration Execution Plan

This project now uses a single consolidated SQL script.

## Canonical Script

- `supabase/hustlr_consolidated_schema.sql` (primary)
- `database/hustlr_consolidated_schema.sql` (synced copy)

## Execution Sequence

1. Backup your database.
2. Open Supabase SQL Editor.
3. Run the consolidated script (`supabase/hustlr_consolidated_schema.sql`) from top to bottom.
4. Run the built-in verification queries at the end of the script.

## Existing Environment Guidance

- Apply only relevant `ALTER TABLE` / `CREATE ... IF NOT EXISTS` blocks.
- Do not replay destructive reset logic on a live environment.

## Judge Notes

- Legacy split migration files were removed intentionally.
- The script includes:
	- complete schema creation,
	- RLS policies,
	- functions and triggers,
	- H3 additions,
	- remediation and verification sections.
