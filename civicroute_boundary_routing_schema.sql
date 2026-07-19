-- =====================================================================
-- CivicRoute v2 — Department-native boundary hierarchies + PostGIS
-- geo-routing of complaints to the correct officer.
-- Replaces the flat "GCC zone/ward for everyone" model with a model
-- where each department keeps its OWN real administrative hierarchy.
-- Target: PostgreSQL + PostGIS extension (Supabase supports this natively)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- ---------------------------------------------------------------------
-- 1. DEPARTMENTS  (unchanged from v1)
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id      TEXT PRIMARY KEY,
    department_name    TEXT NOT NULL,
    jurisdiction_scope  TEXT
);

INSERT INTO departments (department_id, department_name, jurisdiction_scope) VALUES
('GCC_ENG_ROADS', 'GCC Engineering (Roads & Bridges)', 'Potholes, damaged pavements, missing manhole covers on roads, interior street repairs.'),
('GCC_PH_SAN',    'GCC Public Health & Sanitation',    'Garbage piles, irregular door-to-door collection, mosquito breeding, dead animal removal.'),
('GCC_ENG_SWD',   'GCC Storm Water Drains',            'Clogged storm water drains, broken drain slabs, rainwater stagnation/flooding.'),
('GCC_ELECT',     'GCC Electrical (Streetlights)',     'Non-functioning streetlights, glowing lights during daytime, broken streetlight poles.'),
('CMWSSB_SEW',    'Chennai Metrowater (Sewerage)',     'Sewage overflow on streets, main sewer line blocks, mixing of sewage in drinking water.'),
('TANGEDCO_PWR',  'Electricity Board (TNEB)',          'Power outages, voltage fluctuations, transformer sparks, hanging overhead high-tension wires.'),
('GCP_LAW_ORD',   'Greater Chennai Police (L&O)',      'Public nuisance, illegal parking/encroachments, unsafe public activities, street harassment.');

-- ---------------------------------------------------------------------
-- 2. BOUNDARY LEVELS  — each department defines its OWN vocabulary
-- level_rank: 1 = smallest/most granular area, increasing outward.
-- This is what drives the cascading picker in the enrollment UI.
-- ---------------------------------------------------------------------
CREATE TABLE boundary_levels (
    department_id TEXT NOT NULL REFERENCES departments(department_id),
    level_rank    INT  NOT NULL,          -- 1 = most granular
    level_name    TEXT NOT NULL,          -- e.g. 'WARD', 'SECTION', 'STATION_JURISDICTION'
    display_label TEXT NOT NULL,          -- what the UI shows, e.g. 'Ward', 'Section (O&M)'
    PRIMARY KEY (department_id, level_rank),
    UNIQUE (department_id, level_name)
);

-- GCC departments: real GCC ward/zone/region hierarchy
INSERT INTO boundary_levels VALUES
('GCC_ENG_ROADS',1,'WARD','Ward'),
('GCC_ENG_ROADS',2,'ZONE','Zone'),
('GCC_ENG_ROADS',3,'REGION','Region'),
('GCC_ENG_ROADS',4,'CITY','City-wide');

INSERT INTO boundary_levels VALUES
('GCC_PH_SAN',1,'WARD','Ward'),
('GCC_PH_SAN',2,'ZONE','Zone'),
('GCC_PH_SAN',3,'CITY','City-wide');

INSERT INTO boundary_levels VALUES
('GCC_ENG_SWD',1,'WARD','Ward'),
('GCC_ENG_SWD',2,'ZONE','Zone'),
('GCC_ENG_SWD',3,'REGION','Region'),
('GCC_ENG_SWD',4,'CITY','City-wide');

INSERT INTO boundary_levels VALUES
('GCC_ELECT',1,'WARD','Ward'),
('GCC_ELECT',2,'ZONE','Zone'),
('GCC_ELECT',3,'REGION','Region'),
('GCC_ELECT',4,'CITY','City-wide');

-- CMWSSB: its own Sub-division -> Area/Division -> Region -> Board-wide
INSERT INTO boundary_levels VALUES
('CMWSSB_SEW',1,'SUBDIVISION','Sewerage Sub-division'),
('CMWSSB_SEW',2,'AREA_DIVISION','Area Division'),
('CMWSSB_SEW',3,'REGION','Region'),
('CMWSSB_SEW',4,'CITY','Board-wide');

