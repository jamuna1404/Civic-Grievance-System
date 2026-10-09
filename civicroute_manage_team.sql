-- =====================================================================
-- CivicRoute — "Manage Team" tab for officers who have subordinates.
-- Depends on: civicroute_boundary_routing_schema.sql (boundaries,
--             designations, officers), civicroute_citizen_complaint_schema.sql
--             (complaints, complaint_images), civicroute_resolution_review.sql
--             (RESOLUTION_REQUESTED status).
--
-- Adds:
--   1. get_boundary_descendants(p_boundary_id) — the given boundary plus
--      every boundary transitively below it (its own boundary_id is
--      included, per the caller's "own boundary UNION descendants" scope).
--   2. team_complaints_for_officer(p_officer_id) — every complaint whose
--      resolved boundary falls in that scope AND whose assigned officer
--      outranks below the caller (lower rank_order = more junior), with
--      the subordinate's name/designation resolved (officers, not
--      citizens — safe to show), RESOLUTION_REQUESTED items sorted first.
-- =====================================================================

CREATE OR REPLACE FUNCTION get_boundary_descendants(p_boundary_id INT)
RETURNS TABLE(boundary_id INT) AS $$
    WITH RECURSIVE descendants AS (
        SELECT b.boundary_id FROM boundaries b WHERE b.boundary_id = p_boundary_id
        UNION ALL
        SELECT b.boundary_id
        FROM boundaries b
        JOIN descendants d ON b.parent_boundary_id = d.boundary_id
    )
    SELECT boundary_id FROM descendants;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION team_complaints_for_officer(p_officer_id UUID)
RETURNS TABLE (
    complaint_id UUID,
    department_id TEXT,
    department_name TEXT,
    description_text TEXT,
    input_mode TEXT,
    status TEXT,
    address_label TEXT,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    assigned_officer_id UUID,
    resolved_boundary_id INT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    image_urls TEXT[],
    officer_name TEXT,
    officer_designation_name TEXT
) AS $$
DECLARE
    v_boundary_id INT;
    v_department_id TEXT;
    v_rank INT;
BEGIN
    SELECT o.boundary_id, o.department_id, d.rank_order
    INTO v_boundary_id, v_department_id, v_rank
    FROM officers o
    JOIN designations d
        ON d.department_id = o.department_id AND d.designation_id = o.designation_id
    WHERE o.officer_id = p_officer_id;

    IF v_boundary_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        c.complaint_id, c.department_id, dept.department_name, c.description_text,
        c.input_mode, c.status, c.address_label,
        ST_Y(c.location), ST_X(c.location),
        c.assigned_officer_id, c.resolved_boundary_id, c.created_at, c.updated_at,
        COALESCE(
            (SELECT array_agg(ci.image_url ORDER BY ci.uploaded_at)
             FROM complaint_images ci WHERE ci.complaint_id = c.complaint_id),
            ARRAY[]::text[]
        ),
        sub.full_name, subd.designation_name
    FROM complaints c
    JOIN departments dept ON dept.department_id = c.department_id
    JOIN officers sub ON sub.officer_id = c.assigned_officer_id
    JOIN designations subd
        ON subd.department_id = sub.department_id AND subd.designation_id = sub.designation_id
    WHERE c.resolved_boundary_id IN (SELECT boundary_id FROM get_boundary_descendants(v_boundary_id))
      AND subd.rank_order < v_rank
    ORDER BY (c.status = 'RESOLUTION_REQUESTED') DESC, c.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;
