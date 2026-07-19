"""Tests for the citizen 'Track Complaints' list + history endpoints."""

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_session_token
from app.main import app
from app.routers import citizen as citizen_router
from app.routers import complaints as complaints_router
from tests.fake_supabase import FakeSupabase

CITIZEN_ID = "44444444-4444-4444-4444-444444444444"
OTHER_ID = "55555555-5555-5555-5555-555555555555"
COMPLAINT_ID = "aaaaaaaa-0000-0000-0000-000000000001"


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    # complaint_details is a view; the fake just treats it as a table.
    db.table("complaint_details").insert(
        {
            "complaint_id": COMPLAINT_ID,
            "citizen_id": CITIZEN_ID,
            "department_id": "GCC_ELECT",
            "department_name": "GCC Electrical",
            "description_text": "Streetlight out",
            "input_mode": "VOICE",
            "status": "IN_PROGRESS",
            "address_label": "Anna Salai",
            "lat": 13.0827,
            "lon": 80.2707,
            "assigned_officer_id": None,
            "resolved_boundary_id": None,
            "image_urls": ["https://x/a.jpg"],
            "created_at": "2026-07-10T10:00:00+00:00",
        }
    )
    monkeypatch.setattr(citizen_router, "get_supabase", lambda: db)
    monkeypatch.setattr(complaints_router, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


def _headers(citizen_id=CITIZEN_ID):
    return {"Authorization": f"Bearer {create_session_token(citizen_id)}"}


def test_list_requires_auth(fake_db, client):
    assert client.get(f"/citizen/{CITIZEN_ID}/complaints").status_code == 401


def test_list_returns_own_complaints(fake_db, client):
    resp = client.get(f"/citizen/{CITIZEN_ID}/complaints", headers=_headers())
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    item = body[0]
    assert item["complaint_id"] == COMPLAINT_ID
    assert item["department_name"] == "GCC Electrical"
    assert item["status"] == "IN_PROGRESS"
    assert item["lat"] == 13.0827
    assert item["image_urls"] == ["https://x/a.jpg"]


def test_cannot_list_other_citizens_complaints(fake_db, client):
    # Authenticated as OTHER_ID but requesting CITIZEN_ID's list.
    resp = client.get(
        f"/citizen/{CITIZEN_ID}/complaints", headers=_headers(OTHER_ID)
    )
    assert resp.status_code == 403


def test_history_ownership_and_order(fake_db, client):
    fake_db.table("complaint_history_view").insert(
        {
            "complaint_id": COMPLAINT_ID,
            "status": "SUBMITTED",
            "remarks": None,
            "officer_name": None,
            "changed_at": "2026-07-10T10:00:00+00:00",
        }
    )
    fake_db.table("complaint_history_view").insert(
        {
            "complaint_id": COMPLAINT_ID,
            "status": "IN_PROGRESS",
            "remarks": "Crew dispatched",
            "officer_name": "Officer Kumar",
            "changed_at": "2026-07-12T09:00:00+00:00",
        }
    )

    resp = client.get(
        f"/complaints/{COMPLAINT_ID}/history", headers=_headers()
    )
    assert resp.status_code == 200
    body = resp.json()
    assert [e["status"] for e in body] == ["SUBMITTED", "IN_PROGRESS"]
    assert body[1]["officer_name"] == "Officer Kumar"
    assert body[1]["remarks"] == "Crew dispatched"


def test_history_forbidden_for_non_owner(fake_db, client):
    resp = client.get(
        f"/complaints/{COMPLAINT_ID}/history", headers=_headers(OTHER_ID)
    )
    assert resp.status_code == 403


def test_history_unknown_complaint_404(fake_db, client):
    resp = client.get("/complaints/does-not-exist/history", headers=_headers())
    assert resp.status_code == 404