-- TANGEDCO: real TNEB hierarchy Section -> Sub-division -> Division -> Circle -> City
INSERT INTO boundary_levels VALUES
('TANGEDCO_PWR',1,'SECTION','Section (O&M)'),
('TANGEDCO_PWR',2,'SUBDIVISION','Sub-division'),
('TANGEDCO_PWR',3,'DIVISION','Division'),
('TANGEDCO_PWR',4,'CIRCLE','Distribution Circle'),
('TANGEDCO_PWR',5,'CITY','City-wide');

-- Police: Station jurisdiction -> Sub-division -> Police Zone -> City
INSERT INTO boundary_levels VALUES
('GCP_LAW_ORD',1,'STATION_JURISDICTION','Police Station Jurisdiction'),
('GCP_LAW_ORD',2,'SUBDIVISION','Sub-division'),
('GCP_LAW_ORD',3,'POLICE_ZONE','Police Zone'),
('GCP_LAW_ORD',4,'CITY','City-wide');

-- ---------------------------------------------------------------------
-- 3. BOUNDARIES  — the actual named areas + real polygons.
-- Self-referencing hierarchy: a WARD's parent is a ZONE, a ZONE's
-- parent is a REGION, etc. geom is nullable at first because you will
-- need to import real polygon data (see note at bottom of file).
-- ---------------------------------------------------------------------
CREATE TABLE boundaries (
    boundary_id       SERIAL PRIMARY KEY,
    department_id     TEXT NOT NULL REFERENCES departments(department_id),
    level_name        TEXT NOT NULL,
    boundary_name     TEXT NOT NULL,          -- e.g. 'Ward 45', 'Adyar Sub-division', 'T.Nagar PS'
    parent_boundary_id INT REFERENCES boundaries(boundary_id),
    geom              GEOMETRY(MultiPolygon, 4326),  -- real boundary polygon, WGS84
    UNIQUE (department_id, level_name, boundary_name),
    FOREIGN KEY (department_id, level_name) REFERENCES boundary_levels(department_id, level_name)
);

CREATE INDEX idx_boundaries_geom ON boundaries USING GIST (geom);

-- Example seed for GCC_ENG_ROADS (repeat pattern for GCC_PH_SAN / SWD / ELECT).
-- Full 200-ward / 15-zone / 3-region seed should be generated from your
-- earlier v1 wards/zones tables or GCC's published ward shapefiles.
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCC_ENG_ROADS','REGION','North', NULL, NULL),
('GCC_ENG_ROADS','REGION','Central', NULL, NULL),
('GCC_ENG_ROADS','REGION','South', NULL, NULL);
-- ('GCC_ENG_ROADS','ZONE','Adyar', <region_boundary_id_for_South>, <polygon>)
-- ('GCC_ENG_ROADS','WARD','Ward 175', <zone_boundary_id_for_Adyar>, <polygon>)

-- Example seed for TANGEDCO (Circle -> Division -> Sub-division -> Section)
-- Real Chennai circles include e.g. Chennai North/Central/South EDCs, Egmore,
-- etc. — pull exact current names/boundaries from TANGEDCO's official
-- circle-wise division list before going live.
-- INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
-- ('TANGEDCO_PWR','CIRCLE','Chennai South EDC', NULL, <polygon>);

-- Example seed for CMWSSB (Area Divisions — CMWSSB publishes its own area
-- office map, distinct from GCC wards)
-- INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
-- ('CMWSSB_SEW','AREA_DIVISION','Area VI - Adyar', NULL, <polygon>);

-- Example seed for Police (Station jurisdiction polygons — publicly
-- available via Greater Chennai Police / OSM administrative layers)
-- INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
-- ('GCP_LAW_ORD','STATION_JURISDICTION','Adyar PS', NULL, <polygon>);

-- ---------------------------------------------------------------------
-- 4. DESIGNATIONS — same idea as v1, but 'level' now points into each
-- department's own boundary_levels instead of a fixed WARD/ZONE/CITY enum.
-- ---------------------------------------------------------------------
CREATE TABLE designations (
    designation_id   SERIAL PRIMARY KEY,
    department_id    TEXT NOT NULL,
    designation_name TEXT NOT NULL,
    level_name       TEXT NOT NULL,
    rank_order       INT NOT NULL,
    UNIQUE (department_id, designation_name),
    UNIQUE (department_id, designation_id),
    FOREIGN KEY (department_id, level_name) REFERENCES boundary_levels(department_id, level_name)
);

