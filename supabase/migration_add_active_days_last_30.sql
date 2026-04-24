-- Idempotent compatibility migration for older deployments.
-- Fixes: createPolicy 500 when querying users.active_days_last_30

ALTER TABLE users
ADD COLUMN IF NOT EXISTS active_days_last_30 INTEGER;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'days_active'
  ) THEN
    UPDATE users
    SET active_days_last_30 = COALESCE(active_days_last_30, days_active, 0);
  ELSE
    UPDATE users
    SET active_days_last_30 = COALESCE(active_days_last_30, 0);
  END IF;
END $$;

