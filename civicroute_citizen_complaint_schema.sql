-- =====================================================================
-- CivicRoute v3 — Citizen, OTP (dummy), Complaint + Attachments + Status
-- History. Extends civicroute_boundary_routing_schema.sql
-- (departments / boundary_levels / boundaries / designations / officers
-- already exist there — this file only adds the citizen-facing side).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CITIZENS
-- ---------------------------------------------------------------------
CREATE TABLE citizens (
    citizen_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number   TEXT UNIQUE NOT NULL,       -- E.164 format, e.g. +91XXXXXXXXXX
    full_name      TEXT NOT NULL,
    is_verified    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. OTP VERIFICATIONS — dummy/stub implementation for now.
-- Real SMS gateway integration (MSG91 / Twilio / TN govt SMS gateway)
-- can replace the generation logic later without changing this table.
-- ---------------------------------------------------------------------
CREATE TABLE otp_verifications (
    otp_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number   TEXT NOT NULL,
    otp_code       TEXT NOT NULL,             -- dummy: always '123456' for now
    purpose        TEXT NOT NULL DEFAULT 'LOGIN' CHECK (purpose IN ('LOGIN','SIGNUP')),
    is_used        BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at     TIMESTAMPTZ NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_otp_phone ON otp_verifications (phone_number, is_used);

-- ---------------------------------------------------------------------
-- 3. COMPLAINTS  (supersedes the earlier stub complaints table —
-- add this citizen_id + status-tracking version instead)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS complaints CASCADE;

CREATE TABLE complaints (
    complaint_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    citizen_id           UUID NOT NULL REFERENCES citizens(citizen_id),
    department_id        TEXT NOT NULL REFERENCES departments(department_id),
    description_text     TEXT NOT NULL,        -- typed OR transcribed-from-voice
    input_mode           TEXT NOT NULL DEFAULT 'TEXT' CHECK (input_mode IN ('TEXT','VOICE')),
    location             GEOMETRY(Point, 4326) NOT NULL,
    address_label        TEXT,                 -- human-readable reverse-geocoded address
    resolved_boundary_id INT REFERENCES boundaries(boundary_id),
    assigned_officer_id  UUID REFERENCES officers(officer_id),
    status               TEXT NOT NULL DEFAULT 'SUBMITTED'
                         CHECK (status IN ('SUBMITTED','ACKNOWLEDGED','IN_PROGRESS','RESOLVED','REJECTED')),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_complaints_location ON complaints USING GIST (location);
CREATE INDEX idx_complaints_citizen ON complaints (citizen_id);
CREATE INDEX idx_complaints_officer ON complaints (assigned_officer_id);

-- ---------------------------------------------------------------------
-- 4. COMPLAINT IMAGES — normalized out (1 complaint : many images),
-- so a citizen can attach more than one photo without denormalizing
-- the complaints row itself.
-- ---------------------------------------------------------------------
CREATE TABLE complaint_images (
    image_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id   UUID NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    image_url      TEXT NOT NULL,          -- Supabase Storage object path
    uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. COMPLAINT STATUS HISTORY — every status change is an immutable
-- row, so "track complaint" can render a full timeline, not just the
-- current state.
-- ---------------------------------------------------------------------
CREATE TABLE complaint_status_history (
    history_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id   UUID NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    status         TEXT NOT NULL,
    changed_by_officer_id UUID REFERENCES officers(officer_id),  -- NULL = system (e.g. auto-assigned on submit)
    remarks        TEXT,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_status_history_complaint ON complaint_status_history (complaint_id, changed_at);

-- Triggers: auto-log every status change to history so the app never has to
-- write both tables itself.
--
-- NOTE: logging must happen AFTER the complaints row is written, otherwise the
-- complaint_status_history.complaint_id FK has nothing to point at yet on
-- INSERT. So logging is split into AFTER INSERT / AFTER UPDATE triggers, with a
-- separate BEFORE UPDATE trigger to bump updated_at (which must modify NEW).

-- Log the initial status once the complaint row exists.
CREATE OR REPLACE FUNCTION log_complaint_status_insert() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO complaint_status_history (complaint_id, status, changed_by_officer_id)
    VALUES (NEW.complaint_id, NEW.status, NEW.assigned_officer_id);
    RETURN NULL; -- AFTER trigger: return value is ignored
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_complaint_status_insert
AFTER INSERT ON complaints
FOR EACH ROW EXECUTE FUNCTION log_complaint_status_insert();

-- Keep updated_at fresh on every update.
CREATE OR REPLACE FUNCTION touch_complaint_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_complaint_touch_updated
BEFORE UPDATE ON complaints
FOR EACH ROW EXECUTE FUNCTION touch_complaint_updated_at();

-- Log status changes after they're applied.
CREATE OR REPLACE FUNCTION log_complaint_status_update() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO complaint_status_history (complaint_id, status, changed_by_officer_id)
        VALUES (NEW.complaint_id, NEW.status, NEW.assigned_officer_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_complaint_status_update
AFTER UPDATE ON complaints
FOR EACH ROW EXECUTE FUNCTION log_complaint_status_update();

-- ---------------------------------------------------------------------
-- 6. USER PREFERENCES — theme mode, kept separate from citizens/officers
-- so it's optional and doesn't clutter the identity tables (3NF: theme
-- preference is not functionally dependent on citizen identity fields).
-- ---------------------------------------------------------------------
CREATE TABLE user_preferences (
    owner_type    TEXT NOT NULL CHECK (owner_type IN ('CITIZEN','OFFICER')),
    owner_id      UUID NOT NULL,
    theme_mode    TEXT NOT NULL DEFAULT 'SYSTEM' CHECK (theme_mode IN ('LIGHT','DARK','SYSTEM')),
    PRIMARY KEY (owner_type, owner_id)
);
