import unittest
import uuid
import asyncio
from unittest.mock import patch, AsyncMock, MagicMock
from app.models.all_models import Complaint, Department, Jurisdiction, ComplaintEvent
from app.services.narrative_generator import generate_narrative_summary

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
    def __init__(self, departments, jurisdictions, events):
        self.departments = departments
        self.jurisdictions = jurisdictions
        self.events = events
        
    async def execute(self, stmt):
        stmt_str = str(stmt).lower()
        if "from departments" in stmt_str or "departments" in stmt_str:
            params = stmt.compile().params
            val_id = next((v for v in params.values() if isinstance(v, int)), None)
            if val_id:
                matched = [d for d in self.departments if d.id == val_id]
                return MockResult(matched)
            return MockResult(self.departments)
            
        elif "from jurisdictions" in stmt_str or "jurisdictions" in stmt_str:
            params = stmt.compile().params
            val_id = next((v for v in params.values() if isinstance(v, int)), None)
            if val_id:
                matched = [j for j in self.jurisdictions if j.id == val_id]
                return MockResult(matched)
            return MockResult(self.jurisdictions)
            
        elif "from complaint_events" in stmt_str or "complaint_events" in stmt_str:
            return MockResult(self.events)
            
        return MockResult([])

class TestNarrativeGenerator(unittest.TestCase):
    
    def setUp(self):
        self.complaint_id = uuid.uuid4()
        self.complaint = Complaint(
            id=self.complaint_id,
            status="assigned",
            subcategory="pipe leak",
            priority_label="High",
            department_id=1,
            jurisdiction_id=1
        )
        
        self.dept_water = Department(id=1, name="Water Supply & Sewerage")
        self.dept_waste = Department(id=2, name="Solid Waste Management")
        
        self.juris_vyasarpadi = Jurisdiction(
            id=1, zone="Zone A", ward="Ward 1", office_name="Ward 1 Water Office"
        )
        self.juris_perambur = Jurisdiction(
            id=2, zone="Zone A", ward="Ward 2", office_name="Ward 2 Sanitation Office"
        )
        
        self.events = [
            ComplaintEvent(action="registered"),
            ComplaintEvent(action="assigned")
        ]
        
        self.db = MockDbSession(
            departments=[self.dept_water, self.dept_waste],
            jurisdictions=[self.juris_vyasarpadi, self.juris_perambur],
            events=self.events
        )
        
        # Expected template fallback
        self.expected_fallback = (
            f"Complaint {self.complaint_id} regarding pipe leak is currently assigned with High priority. "
            f"It is routed to the Ward 1 Water Office (Ward 1, Zone A) under the Water Supply & Sewerage department."
        )

    @patch("httpx.AsyncClient.post")
    def test_narrative_success(self, mock_post):
        print("\n--- Testing Narrative Summary Generation Success Flow ---")
        
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = MagicMock(return_value={
            "response": "A pipe leak has been reported. The status is assigned and the complaint has been sent to Ward 1."
        })
        mock_post.return_value = mock_response
        
        summary = asyncio.run(generate_narrative_summary(self.db, self.complaint))
        
        # Should return the LLM response itself because it is valid and passes guardrails
        self.assertEqual(summary, "A pipe leak has been reported. The status is assigned and the complaint has been sent to Ward 1.")
        print("Success flow assertions: PASS")

    @patch("httpx.AsyncClient.post")
    def test_guardrail_hallucinated_department(self, mock_post):
        print("\n--- Testing Guardrail: Rejection of Hallucinated Department ---")
        
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = MagicMock(return_value={
            "response": "This is a pipe leak assigned to Solid Waste Management in Ward 1."
        })
        mock_post.return_value = mock_response
        
        summary = asyncio.run(generate_narrative_summary(self.db, self.complaint))
        
        self.assertEqual(summary, self.expected_fallback)
        print("Guardrail hallucinated department fallback: PASS")

    @patch("httpx.AsyncClient.post")
    def test_guardrail_hallucinated_ward(self, mock_post):
        print("\n--- Testing Guardrail: Rejection of Hallucinated Ward ---")
        
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = MagicMock(return_value={
            "response": "A water issue is currently assigned to Ward 2."
        })
        mock_post.return_value = mock_response
        
        summary = asyncio.run(generate_narrative_summary(self.db, self.complaint))
        
        self.assertEqual(summary, self.expected_fallback)
        print("Guardrail hallucinated ward fallback: PASS")

    @patch("httpx.AsyncClient.post")
    def test_guardrail_hallucinated_status(self, mock_post):
        print("\n--- Testing Guardrail: Rejection of Hallucinated Status ---")
        
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = MagicMock(return_value={
            "response": "The pipe leak issue has been resolved in Ward 1."
        })
        mock_post.return_value = mock_response
        
        summary = asyncio.run(generate_narrative_summary(self.db, self.complaint))
        
        self.assertEqual(summary, self.expected_fallback)
        print("Guardrail hallucinated status fallback: PASS")

if __name__ == "__main__":
    unittest.main()
