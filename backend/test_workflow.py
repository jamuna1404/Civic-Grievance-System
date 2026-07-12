import unittest
import uuid
import asyncio
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Tuple, Any

from app.models.all_models import Complaint, User, Department, Jurisdiction, Notification, ComplaintEvent
from app.services.workflow_engine import transition_status, check_sla_breaches
from app.services.routing_engine import route_complaint, route_manually_assigned

# Mock classes to simulate database session and retrieve details locally
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

class MockDbSession:
    def __init__(self, users: List[User], jurisdictions: List[Jurisdiction], departments: List[Department]):
        self.users = users
        self.jurisdictions = jurisdictions
        self.departments = departments
        self.added_items = []
        self.committed = False
        
    def add(self, item):
        self.added_items.append(item)
        
    async def commit(self):
        self.committed = True
        
    async def refresh(self, item):
        pass
        
    async def execute(self, stmt):
        stmt_str = str(stmt).lower()
        params = stmt.compile().params
        param_values = list(params.values())
        

        
        # 1. Fetching Users
        if "from users" in stmt_str or "users" in stmt_str:
            if "officer" in param_values:
                # Return officers
                # Filter by jurisdiction if present in parameters
                juris_id = next((val for val in param_values if isinstance(val, int)), None)
                if juris_id:
                    matched = [u for u in self.users if u.role == "officer" and u.jurisdiction_id == juris_id]
                else:
                    matched = [u for u in self.users if u.role == "officer"]
                return MockResult(matched)
                
            elif "supervisor" in param_values:
                # Return supervisors
                # In the supervisor query, we join Jurisdiction and filter on Jurisdiction.zone
                # Let's inspect param_values for the zone string (e.g. "Zone A", "Zone B")
                zone_val = next((val for val in param_values if isinstance(val, str) and val.startswith("Zone")), None)
                if zone_val:
                    # In our setUp, Supervisor Zone A has jurisdiction_id=1, which is in Zone A.
                    if zone_val == "Zone A":
                        return MockResult([self.users[2]]) # Supervisor Zone A
                return MockResult([self.users[2]]) # Fallback to Zone A supervisor
                
            return MockResult(self.users)
            
        # 2. Fetching Jurisdictions
        elif "from jurisdictions" in stmt_str or "jurisdictions" in stmt_str:
            # If query filters by jurisdiction ID
            juris_id = next((val for val in param_values if isinstance(val, int)), None)
            if juris_id:
                matched = [j for j in self.jurisdictions if j.id == juris_id]
                return MockResult(matched)
            return MockResult(self.jurisdictions)
            
        # 3. Fetching Departments
        elif "from departments" in stmt_str or "departments" in stmt_str:
            dept_id = next((val for val in param_values if isinstance(val, int)), None)
            if dept_id:
                matched = [d for d in self.departments if d.id == dept_id]
                return MockResult(matched)
            return MockResult(self.departments)
            
        # 4. Fetching breached complaints for check_sla_breaches
        elif "complaints" in stmt_str and any(("assigned" in val or "in_progress" in val) if isinstance(val, (list, tuple)) else (val in ["assigned", "in_progress"]) for val in param_values):
            breached = [
                c for c in self.added_items 
                if isinstance(c, Complaint) 
                and c.status in ["assigned", "in_progress"] 
                and c.sla_deadline 
                and c.sla_deadline < datetime.utcnow()
            ]
            return MockResult(breached)
            
        return MockResult([])

