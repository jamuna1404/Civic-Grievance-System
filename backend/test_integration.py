import unittest
import uuid
import asyncio
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock
from typing import List, Optional

from app.models.all_models import Base, Complaint, User, Department, Jurisdiction, ComplaintEvent, Notification
from app.services.workflow_engine import transition_status
from app.services.routing_engine import route_complaint
from app.api.complaints import process_complaint_pipeline

# Re-use our robust MockDbSession structure supporting async context manager
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
        
    async def __aenter__(self):
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass

    def add(self, item):
        self.added_items.append(item)
        
    def add_all(self, items):
        self.added_items.extend(items)
        
    async def commit(self):
        self.committed = True
        
    async def refresh(self, item):
        pass
        
    async def execute(self, stmt):
        stmt_str = str(stmt).lower()
        print(f"DEBUG SQL QUERY: {stmt_str}")
        params = stmt.compile().params

        param_values = list(params.values())
        
        # 1. Fetching Users
        if "from users" in stmt_str or "users" in stmt_str:
            if "officer" in param_values:
                juris_id = next((val for val in param_values if isinstance(val, int)), None)
                if juris_id:
                    matched = [u for u in self.users if u.role == "officer" and u.jurisdiction_id == juris_id]
                else:
                    matched = [u for u in self.users if u.role == "officer"]
                return MockResult(matched)
            elif "supervisor" in param_values:
                return MockResult([self.users[2]]) # supervisor
            return MockResult(self.users)
            
        # 2. Fetching Jurisdictions
        elif "from jurisdictions" in stmt_str or "jurisdictions" in stmt_str:
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

        # 4. Fetching Complaint Coordinates
        elif "st_x" in stmt_str or "st_y" in stmt_str:
            return MockResult([(80.245, 13.091)])

        # 5. Fetching Complaint (mocked return for process_complaint_pipeline)
        elif "from complaints" in stmt_str or "complaints" in stmt_str:

            try:
                complaint = next((c for c in self.added_items if c.__class__.__name__ == 'Complaint'), None)
            except Exception as ex:
                print(f"Error checking class name: {ex}")
                complaint = None
            # Find duplicate complaints within ~100m (empty list for integration simplification)
            if "st_dwithin" in stmt_str:
                return MockResult([])
            return MockResult([complaint] if complaint else [])

            
        return MockResult([])

