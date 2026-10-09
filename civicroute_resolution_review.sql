-- =====================================================================
-- CivicRoute — officer closure-request pipeline.
-- Depends on: civicroute_boundary_routing_schema.sql (boundaries,
--             designations, officers), civicroute_citizen_complaint_schema.sql
--             (complaints), civicroute_track_views.sql (complaint_details).
--
-- Adds:
--   1. RESOLUTION_REQUESTED as a valid complaints.status value — the state
--      between an officer requesting closure and a supervisor approving it.
--   2. v_officer_complaints — the same shape as complaint_details, minus
--      citizen_name/citizen_phone, for officer-facing endpoints that must
--      never surface citizen identity.
--   3. resolve_reviewing_officer() — given a complaint, finds the ACTIVE
--      officer one designation rank above the currently assigned officer,
--      walking up the boundary hierarchy from the complaint's resolved
--      boundary until one is found (same escalation pattern as
--      resolve_officer_for_complaint).
-- =====================================================================

ALTER TABLE complaints DROP CONSTRAINT IF EXISTS complaints_status_check;
ALTER TABLE complaints ADD CONSTRAINT complaints_status_check
    CHECK (status IN (
        'SUBMITTED','ACKNOWLEDGED','IN_PROGRESS',
        'RESOLUTION_REQUESTED','RESOLVED','REJECTED'
    ));

CREATE OR REPLACE VIEW v_officer_complaints AS
SELECT
    c.complaint_id,
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
JOIN departments d ON d.department_id = c.department_id;

CREATE OR REPLACE FUNCTION resolve_reviewing_officer(
    p_complaint_id UUID
) RETURNS TABLE(officer_id UUID, boundary_id INT, designation_id INT) AS $$
-- Ambiguous bare column names (e.g. designation_id) resolve to the table
-- column, not the like-named OUT parameter of this function.
#variable_conflict use_column
DECLARE
    v_department_id TEXT;
    v_boundary_id INT;
    v_current_designation_id INT;
    v_current_rank INT;
    v_next_rank INT;
BEGIN
    SELECT c.department_id, c.resolved_boundary_id, o.designation_id
    INTO v_department_id, v_boundary_id, v_current_designation_id
    FROM complaints c
    JOIN officers o ON o.officer_id = c.assigned_officer_id
    WHERE c.complaint_id = p_complaint_id;

    IF v_boundary_id IS NULL THEN
        RETURN; -- no assigned officer / boundary to escalate from
    END IF;

    SELECT d.rank_order INTO v_current_rank
    FROM designations d
    WHERE d.department_id = v_department_id
      AND d.designation_id = v_current_designation_id;

    -- the next rank strictly above the current officer's
    SELECT MIN(d.rank_order) INTO v_next_rank
    FROM designations d
    WHERE d.department_id = v_department_id AND d.rank_order > v_current_rank;

    IF v_next_rank IS NULL THEN
        RETURN; -- already at the top designation, nobody to review it
    END IF;

    WHILE v_boundary_id IS NOT NULL LOOP
        RETURN QUERY
        SELECT o.officer_id, o.boundary_id, o.designation_id
        FROM officers o
        WHERE o.department_id = v_department_id
          AND o.boundary_id = v_boundary_id
          AND o.status = 'ACTIVE'
          AND o.designation_id = (
              SELECT d.designation_id FROM designations d
              WHERE d.department_id = v_department_id AND d.rank_order = v_next_rank
          )
        LIMIT 1;

        IF FOUND THEN
            RETURN;
        END IF;

        SELECT b.parent_boundary_id INTO v_boundary_id
        FROM boundaries b WHERE b.boundary_id = v_boundary_id;
    END LOOP;

    RETURN; -- reviewing seat vacant all the way up (data gap)
END;
$$ LANGUAGE plpgsql;