class TestWorkflowAndRouting(unittest.TestCase):
    
    def setUp(self):
        # Seed Mock DB
        self.dept_water = Department(id=1, name="Water Supply & Sewerage", category="Water", sla_hours=24)
        self.dept_waste = Department(id=2, name="Solid Waste Management", category="Sanitation", sla_hours=48)
        
        self.juris_vyasarpadi = Jurisdiction(
            id=1, zone="Zone A", ward="Ward 1", area_name="Vyasarpadi",
            department_id=1, office_name="Ward 1 Water Office", officer_contact="+919876543210"
        )
        self.juris_perambur = Jurisdiction(
            id=2, zone="Zone A", ward="Ward 2", area_name="Perambur",
            department_id=2, office_name="Ward 2 Sanitation Office", officer_contact="+919876543211"
        )
        self.juris_triplicane = Jurisdiction(
            id=8, zone="Zone B", ward="Ward 8", area_name="Triplicane",
            department_id=1, office_name="Ward 8 Water Office", officer_contact="+919876543217"
        )
        
        self.officer_vyasarpadi = User(
            id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
            name="Officer Vyasarpadi (Water)", role="officer", jurisdiction_id=1
        )
        self.officer_triplicane = User(
            id=uuid.UUID("33333333-3333-3333-3333-333333333333"),
            name="Officer Triplicane (Water)", role="officer", jurisdiction_id=8
        )
        
        self.supervisor_zonea = User(
            id=uuid.UUID("44444444-4444-4444-4444-444444444444"),
            name="Supervisor Zone A", role="supervisor", jurisdiction_id=1
        )
        
        self.citizen = User(
            id=uuid.UUID("99999999-9999-9999-9999-999999999999"),
            name="Citizen Jan", role="citizen", jurisdiction_id=None
        )
        
        self.db = MockDbSession(
            users=[self.officer_vyasarpadi, self.officer_triplicane, self.supervisor_zonea, self.citizen],
            jurisdictions=[self.juris_vyasarpadi, self.juris_perambur, self.juris_triplicane],
            departments=[self.dept_water, self.dept_waste]
        )

    def test_routing_flow(self):
        print("\n--- Testing Routing Flow and SLA Calculation (FR-4.3, FR-4.4) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            raw_text="Water contamination in Vyasarpadi",
            department_id=1,
            jurisdiction_id=1,
            priority_label="High",
            status="registered",
            created_at=datetime.utcnow()
        )
        self.db.add(complaint)
        
        # Route complaint (calculates SLA deadline, transitions status to assigned, sends notifications)
        asyncio.run(route_complaint(self.db, complaint))
        
        # Assertions
        self.assertEqual(complaint.status, "assigned")
        
        # Check SLA calculation (Water dept = 24 hours, not critical, so 24 hours from now)
        self.assertIsNotNone(complaint.sla_deadline)
        diff_hours = (complaint.sla_deadline - datetime.utcnow()).total_seconds() / 3600.0
        self.assertTrue(23 < diff_hours <= 24)
        
        # Check notifications created (Citizen, Officer Vyasarpadi, Supervisor Zone A)
        notifications = [n for n in self.db.added_items if isinstance(n, Notification)]
        self.assertEqual(len(notifications), 3)
        user_ids = {n.user_id for n in notifications}
        self.assertIn(self.citizen.id, user_ids)
        self.assertIn(self.officer_vyasarpadi.id, user_ids)
        self.assertIn(self.supervisor_zonea.id, user_ids)
        print("Routing Flow & Notification assertions: PASS")

    def test_critical_sla_shortening(self):
        print("\n--- Testing SLA deadline shortening for Critical priority (FR-4.4) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            raw_text="Urgent pipe blast",
            department_id=1,
            jurisdiction_id=1,
            priority_label="Critical",
            status="registered",
            created_at=datetime.utcnow()
        )
        self.db.add(complaint)
        
        # Route Critical complaint
        asyncio.run(route_complaint(self.db, complaint))
        
        # Expected: Water SLA is 24 hours, shortened by 0.5 multiplier -> 12 hours!
        diff_hours = (complaint.sla_deadline - datetime.utcnow()).total_seconds() / 3600.0
        self.assertTrue(11 < diff_hours <= 12)
        print("SLA Critical priority shortening: PASS")

    def test_invalid_state_transition_409(self):
        print("\n--- Testing Invalid Transition Prevention (FR-5.1) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            status="registered",
            created_at=datetime.utcnow()
        )
        # registered -> resolved is not allowed! Must go through assigned -> in_progress first.
        with self.assertRaises(Exception) as context:
            asyncio.run(transition_status(
                db=self.db,
                complaint=complaint,
                target_status="resolved",
                action="mark_resolved",
                actor=self.officer_vyasarpadi
            ))
        print(f"Exception message: {context.exception}")
        # Validate that it failed with a status code 409 or similar transition exception
        self.assertTrue("not allowed" in str(context.exception))
        print("State Machine 409 validation: PASS")

    def test_evidence_requirements_resolved_5_2(self):
        print("\n--- Testing Evidence / Closing Note Validation (FR-5.2) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            jurisdiction_id=1,
            status="in_progress",
            created_at=datetime.utcnow()
        )
        
        # Try to resolve without evidence photo -> Expected fail
        with self.assertRaises(Exception) as context_photo:
            asyncio.run(transition_status(
                db=self.db,
                complaint=complaint,
                target_status="resolved",
                action="mark_resolved",
                actor=self.officer_vyasarpadi,
                note="I have resolved the issue.",
                evidence_image_url=None
            ))
        self.assertTrue("requires uploading an evidence photograph" in str(context_photo.exception))
        
        # Try to resolve without note -> Expected fail
        with self.assertRaises(Exception) as context_note:
            asyncio.run(transition_status(
                db=self.db,
                complaint=complaint,
                target_status="resolved",
                action="mark_resolved",
                actor=self.officer_vyasarpadi,
                note=None,
                evidence_image_url="http://evidence.jpg"
            ))
        self.assertTrue("requires entering a descriptive closing note" in str(context_note.exception))
        
        # Provide both -> Success
        asyncio.run(transition_status(
            db=self.db,
            complaint=complaint,
            target_status="resolved",
            action="mark_resolved",
            actor=self.officer_vyasarpadi,
            note="Repaired the leaking pipe successfully.",
            evidence_image_url="http://supabase.com/evidence_123.jpg"
        ))
        
        self.assertEqual(complaint.status, "resolved")
        self.assertEqual(complaint.resolved_image_url, "http://supabase.com/evidence_123.jpg")
        print("Evidence & Closing Note checks: PASS")

    def test_wrong_jurisdiction_forbidden_403(self):
        print("\n--- Testing Geographic Jurisdiction Access Checks (officers from wrong ward) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            jurisdiction_id=1, # Assigned to Vyasarpadi (Ward 1)
            status="assigned",
            created_at=datetime.utcnow()
        )
        
        # Officer from Triplicane tries to start work on Vyasarpadi complaint -> Expected 403 Forbidden!
        with self.assertRaises(Exception) as context:
            asyncio.run(transition_status(
                db=self.db,
                complaint=complaint,
                target_status="in_progress",
                action="start_work",
                actor=self.officer_triplicane # Triplicane officer (jurisdiction_id = 8)
            ))
        self.assertTrue("outside your assigned office" in str(context.exception))
        print("Geographic Access Control 403 checks: PASS")

    def test_sla_breach_auto_escalation_5_4(self):
        print("\n--- Testing SLA Breach Auto-Escalation & Supervisor alerts (FR-5.4) ---")
        complaint = Complaint(
            id=uuid.uuid4(),
            citizen_id=self.citizen.id,
            jurisdiction_id=1,
            status="assigned",
            created_at=datetime.utcnow() - timedelta(days=5),
            sla_deadline=datetime.utcnow() - timedelta(hours=2) # Breached 2 hours ago
        )
        self.db.add(complaint)
        
        # Run SLA breach worker
        count = asyncio.run(check_sla_breaches(self.db))
        
        self.assertEqual(count, 1)
        self.assertEqual(complaint.status, "escalated")
        
        # Verify escalated audit event is logged on timeline (FR-5.5)
        events = [e for e in self.db.added_items if isinstance(e, ComplaintEvent)]
        actions = [e.action for e in events]
        self.assertIn("escalate", actions)
        
        # Check supervisor and officer were notified
        notifications = [n for n in self.db.added_items if isinstance(n, Notification)]
        user_ids = {n.user_id for n in notifications}
        self.assertIn(self.officer_vyasarpadi.id, user_ids)
        self.assertIn(self.supervisor_zonea.id, user_ids)
        print("SLA breach worker auto-escalation: PASS")

if __name__ == "__main__":
    unittest.main()
