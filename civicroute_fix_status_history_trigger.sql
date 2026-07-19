-- =====================================================================
-- CivicRoute — FIX: complaint status-history trigger ordering.
--
-- The original trigger in civicroute_citizen_complaint_schema.sql was:
--     CREATE TRIGGER trg_complaint_status_log
--     BEFORE INSERT OR UPDATE ON complaints ...
-- On INSERT this fired BEFORE the complaints row existed, then tried to
-- INSERT a complaint_status_history row referencing it — violating the FK
-- complaint_status_history.complaint_id -> complaints.complaint_id
-- (SQLSTATE 23503).
--
-- Correct design:
--   * AFTER INSERT  -> log the initial status (row now exists, FK satisfied)
--   * BEFORE UPDATE -> bump updated_at (must be BEFORE to modify NEW)
--   * AFTER UPDATE  -> log status changes (row exists, FK satisfied)
--
-- Idempotent: safe to run once against an existing database.
-- =====================================================================

-- Remove the old combined trigger + function.
DROP TRIGGER IF EXISTS trg_complaint_status_log ON complaints;
DROP FUNCTION IF EXISTS log_complaint_status_change();

-- 1. Log the initial status after the complaint row is inserted.
CREATE OR REPLACE FUNCTION log_complaint_status_insert() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO complaint_status_history (complaint_id, status, changed_by_officer_id)
    VALUES (NEW.complaint_id, NEW.status, NEW.assigned_officer_id);
    RETURN NULL; -- AFTER trigger: return value is ignored
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_complaint_status_insert ON complaints;
CREATE TRIGGER trg_complaint_status_insert
AFTER INSERT ON complaints
FOR EACH ROW EXECUTE FUNCTION log_complaint_status_insert();

-- 2. Keep updated_at fresh on every update (BEFORE, so it can modify NEW).
CREATE OR REPLACE FUNCTION touch_complaint_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_complaint_touch_updated ON complaints;
CREATE TRIGGER trg_complaint_touch_updated
BEFORE UPDATE ON complaints
FOR EACH ROW EXECUTE FUNCTION touch_complaint_updated_at();

-- 3. Log status changes after they're applied.
CREATE OR REPLACE FUNCTION log_complaint_status_update() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO complaint_status_history (complaint_id, status, changed_by_officer_id)
        VALUES (NEW.complaint_id, NEW.status, NEW.assigned_officer_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_complaint_status_update ON complaints;
CREATE TRIGGER trg_complaint_status_update
AFTER UPDATE ON complaints
FOR EACH ROW EXECUTE FUNCTION log_complaint_status_update();
