import asyncio
import uuid
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.models.all_models import Base, Department, Jurisdiction, User

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
        # Using simple polygon coordinates that represent adjacent grid zones
        # Coordinates form a grid around (13.08, 80.25)
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
        # Note: In production, these match the Sub/UID from Supabase auth.users
        users = [
            # Officers
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
            # Supervisors
            User(
                id=uuid.UUID("44444444-4444-4444-4444-444444444444"),
                name="Supervisor Zone A", role="supervisor",
                phone="+919999911111", email="super.zonea@civicroute.gov.in",
                jurisdiction_id=jurisdictions[0].id # Supervisor located in Zone A
            ),
            User(
                id=uuid.UUID("55555555-5555-5555-5555-555555555555"),
                name="Supervisor Zone B", role="supervisor",
                phone="+919999911112", email="super.zoneb@civicroute.gov.in",
                jurisdiction_id=jurisdictions[4].id # Supervisor located in Zone B
            ),
            # Admin user for testing triage
            User(
                id=uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                name="Admin Root", role="admin",
                phone="+919999999999", email="admin@civicroute.gov.in",
                jurisdiction_id=None
            )
        ]
        session.add_all(users)
        await session.commit()
        print("Seeded 6 staff users (3 officers, 2 supervisors, 1 admin).")

    print("Database seeding completed successfully.")

if __name__ == "__main__":
    asyncio.run(seed_data())