INSERT INTO designations (department_id, designation_name, level_name, rank_order) VALUES
('GCC_ENG_ROADS','Junior Engineer','WARD',1),
('GCC_ENG_ROADS','Assistant Engineer','WARD',2),
('GCC_ENG_ROADS','Assistant Executive Engineer','ZONE',3),
('GCC_ENG_ROADS','Executive Engineer','ZONE',4),
('GCC_ENG_ROADS','Superintending Engineer','REGION',5),
('GCC_ENG_ROADS','Chief Engineer (Works)','CITY',6),

('GCC_PH_SAN','Sanitary Inspector','WARD',1),
('GCC_PH_SAN','Assistant Health Officer','ZONE',2),
('GCC_PH_SAN','Zonal Health Officer','ZONE',3),
('GCC_PH_SAN','City Health Officer','CITY',4),

('GCC_ENG_SWD','Junior Engineer (SWD)','WARD',1),
('GCC_ENG_SWD','Assistant Engineer (SWD)','WARD',2),
('GCC_ENG_SWD','Assistant Executive Engineer (SWD)','ZONE',3),
('GCC_ENG_SWD','Executive Engineer (SWD)','ZONE',4),
('GCC_ENG_SWD','Superintending Engineer (SWD)','REGION',5),
('GCC_ENG_SWD','Chief Engineer (SWD)','CITY',6),

('GCC_ELECT','Junior Engineer (Electrical)','WARD',1),
('GCC_ELECT','Assistant Engineer (Electrical)','ZONE',2),
('GCC_ELECT','Executive Engineer (Electrical)','ZONE',3),
('GCC_ELECT','Superintending Engineer (Electrical)','REGION',4),
('GCC_ELECT','Chief Engineer (Electrical)','CITY',5),

('CMWSSB_SEW','Assistant Engineer (Sewerage)','SUBDIVISION',1),
('CMWSSB_SEW','Assistant Executive Engineer','AREA_DIVISION',2),
('CMWSSB_SEW','Executive Engineer','REGION',3),
('CMWSSB_SEW','Superintending Engineer','REGION',4),
('CMWSSB_SEW','Chief Engineer (Sewerage)','CITY',5),

('TANGEDCO_PWR','Junior Engineer (O&M)','SECTION',1),
('TANGEDCO_PWR','Assistant Engineer / AEE (O&M)','SUBDIVISION',2),
('TANGEDCO_PWR','Executive Engineer','DIVISION',3),
('TANGEDCO_PWR','Superintending Engineer','CIRCLE',4),
('TANGEDCO_PWR','Chief Distribution Engineer','CITY',5),

('GCP_LAW_ORD','Sub-Inspector (SI)','STATION_JURISDICTION',1),
('GCP_LAW_ORD','Inspector of Police','STATION_JURISDICTION',2),
('GCP_LAW_ORD','Assistant Commissioner of Police (ACP)','SUBDIVISION',3),
('GCP_LAW_ORD','Deputy Commissioner of Police (DCP)','POLICE_ZONE',4),
('GCP_LAW_ORD','Joint Commissioner of Police','POLICE_ZONE',5),
('GCP_LAW_ORD','Commissioner of Police','CITY',6);