class TestIntegrationLifecycle(unittest.TestCase):
    
    def setUp(self):
        # 1. Seed DB structures
        self.dept_water = Department(id=1, name="Water Supply & Sewerage", category="Water", sla_hours=24)
        self.juris_vyasarpadi = Jurisdiction(
            id=1, zone="Zone A", ward="Ward 1", area_name="Vyasarpadi",
            department_id=1, office_name="Ward 1 Water Office", officer_contact="+919876543210"
        )
        self.officer = User(
            id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
            name="Officer Vyasarpadi", role="officer", jurisdiction_id=1
        )
        self.supervisor = User(
            id=uuid.UUID("44444444-4444-4444-4444-444444444444"),
            name="Supervisor Zone A", role="supervisor", jurisdiction_id=1
        )
        self.citizen = User(
            id=uuid.UUID("99999999-9999-9999-9999-999999999999"),
            name="Citizen Jan", role="citizen", jurisdiction_id=None
        )
        
        self.db = MockDbSession(
            users=[self.officer, self.supervisor, self.citizen],
            jurisdictions=[self.juris_vyasarpadi],
            departments=[self.dept_water]
        )

    # Mock Whisper transcribing, CLIP image classifying, and GIS geocoding/nominatim APIs
    @patch("app.api.complaints.transcribe")
    @patch("app.api.complaints.analyze_image")
    @patch("app.api.complaints.resolve_gis_jurisdiction")
    @patch("app.api.complaints.classify_complaint_text")
    @patch("app.api.complaints.compute_priority")
    def test_end_to_end_lifecycle(self, *args):
        # Print actual args to see their order
        for idx, arg in enumerate(args):
            print(f"ARG {idx}: name={getattr(arg, '_mock_name', 'None')}, type={type(arg)}")
            
        # Distribute mocks based on the prints
        mock_priority = args[0]      # Dec 5 (compute_priority)
        mock_classify_nlp = args[1]  # Dec 4 (classify_complaint_text)
        mock_gis = args[2]           # Dec 3 (resolve_gis_jurisdiction)
        mock_cv = args[3]            # Dec 2 (analyze_image)
        mock_transcribe = args[4]    # Dec 1 (transcribe)

        print(f"DEBUG mock_transcribe: {mock_transcribe._mock_name}")
        print(f"DEBUG mock_cv: {mock_cv._mock_name}")
        print(f"DEBUG mock_gis: {mock_gis._mock_name}")
        print(f"DEBUG mock_classify_nlp: {mock_classify_nlp._mock_name}")
        print(f"DEBUG mock_priority: {mock_priority._mock_name}")

        # Mock Pipeline inputs (sync)
        mock_transcribe.return_value = {
            "text": "Water leakage reported in Vyasarpadi",
            "detected_language": "English",
            "confidence": 0.98
        }
        mock_cv.return_value = {"label": "pipe leak", "confidence": 0.90, "severity_hint": "severe", "is_conflict": False}
        mock_priority.return_value = (85, "Critical", {"base_weight": 20, "keyword_boost": 35, "cv_boost": 25, "cluster_boost": 0, "sla_decay": 5})

        # Mock Pipeline inputs (async side-effects)
        async def mock_nlp_func(*args_nlp, **kwargs_nlp):
            return {"department_id": 1, "subcategory": "leak", "confidence": 0.85, "status": "assigned"}
        mock_classify_nlp.side_effect = mock_nlp_func

        async def mock_gis_func(*args_gis, **kwargs_gis):
            return {
                "jurisdiction_id": 1,
                "gis_resolution_method": "GPS lookup",
                "jurisdiction_uncertain": False,
                "resolved_lat": 13.091,
                "resolved_lng": 80.245
            }
        mock_gis.side_effect = mock_gis_func

        complaint_id = uuid.uuid4()
        complaint = Complaint(
            id=complaint_id,
            citizen_id=self.citizen.id,
            raw_text="Water pipeline leaking",
            image_url="http://supabase.com/pic.jpg",
            audio_url="http://supabase.com/voice.m4a",
            status="registered",
            created_at=datetime.utcnow()
        )
        self.db.add(complaint)
        
        # We mock SessionLocal to return our mock DB session when process_complaint_pipeline calls it!
        with patch("app.api.complaints.SessionLocal", return_value=self.db):
            with patch("requests.get") as mock_req:
                mock_req.return_value.status_code = 200
                mock_req.return_value.content = b"fake audio/image data"
                
                # 1. RUN PIPELINE (Audio -> NLP -> CV -> GIS -> Priority -> Routing)
                asyncio.run(process_complaint_pipeline(complaint_id))
        
        # Verify status progressed to "assigned" automatically
        self.assertEqual(complaint.status, "assigned")
        self.assertEqual(complaint.priority_label, "Critical")
        self.assertEqual(complaint.priority_score, 85)
        self.assertEqual(complaint.jurisdiction_id, 1)
        self.assertEqual(complaint.department_id, 1)
        
        # 2. OFFICER ACTION: start_work (assigned -> in_progress)
        asyncio.run(transition_status(
            db=self.db,
            complaint=complaint,
            target_status="in_progress",
            action="start_work",
            actor=self.officer
        ))
        self.assertEqual(complaint.status, "in_progress")
        
        # 3. OFFICER ACTION: mark_resolved (in_progress -> resolved)
        asyncio.run(transition_status(
            db=self.db,
            complaint=complaint,
            target_status="resolved",
            action="mark_resolved",
            actor=self.officer,
            note="Pipe leakage successfully welded and repaired.",
            evidence_image_url="http://supabase.com/evidence_photo.jpg"
        ))
        self.assertEqual(complaint.status, "resolved")
        
        # 4. SUPERVISOR ACTION: approve (resolved -> closed)
        asyncio.run(transition_status(
            db=self.db,
            complaint=complaint,
            target_status="closed",
            action="approve",
            actor=self.supervisor,
            note="Resolution verified and approved."
        ))
        self.assertEqual(complaint.status, "closed")
        
        # 5. ASSERT AUDIT TRAIL TIMELINE (events logged in order)
        events = [e for e in self.db.added_items if isinstance(e, ComplaintEvent)]
        # Expected actions logged during FSM changes
        logged_actions = [e.action for e in events]
        print(f"Logged FSM Actions: {logged_actions}")
        
        # FSM updates should include start_work, mark_resolved, and approve
        self.assertIn("start_work", logged_actions)
        self.assertIn("mark_resolved", logged_actions)
        self.assertIn("approve", logged_actions)
        
        print("End-to-end integration lifecycle test: PASS")

if __name__ == "__main__":
    unittest.main()
