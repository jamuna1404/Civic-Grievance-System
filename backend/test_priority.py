import unittest
from datetime import datetime, timedelta
from app.services.priority_engine import compute_priority

class MockComplaint:
    def __init__(self, department_id, raw_text, transcribed_text, created_at, status="registered"):
        self.department_id = department_id
        self.raw_text = raw_text
        self.transcribed_text = transcribed_text
        self.created_at = created_at
        self.status = status

class TestPriorityEngine(unittest.TestCase):
    
    def test_routine_complaint(self):
        print("\nTesting Test Case 1: Routine street lamp issue (Expected: Low priority)...")
        # Department 5: Streetlight Maintenance (base = 10)
        # No danger keywords, no CV, no cluster, new complaint
        complaint = MockComplaint(
            department_id=5,
            raw_text="The street lamp in front of house 4 is slightly dim.",
            transcribed_text=None,
            created_at=datetime.utcnow()
        )
        score, label, breakdown = compute_priority(
            complaint=complaint,
            related_complaints_count=0,
            cv_severity_hint="minor",
            department_sla_hours=48
        )
        print(f"Score: {score}, Label: {label}, Breakdown: {breakdown}")
        
        self.assertEqual(label, "Low")
        self.assertEqual(score, 10)
        self.assertEqual(breakdown["base_weight"], 10)
        self.assertEqual(breakdown["keyword_boost"], 0)
        self.assertEqual(breakdown["cv_boost"], 0)
        self.assertEqual(breakdown["cluster_boost"], 0)
        self.assertEqual(breakdown["sla_breach_boost"], 0)

    def test_danger_keywords_complaint(self):
        print("\nTesting Test Case 2: Water leak with high-danger keywords (Expected: High priority)...")
        # Department 1: Water Supply & Sewerage (base = 20)
        # Danger keywords: "danger" (+20), "flooded" (+20) -> sum 40, capped at 35
        # CV: moderate (+10)
        complaint = MockComplaint(
            department_id=1,
            raw_text="Water main burst has flooded Egmore road. It is a huge danger.",
            transcribed_text=None,
            created_at=datetime.utcnow()
        )
        score, label, breakdown = compute_priority(
            complaint=complaint,
            related_complaints_count=0,
            cv_severity_hint="moderate",
            department_sla_hours=24
        )
        print(f"Score: {score}, Label: {label}, Breakdown: {breakdown}")
        
        # Expected: base (20) + keyword (35) + cv (10) = 65 -> High
        self.assertEqual(label, "High")
        self.assertEqual(score, 65)
        self.assertEqual(breakdown["base_weight"], 20)
        self.assertEqual(breakdown["keyword_boost"], 35) # capped
        self.assertEqual(breakdown["cv_boost"], 10)
        self.assertIn("danger (+20)", breakdown["matched_keywords"])

    def test_cluster_critical_complaint(self):
        print("\nTesting Test Case 3: Power grid fault with 3+ complaint cluster (Expected: Critical)...")
        # Department 4: Electricity Grid & Power (base = 25)
        # Danger keywords: "spark" (+25), "shock" (+25) -> sum 50, capped at 35
        # CV: severe (+25)
        # Cluster count: 3 other open complaints -> +15 cluster boost
        complaint = MockComplaint(
            department_id=4,
            raw_text="Electrical wire snapped and is sparking on the street! Risk of shock!",
            transcribed_text=None,
            created_at=datetime.utcnow()
        )
        score, label, breakdown = compute_priority(
            complaint=complaint,
            related_complaints_count=3,
            cv_severity_hint="severe",
            department_sla_hours=12
        )
        print(f"Score: {score}, Label: {label}, Breakdown: {breakdown}")
        
        # Expected: base (25) + keyword (35) + cv (25) + cluster (15) = 100 -> Critical
        self.assertEqual(label, "Critical")
        self.assertEqual(score, 100)
        self.assertEqual(breakdown["base_weight"], 25)
        self.assertEqual(breakdown["keyword_boost"], 35)
        self.assertEqual(breakdown["cv_boost"], 25)
        self.assertEqual(breakdown["cluster_boost"], 15)

    def test_overdue_complaint(self):
        print("\nTesting Test Case 4: Overdue complaint past SLA deadline (Expected: decay boost)...")
        # Department 3: Roads (base = 10)
        # Created 5 days ago (120 hours), SLA is 24 hours -> past SLA (+15 points decay boost)
        complaint = MockComplaint(
            department_id=3,
            raw_text="Pothole repair request.",
            transcribed_text=None,
            created_at=datetime.utcnow() - timedelta(days=5)
        )
        score, label, breakdown = compute_priority(
            complaint=complaint,
            related_complaints_count=0,
            cv_severity_hint=None,
            department_sla_hours=24
        )
        print(f"Score: {score}, Label: {label}, Breakdown: {breakdown}")
        
        # Expected: base (10) + SLA breach (15) = 25 -> Low
        self.assertEqual(score, 25)
        self.assertEqual(breakdown["sla_breach_boost"], 15)
        self.assertEqual(breakdown["at_risk"], True)

if __name__ == "__main__":
    unittest.main()
