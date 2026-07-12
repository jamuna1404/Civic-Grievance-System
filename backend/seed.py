import asyncio
import uuid
import random
from datetime import datetime, timedelta
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.models.all_models import Base, Department, Jurisdiction, User, Complaint, ComplaintEvent

# Async engine for DB seed
engine = create_async_engine(settings.DATABASE_URL, echo=True)
SessionLocal = async_sessionmaker(bind=engine, expire_on_commit=False)

async def seed_data():
    print("Enabling PostGIS extension...")
    async with engine.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))

    print("Re-creating all tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    async with SessionLocal() as session:
        # 1. Seed Departments (FR-4.4 base weight configurations)
        departments = [
            Department(name="Water Supply & Sewerage", category="Water Supply", sla_hours=24),
            Department(name="Solid Waste Management", category="Waste Management", sla_hours=48),
            Department(name="Roads & Public Works", category="Public Works", sla_hours=72),
            Department(name="Electricity Grid & Power", category="Electricity", sla_hours=12),
            Department(name="Streetlight Maintenance", category="Streetlights", sla_hours=24)
        ]
        session.add_all(departments)
        await session.commit()
        print("Seeded 5 departments.")

        # Refresh departments to get their IDs
        water_dept = departments[0]
        waste_dept = departments[1]
        roads_dept = departments[2]
        elec_dept = departments[3]
        lights_dept = departments[4]

        # 2. Seed 8 Jurisdictions (Wards 1 to 8 in Chennai grid)
        jurisdictions = [
            Jurisdiction(
                zone="Zone A", ward="Ward 1", area_name="Vyasarpadi",
                boundary="SRID=4326;POLYGON((80.24 13.09, 80.25 13.09, 80.25 13.10, 80.24 13.10, 80.24 13.09))",
                department_id=water_dept.id, office_name="Ward 1 Water Office", officer_contact="+919876543210"
            ),
            Jurisdiction(
                zone="Zone A", ward="Ward 2", area_name="Perambur",
                boundary="SRID=4326;POLYGON((80.25 13.09, 80.26 13.09, 80.26 13.10, 80.25 13.10, 80.25 13.09))",
                department_id=waste_dept.id, office_name="Ward 2 Sanitation Office", officer_contact="+919876543211"
            ),
            Jurisdiction(
                zone="Zone A", ward="Ward 3", area_name="Otteri",
                boundary="SRID=4326;POLYGON((80.24 13.08, 80.25 13.08, 80.25 13.09, 80.24 13.09, 80.24 13.08))",
                department_id=roads_dept.id, office_name="Ward 3 Public Works Office", officer_contact="+919876543212"
            ),
            Jurisdiction(
                zone="Zone A", ward="Ward 4", area_name="Purasawalkam",
                boundary="SRID=4326;POLYGON((80.25 13.08, 80.26 13.08, 80.26 13.09, 80.25 13.09, 80.25 13.08))",
                department_id=elec_dept.id, office_name="Ward 4 Electricity Office", officer_contact="+919876543213"
            ),
            Jurisdiction(
                zone="Zone B", ward="Ward 5", area_name="Kilpauk",
                boundary="SRID=4326;POLYGON((80.23 13.07, 80.24 13.07, 80.24 13.08, 80.23 13.08, 80.23 13.07))",
                department_id=lights_dept.id, office_name="Ward 5 Streetlight Office", officer_contact="+919876543214"
            ),
            Jurisdiction(
                zone="Zone B", ward="Ward 6", area_name="Nungambakkam",
                boundary="SRID=4326;POLYGON((80.24 13.06, 80.25 13.06, 80.25 13.07, 80.24 13.07, 80.24 13.06))",
                department_id=water_dept.id, office_name="Ward 6 Water Office", officer_contact="+919876543215"
            ),
            Jurisdiction(
                zone="Zone B", ward="Ward 7", area_name="Egmore",
                boundary="SRID=4326;POLYGON((80.25 13.06, 80.26 13.06, 80.26 13.07, 80.25 13.07, 80.25 13.06))",
                department_id=waste_dept.id, office_name="Ward 7 Sanitation Office", officer_contact="+919876543216"
            ),
            Jurisdiction(
                zone="Zone B", ward="Ward 8", area_name="Triplicane",
                boundary="SRID=4326;POLYGON((80.26 13.05, 80.27 13.05, 80.27 13.06, 80.26 13.06, 80.26 13.05))",
                department_id=roads_dept.id, office_name="Ward 8 PWD Office", officer_contact="+919876543217"
            )
        ]
        session.add_all(jurisdictions)
        await session.commit()
        print("Seeded 8 jurisdictions.")

        # 3. Seed Users (3 Officers + 2 Supervisors with fixed UUIDs for local dev auth integration)
        users = [
            User(
                id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
                name="Officer Vyasarpadi (Water)", role="officer",
                phone="+919999900001", email="officer.water@civicroute.gov.in",
                jurisdiction_id=jurisdictions[0].id
            ),
            User(
                id=uuid.UUID("22222222-2222-2222-2222-222222222222"),
                name="Officer Perambur (Sanitation)", role="officer",
                phone="+919999900002", email="officer.waste@civicroute.gov.in",
                jurisdiction_id=jurisdictions[1].id
            ),
            User(
                id=uuid.UUID("33333333-3333-3333-3333-333333333333"),
                name="Officer Otteri (Roads)", role="officer",
                phone="+919999900003", email="officer.roads@civicroute.gov.in",
                jurisdiction_id=jurisdictions[2].id
            ),
            User(
                id=uuid.UUID("44444444-4444-4444-4444-444444444444"),
                name="Supervisor Zone A", role="supervisor",
                phone="+919999911111", email="super.zonea@civicroute.gov.in",
                jurisdiction_id=jurisdictions[0].id
            ),
            User(
                id=uuid.UUID("55555555-5555-5555-5555-555555555555"),
                name="Supervisor Zone B", role="supervisor",
                phone="+919999911112", email="super.zoneb@civicroute.gov.in",
                jurisdiction_id=jurisdictions[4].id
            ),
            User(
                id=uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                name="Admin Root", role="admin",
                phone="+919999999999", email="admin@civicroute.gov.in",
                jurisdiction_id=None
            ),
            # Seed Dummy Citizens
            User(
                id=uuid.UUID("cccccc11-cccc-cccc-cccc-cccccccccccc"),
                name="Citizen Jan", role="citizen",
                phone="+919999900101", email="citizen.jan@example.com",
                jurisdiction_id=None
            ),
            User(
                id=uuid.UUID("cccccc22-cccc-cccc-cccc-cccccccccccc"),
                name="Citizen Anbarasu", role="citizen",
                phone="+919999900102", email="citizen.anbu@example.com",
                jurisdiction_id=None
            )
        ]
        session.add_all(users)
        await session.commit()
        print("Seeded 8 users (3 officers, 2 supervisors, 1 admin, 2 citizens).")

        # 4. Generate ~150 synthetic complaints spread across departments/wards/priorities/statuses/languages (FR-4.5 scaling)
        citizen_ids = [users[6].id, users[7].id]
        
        # Subcategory and text catalogs
        water_issues = ["pipe leak", "water contamination", "low pressure", "drain overflow"]
        waste_issues = ["garbage pile", "dead animal", "littering", "dustbin damage"]
        roads_issues = ["pothole", "broken pavement", "water logging", "road cave-in"]
        elec_issues = ["power cut", "sparking wire", "voltage fluctuation", "transformer blast"]
        lights_issues = ["broken streetlight", "continuous glowing", "dark spot", "leaning pole"]

        english_texts = [
            "Heavy water leakage / pipe leak reported on the street.",
            "Water smells bad and seems to be highly contaminated.",
            "Large garbage pile accumulated on the sidewalk. Unbearable smell.",
            "Deep dangerous pothole in the middle of the road causing accidents.",
            "Electricity wire sparking on the tree branch, very dangerous.",
            "Streetlight is completely broken and the lane is in total darkness."
        ]

        tamil_texts = [
            "En area la heavy aah pipe leak/thanni varala.",
            "Romba naala water contamination prachinai iruku, color change iruku.",
            "Road corner la massive garbage pile kuppai sernthruchu. Smell varuthu.",
            "Pothole roattu nadula iruku, accident aagum. Please fix pannunga.",
            "Electricity grid / power cut problem. Sparking wire iruku.",
            "Velichame illa broken streetlight. Dark spot area safety issue."
        ]

        complaints_list = []
        now = datetime.utcnow()

        for i in range(1, 151):
            comp_id = uuid.uuid4()
            citizen_id = random.choice(citizen_ids)
            dept = random.choice(departments)
            
            # Map subcategory matching department name
            if dept.name == "Water Supply & Sewerage":
                subcat = random.choice(water_issues)
            elif dept.name == "Solid Waste Management":
                subcat = random.choice(waste_issues)
            elif dept.name == "Roads & Public Works":
                subcat = random.choice(roads_issues)
            elif dept.name == "Electricity Grid & Power":
                subcat = random.choice(elec_issues)
            else:
                subcat = random.choice(lights_issues)

            # Choose random jurisdiction (some left null to simulate triage queue)
            juris = None
            if i % 12 != 0:
                juris = random.choice(jurisdictions)

            status = random.choice(["registered", "assigned", "in_progress", "resolved", "closed", "escalated"])
            priority_label = random.choice(["Low", "Medium", "High", "Critical"])
            priority_score = random.randint(15, 95)
            
            # Alternate language
            raw_text = random.choice(tamil_texts) if i % 2 == 0 else random.choice(english_texts)

            # Geographic grid around Chennai center (13.08, 80.25)
            lat = 13.05 + (i * 0.0003) % 0.05
            lng = 80.23 + (i * 0.0002) % 0.04
            location_wkt = f"SRID=4326;POINT({lng} {lat})"

            # SLA calculation
            if status == "escalated":
                created_at = now - timedelta(days=5)
                sla_deadline = now - timedelta(days=2)
            else:
                created_at = now - timedelta(days=1)
                sla_deadline = now + timedelta(hours=dept.sla_hours)

            # Mock priority breakdown (FR-6.3 breakdown transparency)
            breakdown = {
                "base_weight_points": 20 if dept.name == "Water Supply & Sewerage" else 10,
                "keyword_boost_points": 15 if "leak" in raw_text or "pothole" in raw_text else 0,
                "cv_boost_points": 10 if status in ["resolved", "closed"] else 0,
                "cluster_boost_points": 15 if i % 4 == 0 else 0,
                "sla_decay_points": 15 if status == "escalated" else 0
            }

            resolved_note = None
            resolved_image_url = None
            if status in ["resolved", "closed"]:
                resolved_note = "Resolution work verified by field unit."
                resolved_image_url = "https://images.unsplash.com/photo-1595206133361-b1fe343e5e23?q=80&w=300"

            comp = Complaint(
                id=comp_id,
                citizen_id=citizen_id,
                raw_text=raw_text,
                transcribed_text=raw_text,
                detected_language="Tamil" if i % 2 == 0 else "English",
                category=dept.category,
                subcategory=subcat,
                department_id=dept.id,
                jurisdiction_id=juris.id if juris else None,
                status=status,
                priority_label=priority_label,
                priority_score=priority_score,
                priority_breakdown=breakdown,
                resolved_note=resolved_note,
                resolved_image_url=resolved_image_url,
                location=location_wkt,
                address_text=f"Grid Address Area #{i}, Chennai",
                created_at=created_at,
                sla_deadline=sla_deadline
            )
            complaints_list.append(comp)

        session.add_all(complaints_list)
        await session.commit()
        print(f"Generated 150 synthetic seeded complaints.")

    print("Database seeding completed successfully.")

if __name__ == "__main__":
    asyncio.run(seed_data())
