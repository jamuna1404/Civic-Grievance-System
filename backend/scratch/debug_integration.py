import asyncio
import uuid
from unittest.mock import patch
from app.api.complaints import process_complaint_pipeline
from test_integration import MockDbSession, TestIntegrationLifecycle

async def main():
    test = TestIntegrationLifecycle()
    test.setUp()
    
    # Mock sync functions
    mock_transcribe = MagicMock()
    mock_transcribe.return_value = {
        "text": "Water leakage reported in Vyasarpadi",
        "detected_language": "English",
        "confidence": 0.98
    }
    
    mock_cv = MagicMock()
    mock_cv.return_value = {
        "label": "pipe leak",
        "confidence": 0.90,
        "severity_hint": "severe",
        "is_conflict": False
    }
    
    mock_priority = MagicMock()
    mock_priority.return_value = (85, "Critical", {"base_weight": 20, "keyword_boost": 35, "cv_boost": 25, "cluster_boost": 0, "sla_decay": 5})

    # Mock async functions
    async def mock_nlp_func(*args, **kwargs):
        return {"department_id": 1, "subcategory": "leak", "confidence": 0.85, "status": "assigned"}

    async def mock_gis_func(*args, **kwargs):
        return {
            "jurisdiction_id": 1,
            "gis_resolution_method": "GPS lookup",
            "jurisdiction_uncertain": False,
            "resolved_lat": 13.091,
            "resolved_lng": 80.245
        }

    # Apply patches and print full traceback on failure
    with patch("app.api.complaints.transcribe", mock_transcribe):
        with patch("app.api.complaints.analyze_image", mock_cv):
            with patch("app.api.complaints.resolve_gis_jurisdiction", mock_gis_func):
                with patch("app.api.complaints.classify_complaint_text", mock_nlp_func):
                    with patch("app.api.complaints.compute_priority", mock_priority):
                        with patch("app.api.complaints.SessionLocal", return_value=test.db):
                            with patch("requests.get") as mock_req:
                                mock_req.return_value.status_code = 200
                                mock_req.return_value.content = b"fake data"
                                
                                complaint_id = uuid.uuid4()
                                from app.models.all_models import Complaint
                                from datetime import datetime
                                complaint = Complaint(
                                    id=complaint_id,
                                    citizen_id=test.citizen.id,
                                    raw_text="Water pipeline leaking",
                                    image_url="http://supabase.com/pic.jpg",
                                    audio_url="http://supabase.com/voice.m4a",
                                    status="registered",
                                    created_at=datetime.utcnow()
                                )
                                test.db.add(complaint)
                                
                                print("Running pipeline...")
                                try:
                                    # We don't catch exceptions inside process_complaint_pipeline unless they are caught inside the pipeline itself.
                                    # Wait, process_complaint_pipeline catches exceptions itself!
                                    # Let's inspect what print statements are logged
                                    import logging
                                    logging.basicConfig(level=logging.INFO)
                                    await process_complaint_pipeline(complaint_id)
                                    print("Pipeline execution completed.")
                                    print(f"Complaint status: {complaint.status}")
                                    print(f"Complaint jurisdiction: {complaint.jurisdiction_id}")
                                except Exception as ex:
                                    import traceback
                                    traceback.print_exc()

if __name__ == "__main__":
    from unittest.mock import MagicMock
    asyncio.run(main())