-- ---------------------------------------------------------------------
-- 5. OFFICERS  — one table for every department, boundary-based.
-- ---------------------------------------------------------------------
CREATE TABLE officers (
    officer_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       TEXT NOT NULL,
    phone           TEXT NOT NULL,
    email           TEXT,
    employee_id     TEXT,                 -- optional, collected at enrollment
    department_id   TEXT NOT NULL,
    designation_id  INT  NOT NULL,
    boundary_id     INT  NOT NULL REFERENCES boundaries(boundary_id),
    status          TEXT NOT NULL DEFAULT 'PENDING_VERIFICATION'
                    CHECK (status IN ('PENDING_VERIFICATION','ACTIVE','SUSPENDED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (department_id, designation_id) REFERENCES designations(department_id, designation_id),

    -- guard: the boundary picked must actually belong to this department
    CONSTRAINT chk_boundary_department CHECK (
        (SELECT b.department_id FROM boundaries b WHERE b.boundary_id = boundary_id) = department_id
    )
);

-- ONE unified conflict-prevention rule for every department & every level:
-- only one active/pending officer per (department, designation, exact boundary)
CREATE UNIQUE INDEX uq_officer_boundary
    ON officers (department_id, designation_id, boundary_id)
    WHERE status <> 'SUSPENDED';

-- ---------------------------------------------------------------------
-- 6. COMPLAINTS  — citizen submissions with a geo-point
-- ---------------------------------------------------------------------
CREATE TABLE complaints (
    complaint_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id    TEXT NOT NULL REFERENCES departments(department_id),
    description      TEXT NOT NULL,
    location         GEOMETRY(Point, 4326) NOT NULL,   -- from GPS or geocoded address
    resolved_boundary_id INT REFERENCES boundaries(boundary_id),
    assigned_officer_id  UUID REFERENCES officers(officer_id),
    status           TEXT NOT NULL DEFAULT 'SUBMITTED',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_complaints_location ON complaints USING GIST (location);

-- ---------------------------------------------------------------------
-- 7. ROUTING FUNCTION — point-in-polygon lookup + escalation on vacancy
-- Finds the most granular boundary containing the complaint's location
-- for that department, then finds the lowest-rank (first-responder)
-- officer assigned there. If that seat is vacant, walks up parent
-- boundaries until an active officer is found.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_officer_for_complaint(
    p_department_id TEXT,
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION
) RETURNS TABLE(officer_id UUID, boundary_id INT, designation_id INT) AS $$
DECLARE
    v_point GEOMETRY := ST_SetSRID(ST_Point(p_lon, p_lat), 4326);
    v_boundary_id INT;
    v_min_rank INT;
BEGIN
    -- find the most granular (level_rank = 1) boundary containing the point
    SELECT b.boundary_id INTO v_boundary_id
    FROM boundaries b
    JOIN boundary_levels bl ON bl.department_id = b.department_id AND bl.level_name = b.level_name
    WHERE b.department_id = p_department_id
      AND bl.level_rank = 1
      AND b.geom IS NOT NULL
      AND ST_Contains(b.geom, v_point)
    LIMIT 1;

    SELECT MIN(rank_order) INTO v_min_rank FROM designations WHERE department_id = p_department_id;

    -- walk up the hierarchy until an ACTIVE officer is found or we run out of parents
    WHILE v_boundary_id IS NOT NULL LOOP
        RETURN QUERY
        SELECT o.officer_id, o.boundary_id, o.designation_id
        FROM officers o
        WHERE o.department_id = p_department_id
          AND o.boundary_id = v_boundary_id
          AND o.status = 'ACTIVE'
          AND o.designation_id = (
              SELECT designation_id FROM designations
              WHERE department_id = p_department_id AND rank_order = v_min_rank
          )
        LIMIT 1;

        IF FOUND THEN
            RETURN;
        END IF;

        SELECT parent_boundary_id INTO v_boundary_id FROM boundaries WHERE boundary_id = v_boundary_id;
    END LOOP;

    RETURN; -- no officer found anywhere in the hierarchy (data gap)
END;
$$ LANGUAGE plpgsql;

-- Usage when a complaint comes in:
-- SELECT * FROM resolve_officer_for_complaint('TANGEDCO_PWR', 80.2707, 13.0827);
-- then UPDATE complaints SET assigned_officer_id = ..., resolved_boundary_id = ... WHERE complaint_id = ...

-- =====================================================================
-- NOTE ON REAL POLYGON DATA (important — do not fabricate this yourself):
-- - GCC ward boundaries: available as official shapefile/GeoJSON via
--   Chennai Corporation's GIS cell / data.gov.in / OpenCity Chennai datasets.
-- - CMWSSB area division boundaries: not published as GIS files publicly;
--   you'll likely need to manually digitize from their published area maps
--   (e.g. using geojson.io tracing over their PDF maps) — reasonable to
--   note as a scoping assumption in your SRS.
-- - TANGEDCO circle/division/section boundaries: similarly not open GIS
--   data; TANGEDCO publishes circle-wise jurisdiction PDFs you can digitize.
-- - Police station jurisdictions: OpenStreetMap has partial coverage for
--   some Indian city police boundaries; verify against Greater Chennai
--   Police's official station list before treating as authoritative.
-- For a portfolio-scope project, digitizing a representative subset
-- (rather than all 200 wards / every circle / every station) is a fair
-- and defensible scope cut — just say so explicitly in your assumptions.
-- =====================================================================
