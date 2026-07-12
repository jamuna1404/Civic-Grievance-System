import asyncio
import math
from typing import List, Tuple, Optional
from app.services.gis_resolver import resolve_gis_jurisdiction

# Mock Department model matching seed structure
class MockDepartment:
    def __init__(self, id: int, name: str, category: str):
        self.id = id
        self.name = name
        self.category = category

# Mock Jurisdiction model matching schema
class MockJurisdiction:
    def __init__(
        self, id: int, zone: str, ward: str, area_name: str, 
        center: Tuple[float, float], department_id: int, 
        office_name: str, officer_contact: str
    ):
        self.id = id
        self.zone = zone
        self.ward = ward
        self.area_name = area_name
        self.center = center  # (lat, lng) representing centroid
        self.department_id = department_id
        self.office_name = office_name
        self.officer_contact = officer_contact

# 1. Predefine Mock Departments and 8 Jurisdictions
DEPARTMENTS = [
    MockDepartment(1, "Water Supply & Sewerage", "Water Supply & Sewerage"),
    MockDepartment(2, "Solid Waste Management", "Solid Waste Management"),
    MockDepartment(3, "Roads & Public Works", "Roads & Public Works"),
    MockDepartment(4, "Electricity Grid & Power", "Electricity Grid & Power"),
    MockDepartment(5, "Streetlight Maintenance", "Streetlight Maintenance")
]

DEPARTMENTS_DICT = {d.id: d.name for d in DEPARTMENTS}

JURISDICTIONS = [
    # Zone A Wards (1 to 4)
    MockJurisdiction(1, "Zone A", "Ward 1", "Vyasarpadi", (13.095, 80.245), 1, "Ward 1 Water Office", "+919876543210"),
    MockJurisdiction(2, "Zone A", "Ward 2", "Perambur", (13.095, 80.255), 2, "Ward 2 Sanitation Office", "+919876543211"),
    MockJurisdiction(3, "Zone A", "Ward 3", "Otteri", (13.085, 80.245), 3, "Ward 3 Public Works Office", "+919876543212"),
    MockJurisdiction(4, "Zone A", "Ward 4", "Purasawalkam", (13.085, 80.255), 4, "Ward 4 Electricity Office", "+919876543213"),
    
    # Zone B Wards (5 to 8)
    MockJurisdiction(5, "Zone B", "Ward 5", "Kilpauk", (13.075, 80.235), 5, "Ward 5 Streetlight Office", "+919876543214"),
    MockJurisdiction(6, "Zone B", "Ward 6", "Nungambakkam", (13.065, 80.245), 1, "Ward 6 Water Office", "+919876543215"),
    MockJurisdiction(7, "Zone B", "Ward 7", "Egmore", (13.065, 80.255), 2, "Ward 7 Sanitation Office", "+919876543216"),
    MockJurisdiction(8, "Zone B", "Ward 8", "Triplicane", (13.055, 80.265), 3, "Ward 8 PWD Office", "+919876543217")
]

# Global test state variables to mock spatial queries dynamically
current_lat = None
current_lng = None

# Mock database result wrapper
class MockResult:
    def __init__(self, data):
        self.data = data
    def scalars(self):
        class MockScalars:
            def __init__(self, data):
                self.data = data
            def all(self):
                return self.data
        return MockScalars(self.data)
    def scalar_one_or_none(self):
        return self.data[0] if self.data else None
    def first(self):
        return self.data[0] if self.data else None

# Mock database session simulating PostGIS queries (ST_Contains, ST_Distance, Centroid)
class MockDbSession:
    async def execute(self, stmt):
        stmt_str = str(stmt).lower()
        params = stmt.compile().params
        param_values = list(params.values())
        
        # Scenario A: ST_Contains query
        if "st_contains" in stmt_str:
            containing_j = []
            for j in JURISDICTIONS:
                lat_min, lat_max = j.center[0] - 0.005, j.center[0] + 0.005
                lng_min, lng_max = j.center[1] - 0.005, j.center[1] + 0.005
                
                if (lat_min <= current_lat <= lat_max) and (lng_min <= current_lng <= lng_max):
                    containing_j.append(j)
            return MockResult(containing_j)
            
        # Scenario B: exact ward-level office query
        elif "jurisdictions.ward =" in stmt_str:
            matched = []
            for j in JURISDICTIONS:
                if j.ward in param_values and j.department_id in param_values:
                    matched.append(j)
            return MockResult(matched)
            
        # Scenario C: escalated zone-level office query
        elif "jurisdictions.zone =" in stmt_str:
            matched = []
            for j in JURISDICTIONS:
                if j.zone in param_values and j.department_id in param_values:
                    matched.append(j)
            return MockResult(matched)
            
        # Scenario D: nearest centroid fallback query
        elif "st_centroid" in stmt_str or "st_distance" in stmt_str:
            results = []
            for j in JURISDICTIONS:
                if j.department_id in param_values:
                    dist = math.sqrt((j.center[0] - current_lat)**2 + (j.center[1] - current_lng)**2)
                    results.append((j, dist))
            
            # Sort by distance
            results.sort(key=lambda x: x[1])
            return MockResult(results)
            
        # Default query handler
        elif "select departments" in stmt_str or "from departments" in stmt_str:
            return MockResult(DEPARTMENTS)
            
        return MockResult([])


