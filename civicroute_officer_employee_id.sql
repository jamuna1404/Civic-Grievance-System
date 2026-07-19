-- =====================================================================
-- CivicRoute — add optional employee_id to officers.
-- Collected during officer enrollment (Step 4). Idempotent.
-- =====================================================================
ALTER TABLE officers ADD COLUMN IF NOT EXISTS employee_id TEXT;
