-- =====================================================================
-- CivicRoute — placeholder seed data (run AFTER verifying Prompt 1's
-- schema files applied cleanly). Purely for development/testing —
-- rectangles around central Chennai, NOT real administrative boundaries.
-- =====================================================================

-- One top-level CITY boundary + one leaf-level (rank 1) boundary per
-- department, each with a placeholder rectangle polygon, so the
-- enrollment picker and resolve_officer_for_complaint() both have
-- something to query against.

-- GCC_ENG_ROADS: Region -> Zone -> Ward chain
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCC_ENG_ROADS','CITY','Chennai City', NULL, NULL);

INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_ROADS','REGION','South',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_ROADS' AND boundary_name='Chennai City'),
       NULL;

INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_ROADS','ZONE','Adyar',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_ROADS' AND boundary_name='South'),
       NULL;

INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_ROADS','WARD','Ward 175',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_ROADS' AND boundary_name='Adyar'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

-- Repeat the same 4-level chain for the other GCC departments (they
-- share the same real hierarchy, just separate cadres per department)
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCC_PH_SAN','CITY','Chennai City', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_PH_SAN','ZONE','Adyar',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_PH_SAN' AND boundary_name='Chennai City'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_PH_SAN','WARD','Ward 175',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_PH_SAN' AND boundary_name='Adyar'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCC_ENG_SWD','CITY','Chennai City', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_SWD','REGION','South',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_SWD' AND boundary_name='Chennai City'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_SWD','ZONE','Adyar',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_SWD' AND boundary_name='South'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ENG_SWD','WARD','Ward 175',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_SWD' AND boundary_name='Adyar'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCC_ELECT','CITY','Chennai City', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ELECT','ZONE','Adyar',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ELECT' AND boundary_name='Chennai City'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCC_ELECT','WARD','Ward 175',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ELECT' AND boundary_name='Adyar'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

-- CMWSSB_SEW: Sub-division -> Area Division -> Region -> City
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('CMWSSB_SEW','CITY','Board-wide', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'CMWSSB_SEW','AREA_DIVISION','Area VI - Adyar',
       (SELECT boundary_id FROM boundaries WHERE department_id='CMWSSB_SEW' AND boundary_name='Board-wide'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'CMWSSB_SEW','SUBDIVISION','Adyar Sewerage Sub-division',
       (SELECT boundary_id FROM boundaries WHERE department_id='CMWSSB_SEW' AND boundary_name='Area VI - Adyar'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

-- TANGEDCO_PWR: Section -> Sub-division -> Division -> Circle -> City
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('TANGEDCO_PWR','CITY','TNEB Chennai', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'TANGEDCO_PWR','CIRCLE','Chennai South EDC',
       (SELECT boundary_id FROM boundaries WHERE department_id='TANGEDCO_PWR' AND boundary_name='TNEB Chennai'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'TANGEDCO_PWR','DIVISION','Adyar Division',
       (SELECT boundary_id FROM boundaries WHERE department_id='TANGEDCO_PWR' AND boundary_name='Chennai South EDC'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'TANGEDCO_PWR','SUBDIVISION','Adyar Sub-division',
       (SELECT boundary_id FROM boundaries WHERE department_id='TANGEDCO_PWR' AND boundary_name='Adyar Division'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'TANGEDCO_PWR','SECTION','Adyar Section',
       (SELECT boundary_id FROM boundaries WHERE department_id='TANGEDCO_PWR' AND boundary_name='Adyar Sub-division'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

-- GCP_LAW_ORD: Station -> Sub-division -> Police Zone -> City
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom) VALUES
('GCP_LAW_ORD','CITY','Greater Chennai Police', NULL, NULL);
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCP_LAW_ORD','POLICE_ZONE','South Zone',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCP_LAW_ORD' AND boundary_name='Greater Chennai Police'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCP_LAW_ORD','SUBDIVISION','Adyar Sub-division',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCP_LAW_ORD' AND boundary_name='South Zone'), NULL;
INSERT INTO boundaries (department_id, level_name, boundary_name, parent_boundary_id, geom)
SELECT 'GCP_LAW_ORD','STATION_JURISDICTION','Adyar PS',
       (SELECT boundary_id FROM boundaries WHERE department_id='GCP_LAW_ORD' AND boundary_name='Adyar Sub-division'),
       ST_Multi(ST_GeomFromText(
         'POLYGON((80.05 12.85, 80.35 12.85, 80.35 13.25, 80.05 13.25, 80.05 12.85))', 4326));

-- ---------------------------------------------------------------------
-- One dummy ACTIVE officer per department, at the leaf boundary above,
-- so complaint routing has someone to assign to during testing.
-- ---------------------------------------------------------------------
INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - Roads', '+919000000001', 'test.roads@example.com',
       'GCC_ENG_ROADS',
       (SELECT designation_id FROM designations WHERE department_id='GCC_ENG_ROADS' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_ROADS' AND boundary_name='Ward 175'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - Sanitation', '+919000000002', 'test.san@example.com',
       'GCC_PH_SAN',
       (SELECT designation_id FROM designations WHERE department_id='GCC_PH_SAN' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_PH_SAN' AND boundary_name='Ward 175'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - SWD', '+919000000003', 'test.swd@example.com',
       'GCC_ENG_SWD',
       (SELECT designation_id FROM designations WHERE department_id='GCC_ENG_SWD' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ENG_SWD' AND boundary_name='Ward 175'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - Electrical', '+919000000004', 'test.elect@example.com',
       'GCC_ELECT',
       (SELECT designation_id FROM designations WHERE department_id='GCC_ELECT' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='GCC_ELECT' AND boundary_name='Ward 175'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - Metrowater', '+919000000005', 'test.cmwssb@example.com',
       'CMWSSB_SEW',
       (SELECT designation_id FROM designations WHERE department_id='CMWSSB_SEW' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='CMWSSB_SEW' AND boundary_name='Adyar Sewerage Sub-division'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - TANGEDCO', '+919000000006', 'test.tangedco@example.com',
       'TANGEDCO_PWR',
       (SELECT designation_id FROM designations WHERE department_id='TANGEDCO_PWR' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='TANGEDCO_PWR' AND boundary_name='Adyar Section'),
       'ACTIVE';

INSERT INTO officers (full_name, phone, email, department_id, designation_id, boundary_id, status)
SELECT 'Test Officer - Police', '+919000000007', 'test.police@example.com',
       'GCP_LAW_ORD',
       (SELECT designation_id FROM designations WHERE department_id='GCP_LAW_ORD' AND rank_order=1),
       (SELECT boundary_id FROM boundaries WHERE department_id='GCP_LAW_ORD' AND boundary_name='Adyar PS'),
       'ACTIVE';

-- ---------------------------------------------------------------------
-- Quick sanity check: this should return the Roads test officer above,
-- since (80.24, 13.00) falls inside the placeholder rectangle.
-- ---------------------------------------------------------------------
-- SELECT * FROM resolve_officer_for_complaint('GCC_ENG_ROADS', 80.24, 13.00);