async def run_tests():
    global current_lat, current_lng
    print("--- Running Offline Mocked GIS Spatial Database Tests ---")
    db = MockDbSession()
    
    # Test Case 1: Point inside Ward 3 (Otteri - Roads & Public Works)
    # Centroid: (13.085, 80.245)
    current_lat = 13.085
    current_lng = 80.245
    roads_dept_id = 3 # Roads & Public Works
    
    print(f"\nTest 1: Querying coordinate ({current_lat}, {current_lng}) inside Ward 3 (Roads)...")
    res1 = await resolve_gis_jurisdiction(db, current_lat, current_lng, None, roads_dept_id)
    
    print(f"Result1: Jurisdiction ID : {res1['jurisdiction_id']}")
    print(f"Result1: Method          : {res1['gis_resolution_method']}")
    print(f"Result1: Uncertain Flag   : {res1['jurisdiction_uncertain']}")
    
    # Assertions
    assert res1['jurisdiction_id'] == 3, f"Expected office ID 3 (Ward 3 Roads), got {res1['jurisdiction_id']}"
    assert res1['gis_resolution_method'] == "direct_coordinates_polygon_match"
    assert res1['jurisdiction_uncertain'] is False
    print("Test 1: PASS [OK]")

    # Test Case 2: Escalation test
    # Point inside Ward 1 (Vyasarpadi - Water office), but request Solid Waste (Sanitation) department.
    # Vyasarpadi center = (13.095, 80.245). Solid Waste dept_id = 2.
    # Ward 1 has no Solid Waste office. It must escalate to Ward 2 (Perambur) Sanitation Office in Zone A.
    current_lat = 13.095
    current_lng = 80.245
    waste_dept_id = 2 # Solid Waste Management
    
    print(f"\nTest 2: Querying coordinate ({current_lat}, {current_lng}) inside Ward 1 with Sanitation department (Escalation)...")
    res2 = await resolve_gis_jurisdiction(db, current_lat, current_lng, None, waste_dept_id)
    
    print(f"Result2: Jurisdiction ID : {res2['jurisdiction_id']}")
    print(f"Result2: Method          : {res2['gis_resolution_method']}")
    print(f"Result2: Uncertain Flag   : {res2['jurisdiction_uncertain']}")
    
    # Assertions
    assert res2['jurisdiction_id'] == 2, f"Expected escalated office ID 2 (Ward 2 Sanitation), got {res2['jurisdiction_id']}"
    assert res2['gis_resolution_method'] == "direct_coordinates_zone_escalation"
    assert res2['jurisdiction_uncertain'] is False
    print("Test 2: PASS [OK]")

    # Test Case 3: Point outside all seeded boundaries (Fallback to nearest centroid)
    # Target: point (13.020, 80.200) is close to Nungambakkam (Ward 6, Water office) center (13.065, 80.245)
    # Distance is about 0.063, which is within max_radius = 0.08.
    current_lat = 13.020
    current_lng = 80.200
    water_dept_id = 1 # Water Supply & Sewerage
    
    print(f"\nTest 3: Querying out-of-bounds coordinate ({current_lat}, {current_lng}) within distance threshold...")
    res3 = await resolve_gis_jurisdiction(db, current_lat, current_lng, None, water_dept_id)
    
    print(f"Result3: Jurisdiction ID : {res3['jurisdiction_id']}")
    print(f"Result3: Method          : {res3['gis_resolution_method']}")
    print(f"Result3: Uncertain Flag   : {res3['jurisdiction_uncertain']}")
    
    # Assertions
    assert res3['jurisdiction_id'] == 6, f"Expected nearest centroid office ID 6, got {res3['jurisdiction_id']}"
    assert res3['gis_resolution_method'] == "nearest_centroid"
    assert res3['jurisdiction_uncertain'] is True
    print("Test 3: PASS [OK]")

    # Test Case 4: Extreme out-of-bounds point (beyond max radius threshold)
    current_lat = 12.000
    current_lng = 79.000
    print(f"\nTest 4: Querying extreme out-of-bounds coordinate ({current_lat}, {current_lng})...")
    res4 = await resolve_gis_jurisdiction(db, current_lat, current_lng, None, roads_dept_id)
    
    print(f"Result4: Jurisdiction ID : {res4['jurisdiction_id']}")
    print(f"Result4: Method          : {res4['gis_resolution_method']}")
    print(f"Result4: Uncertain Flag   : {res4['jurisdiction_uncertain']}")
    
    # Assertions
    assert res4['jurisdiction_id'] is None
    assert res4['gis_resolution_method'] == "out_of_bounds"
    assert res4['jurisdiction_uncertain'] is True
    print("Test 4: PASS [OK]")

    # Test Case 5: Geocoding fallback match
    # Free-text address: "Vyasarpadi, Chennai" which resolves to cache (13.095, 80.245).
    # Requested water department (ID = 1). Should match Ward 1 Water office.
    current_lat = 13.095
    current_lng = 80.245
    print("\nTest 5: Querying address 'Vyasarpadi, Chennai' without lat/lng coordinates (Geocoding fallback)...")
    res5 = await resolve_gis_jurisdiction(db, None, None, "Vyasarpadi, Chennai", water_dept_id)
    
    print(f"Result5: Jurisdiction ID : {res5['jurisdiction_id']}")
    print(f"Result5: Method          : {res5['gis_resolution_method']}")
    print(f"Result5: Uncertain Flag   : {res5['jurisdiction_uncertain']}")
    
    # Assertions
    assert res5['jurisdiction_id'] == 1
    assert res5['gis_resolution_method'] == "geocoded_address_polygon_match"
    assert res5['jurisdiction_uncertain'] is False
    print("Test 5: PASS [OK]")

    print("\nAll GIS Resolver unit tests passed successfully!")

if __name__ == "__main__":
    asyncio.run(run_tests())
