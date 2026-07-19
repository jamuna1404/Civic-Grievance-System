-- =====================================================================
-- CivicRoute — read-model views for the citizen "Track Complaints" feature.
-- Depends on: civicroute_boundary_routing_schema.sql (departments, officers)
--             civicroute_citizen_complaint_schema.sql (complaints,
--             complaint_images, complaint_status_history)
--
-- These views exist so the API can read complaints with lat/lon pulled out
-- of the PostGIS geometry (ST_X/ST_Y), the department name joined in, and the
-- image URLs aggregated — all in one PostgREST-selectable shape, instead of
-- decoding EWKB on the client/server.
-- =====================================================================

-- Full complaint detail, one row per complaint, with derived lat/lon,
-- department name, and an array of image URLs.
CREATE OR REPLACE VIEW complaint_details AS
SELECT
    c.complaint_id,
    c.citizen_id,
    cit.full_name AS citizen_name,
    cit.phone_number AS citizen_phone,
    c.department_id,
    d.department_name,
    c.description_text,
    c.input_mode,
    c.status,
    c.address_label,
    ST_Y(c.location) AS lat,
    ST_X(c.location) AS lon,
    c.assigned_officer_id,
    c.resolved_boundary_id,
    c.created_at,
    c.updated_at,
    COALESCE(
        (
            SELECT array_agg(ci.image_url ORDER BY ci.uploaded_at)
            FROM complaint_images ci
            WHERE ci.complaint_id = c.complaint_id
        ),
        ARRAY[]::text[]
    ) AS image_urls
FROM complaints c
JOIN departments d ON d.department_id = c.department_id
JOIN citizens cit ON cit.citizen_id = c.citizen_id;

-- Status history with the acting officer's name resolved (NULL = system,
-- e.g. the auto-logged SUBMITTED entry).
CREATE OR REPLACE VIEW complaint_history_view AS
SELECT
    h.history_id,
    h.complaint_id,
    h.status,
    h.remarks,
    h.changed_at,
    o.full_name AS officer_name
FROM complaint_status_history h
LEFT JOIN officers o ON o.officer_id = h.changed_by_officer_id;
