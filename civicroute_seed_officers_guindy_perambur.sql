-- =====================================================================
-- CivicRoute — test-officer seed for the Guindy and Perambur areas,
-- full designation hierarchy, for every department EXCEPT
-- GCC_ENG_SWD and GCC_PH_SAN.
--
-- Idempotent: re-running does not create duplicates (boundaries are
-- matched by (department, level, name); officers by (department,
-- designation, boundary)). Safe to run more than once.
--
-- Depends on: civicroute_boundary_routing_schema.sql (departments,
--   boundary_levels, boundaries, designations, officers) and the
--   RESOLUTION_REQUESTED status from civicroute_resolution_review.sql.
--
-- Geometry note: three DISJOINT boxes (Guindy / Perambur / Adyar) so
-- point-in-polygon routing is unambiguous per department. The existing
-- placeholder Adyar level-1 boundary (widened earlier to a city-wide
-- box) is narrowed back to an Adyar-only box here.
--
-- Login: all seeded officers are ACTIVE. Log in with the dummy OTP
-- (123456) using the phone listed by the roster query at the bottom.
-- =====================================================================

BEGIN;

CREATE SEQUENCE IF NOT EXISTS _seed_phone_seq START 1000;

-- get-or-create a boundary; updates parent/geom when explicitly provided.
CREATE OR REPLACE FUNCTION _seed_boundary(
    p_dept TEXT, p_level TEXT, p_name TEXT, p_parent INT, p_geom GEOMETRY
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    SELECT boundary_id INTO v_id FROM boundaries
    WHERE department_id = p_dept AND level_name = p_level AND boundary_name = p_name;
    IF v_id IS NULL THEN
        INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
        VALUES (p_dept, p_level, p_name, p_parent, p_geom)
        RETURNING boundary_id INTO v_id;
    ELSE
        UPDATE boundaries
        SET parent_boundary_id = COALESCE(p_parent, parent_boundary_id),
            geom = COALESCE(p_geom, geom)
        WHERE boundary_id = v_id;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- get-or-create an ACTIVE officer at a (department, designation-by-name,
-- boundary) seat. full_name = "<designation> - <area>", phone auto-generated.
CREATE OR REPLACE FUNCTION _seed_officer(
    p_dept TEXT, p_desig_name TEXT, p_boundary INT, p_area TEXT
) RETURNS VOID AS $$
DECLARE v_desig INT;
BEGIN
    SELECT designation_id INTO v_desig FROM designations
    WHERE department_id = p_dept AND designation_name = p_desig_name;
    IF v_desig IS NULL THEN
        RAISE NOTICE 'designation "%" not found for %, skipped', p_desig_name, p_dept;
        RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM officers
        WHERE department_id = p_dept AND designation_id = v_desig
          AND boundary_id = p_boundary AND status <> 'SUSPENDED'
    ) THEN
        RETURN; -- seat already filled
    END IF;
    INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
    VALUES (
        p_desig_name || ' - ' || p_area,
        '+919' || lpad(nextval('_seed_phone_seq')::text, 9, '0'),
        'seed-test@civicroute.local',   -- marker for the roster query below
        p_dept, v_desig, p_boundary, 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    guindy   GEOMETRY := ST_Multi(ST_GeomFromText('POLYGON((80.20 12.99,80.23 12.99,80.23 13.02,80.20 13.02,80.20 12.99))', 4326));
    perambur GEOMETRY := ST_Multi(ST_GeomFromText('POLYGON((80.22 13.10,80.25 13.10,80.25 13.13,80.22 13.13,80.22 13.10))', 4326));
    adyar    GEOMETRY := ST_Multi(ST_GeomFromText('POLYGON((80.24 13.00,80.27 13.00,80.27 13.03,80.24 13.03,80.24 13.00))', 4326));
    city INT; rgnS INT; rgnN INT; zoneA INT; zoneP INT; wardG INT; wardP INT;
    circS INT; circN INT; divG INT; divP INT; subG INT; subP INT; secG INT; secP INT;
    areaG INT; areaP INT; stnG INT; stnP INT;
BEGIN
    -- ============================ GCC_ENG_ROADS ============================
    -- WARD -> ZONE -> REGION -> CITY
    city  := _seed_boundary('GCC_ENG_ROADS','CITY','Chennai City',NULL,NULL);
    rgnS  := _seed_boundary('GCC_ENG_ROADS','REGION','South',city,NULL);
    rgnN  := _seed_boundary('GCC_ENG_ROADS','REGION','North',city,NULL);
    zoneA := _seed_boundary('GCC_ENG_ROADS','ZONE','Adyar',rgnS,NULL);
    zoneP := _seed_boundary('GCC_ENG_ROADS','ZONE','Perambur',rgnN,NULL);
    wardG := _seed_boundary('GCC_ENG_ROADS','WARD','Guindy',zoneA,guindy);
    wardP := _seed_boundary('GCC_ENG_ROADS','WARD','Perambur',zoneP,perambur);
    PERFORM _seed_boundary('GCC_ENG_ROADS','WARD','Ward 175',NULL,adyar); -- narrow placeholder
    -- Guindy
    PERFORM _seed_officer('GCC_ENG_ROADS','Junior Engineer',wardG,'Guindy');
    PERFORM _seed_officer('GCC_ENG_ROADS','Assistant Engineer',wardG,'Guindy');
    PERFORM _seed_officer('GCC_ENG_ROADS','Assistant Executive Engineer',zoneA,'Adyar Zone');
    PERFORM _seed_officer('GCC_ENG_ROADS','Executive Engineer',zoneA,'Adyar Zone');
    PERFORM _seed_officer('GCC_ENG_ROADS','Superintending Engineer',rgnS,'South Region');
    PERFORM _seed_officer('GCC_ENG_ROADS','Chief Engineer (Works)',city,'Chennai City');
    -- Perambur
    PERFORM _seed_officer('GCC_ENG_ROADS','Junior Engineer',wardP,'Perambur');
    PERFORM _seed_officer('GCC_ENG_ROADS','Assistant Engineer',wardP,'Perambur');
    PERFORM _seed_officer('GCC_ENG_ROADS','Assistant Executive Engineer',zoneP,'Perambur Zone');
    PERFORM _seed_officer('GCC_ENG_ROADS','Executive Engineer',zoneP,'Perambur Zone');
    PERFORM _seed_officer('GCC_ENG_ROADS','Superintending Engineer',rgnN,'North Region');

    -- ============================== GCC_ELECT =============================
    -- WARD -> ZONE -> REGION -> CITY (JE=WARD; AE,EE=ZONE; SE=REGION; CE=CITY)
    city  := _seed_boundary('GCC_ELECT','CITY','Chennai City',NULL,NULL);
    rgnS  := _seed_boundary('GCC_ELECT','REGION','South',city,NULL);
    rgnN  := _seed_boundary('GCC_ELECT','REGION','North',city,NULL);
    zoneA := _seed_boundary('GCC_ELECT','ZONE','Adyar',rgnS,NULL);
    zoneP := _seed_boundary('GCC_ELECT','ZONE','Perambur',rgnN,NULL);
    wardG := _seed_boundary('GCC_ELECT','WARD','Guindy',zoneA,guindy);
    wardP := _seed_boundary('GCC_ELECT','WARD','Perambur',zoneP,perambur);
    PERFORM _seed_boundary('GCC_ELECT','WARD','Ward 175',NULL,adyar);
    -- Guindy
    PERFORM _seed_officer('GCC_ELECT','Junior Engineer (Electrical)',wardG,'Guindy');
    PERFORM _seed_officer('GCC_ELECT','Assistant Engineer (Electrical)',zoneA,'Adyar Zone');
    PERFORM _seed_officer('GCC_ELECT','Executive Engineer (Electrical)',zoneA,'Adyar Zone');
    PERFORM _seed_officer('GCC_ELECT','Superintending Engineer (Electrical)',rgnS,'South Region');
    PERFORM _seed_officer('GCC_ELECT','Chief Engineer (Electrical)',city,'Chennai City');
    -- Perambur
    PERFORM _seed_officer('GCC_ELECT','Junior Engineer (Electrical)',wardP,'Perambur');
    PERFORM _seed_officer('GCC_ELECT','Assistant Engineer (Electrical)',zoneP,'Perambur Zone');
    PERFORM _seed_officer('GCC_ELECT','Executive Engineer (Electrical)',zoneP,'Perambur Zone');
    PERFORM _seed_officer('GCC_ELECT','Superintending Engineer (Electrical)',rgnN,'North Region');

    -- ============================= CMWSSB_SEW =============================
    -- SUBDIVISION -> AREA_DIVISION -> REGION -> CITY
    city  := _seed_boundary('CMWSSB_SEW','CITY','Board-wide',NULL,NULL);
    rgnS  := _seed_boundary('CMWSSB_SEW','REGION','South',city,NULL);
    rgnN  := _seed_boundary('CMWSSB_SEW','REGION','North',city,NULL);
    areaG := _seed_boundary('CMWSSB_SEW','AREA_DIVISION','Guindy Area',rgnS,NULL);
    areaP := _seed_boundary('CMWSSB_SEW','AREA_DIVISION','Perambur Area',rgnN,NULL);
    subG  := _seed_boundary('CMWSSB_SEW','SUBDIVISION','Guindy Sub-division',areaG,guindy);
    subP  := _seed_boundary('CMWSSB_SEW','SUBDIVISION','Perambur Sub-division',areaP,perambur);
    PERFORM _seed_boundary('CMWSSB_SEW','SUBDIVISION','Adyar Sewerage Sub-division',NULL,adyar);
    -- Guindy
    PERFORM _seed_officer('CMWSSB_SEW','Assistant Engineer (Sewerage)',subG,'Guindy');
    PERFORM _seed_officer('CMWSSB_SEW','Assistant Executive Engineer',areaG,'Guindy Area');
    PERFORM _seed_officer('CMWSSB_SEW','Executive Engineer',rgnS,'South Region');
    PERFORM _seed_officer('CMWSSB_SEW','Superintending Engineer',rgnS,'South Region');
    PERFORM _seed_officer('CMWSSB_SEW','Chief Engineer (Sewerage)',city,'Board-wide');
    -- Perambur
    PERFORM _seed_officer('CMWSSB_SEW','Assistant Engineer (Sewerage)',subP,'Perambur');
    PERFORM _seed_officer('CMWSSB_SEW','Assistant Executive Engineer',areaP,'Perambur Area');
    PERFORM _seed_officer('CMWSSB_SEW','Executive Engineer',rgnN,'North Region');
    PERFORM _seed_officer('CMWSSB_SEW','Superintending Engineer',rgnN,'North Region');

    -- ============================ TANGEDCO_PWR ============================
    -- SECTION -> SUBDIVISION -> DIVISION -> CIRCLE -> CITY
    city  := _seed_boundary('TANGEDCO_PWR','CITY','TNEB Chennai',NULL,NULL);
    circS := _seed_boundary('TANGEDCO_PWR','CIRCLE','Chennai South EDC',city,NULL);
    circN := _seed_boundary('TANGEDCO_PWR','CIRCLE','Chennai North EDC',city,NULL);
    divG  := _seed_boundary('TANGEDCO_PWR','DIVISION','Guindy Division',circS,NULL);
    divP  := _seed_boundary('TANGEDCO_PWR','DIVISION','Perambur Division',circN,NULL);
    subG  := _seed_boundary('TANGEDCO_PWR','SUBDIVISION','Guindy Sub-division',divG,NULL);
    subP  := _seed_boundary('TANGEDCO_PWR','SUBDIVISION','Perambur Sub-division',divP,NULL);
    secG  := _seed_boundary('TANGEDCO_PWR','SECTION','Guindy Section',subG,guindy);
    secP  := _seed_boundary('TANGEDCO_PWR','SECTION','Perambur Section',subP,perambur);
    PERFORM _seed_boundary('TANGEDCO_PWR','SECTION','Adyar Section',NULL,adyar);
    -- Guindy
    PERFORM _seed_officer('TANGEDCO_PWR','Junior Engineer (O&M)',secG,'Guindy');
    PERFORM _seed_officer('TANGEDCO_PWR','Assistant Engineer / AEE (O&M)',subG,'Guindy Sub-division');
    PERFORM _seed_officer('TANGEDCO_PWR','Executive Engineer',divG,'Guindy Division');
    PERFORM _seed_officer('TANGEDCO_PWR','Superintending Engineer',circS,'Chennai South EDC');
    PERFORM _seed_officer('TANGEDCO_PWR','Chief Distribution Engineer',city,'TNEB Chennai');
    -- Perambur
    PERFORM _seed_officer('TANGEDCO_PWR','Junior Engineer (O&M)',secP,'Perambur');
    PERFORM _seed_officer('TANGEDCO_PWR','Assistant Engineer / AEE (O&M)',subP,'Perambur Sub-division');
    PERFORM _seed_officer('TANGEDCO_PWR','Executive Engineer',divP,'Perambur Division');
    PERFORM _seed_officer('TANGEDCO_PWR','Superintending Engineer',circN,'Chennai North EDC');

    -- ============================ GCP_LAW_ORD ============================
    -- STATION_JURISDICTION -> SUBDIVISION -> POLICE_ZONE -> CITY
    city  := _seed_boundary('GCP_LAW_ORD','CITY','Greater Chennai Police',NULL,NULL);
    rgnS  := _seed_boundary('GCP_LAW_ORD','POLICE_ZONE','South Zone',city,NULL);
    rgnN  := _seed_boundary('GCP_LAW_ORD','POLICE_ZONE','North Zone',city,NULL);
    subG  := _seed_boundary('GCP_LAW_ORD','SUBDIVISION','Guindy Sub-division',rgnS,NULL);
    subP  := _seed_boundary('GCP_LAW_ORD','SUBDIVISION','Perambur Sub-division',rgnN,NULL);
    stnG  := _seed_boundary('GCP_LAW_ORD','STATION_JURISDICTION','Guindy PS',subG,guindy);
    stnP  := _seed_boundary('GCP_LAW_ORD','STATION_JURISDICTION','Perambur PS',subP,perambur);
    PERFORM _seed_boundary('GCP_LAW_ORD','STATION_JURISDICTION','Adyar PS',NULL,adyar);
    -- Guindy
    PERFORM _seed_officer('GCP_LAW_ORD','Sub-Inspector (SI)',stnG,'Guindy PS');
    PERFORM _seed_officer('GCP_LAW_ORD','Inspector of Police',stnG,'Guindy PS');
    PERFORM _seed_officer('GCP_LAW_ORD','Assistant Commissioner of Police (ACP)',subG,'Guindy Sub-division');
    PERFORM _seed_officer('GCP_LAW_ORD','Deputy Commissioner of Police (DCP)',rgnS,'South Zone');
    PERFORM _seed_officer('GCP_LAW_ORD','Joint Commissioner of Police',rgnS,'South Zone');
    PERFORM _seed_officer('GCP_LAW_ORD','Commissioner of Police',city,'Greater Chennai Police');
    -- Perambur
    PERFORM _seed_officer('GCP_LAW_ORD','Sub-Inspector (SI)',stnP,'Perambur PS');
    PERFORM _seed_officer('GCP_LAW_ORD','Inspector of Police',stnP,'Perambur PS');
    PERFORM _seed_officer('GCP_LAW_ORD','Assistant Commissioner of Police (ACP)',subP,'Perambur Sub-division');
    PERFORM _seed_officer('GCP_LAW_ORD','Deputy Commissioner of Police (DCP)',rgnN,'North Zone');
    PERFORM _seed_officer('GCP_LAW_ORD','Joint Commissioner of Police',rgnN,'North Zone');
END $$;

DROP FUNCTION _seed_boundary(TEXT, TEXT, TEXT, INT, GEOMETRY);
DROP FUNCTION _seed_officer(TEXT, TEXT, INT, TEXT);
DROP SEQUENCE _seed_phone_seq;

COMMIT;

-- Roster of everyone this seed created (log in with dummy OTP 123456):
SELECT o.department_id, dg.rank_order, dg.designation_name,
       b.level_name, b.boundary_name, o.full_name, o.phone
FROM officers o
JOIN designations dg
    ON dg.department_id = o.department_id AND dg.designation_id = o.designation_id
JOIN boundaries b ON b.boundary_id = o.boundary_id
WHERE o.email = 'seed-test@civicroute.local'
ORDER BY o.department_id, dg.rank_order, b.boundary_name;
