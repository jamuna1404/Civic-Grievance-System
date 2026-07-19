"""Tests for the officer work surfaces: allotted list, jurisdiction track,
profile, preferences, and complaint status updates."""

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_session_token
from app.main import app
from app.routers import complaints as complaints_router
from app.routers import officer as officer_router
from tests.fake_supabase import FakeSupabase

OFFICER_ID = "off-100"
OTHER_OFFICER = "off-999"
BOUNDARY_ID = 11


def _complaint(cid, status_, *, assigned=OFFICER_ID, boundary=BOUNDARY_ID):
    return {
        "complaint_id": cid,
        "citizen_id": "cit-1",
        "citizen_name": "Priya",
        "citizen_phone": "+919876543210",
        "department_id": "GCC_ELECT",
        "department_name": "GCC Electrical",
        "description_text": "Light out",
        "input_mode": "TEXT",
        "status": status_,
        "address_label": "Anna Salai",
        "lat": 13.0,
        "lon": 80.0,
        "assigned_officer_id": assigned,
        "resolved_boundary_id": boundary,
        "image_urls": [],
        "created_at": "2026-07-10T10:00:00+00:00",
    }


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    db.table("officers").insert(
        {"officer_id": OFFICER_ID, "full_name": "R. Kumar",
         "phone": "+919000000001", "email": "k@x.in", "employee_id": "E1",
         "department_id": "GCC_ELECT", "designation_id": 1,
         "boundary_id": BOUNDARY_ID, "status": "ACTIVE"}
    )
    db.table("departments").insert(
        {"department_id": "GCC_ELECT", "department_name": "GCC Electrical"}
    )
    db.table("designations").insert(
        {"designation_id": 1, "department_id": "GCC_ELECT",
         "designation_name": "Junior Engineer", "level_name": "WARD",
         "rank_order": 1}
    )
    db.table("boundaries").insert(
        {"boundary_id": BOUNDARY_ID, "department_id": "GCC_ELECT",
         "level_name": "WARD", "boundary_name": "Ward 175"}
    )
    # Complaints in complaint_details (view stand-in).
    db.table("complaint_details").insert(_complaint("c-open", "IN_PROGRESS"))
    db.table("complaint_details").insert(_complaint("c-done", "RESOLVED"))
    db.table("complaint_details").insert(
        _complaint("c-other", "SUBMITTED", assigned=OTHER_OFFICER)
    )
    for mod in (officer_router, complaints_router):
        monkeypatch.setattr(mod, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


def _hdr(officer_id=OFFICER_ID):
    return {"Authorization": f"Bearer {create_session_token(officer_id)}"}


def test_allotted_active_excludes_resolved_and_others(fake_db, client):
    resp = client.get(f"/officer/{OFFICER_ID}/complaints", headers=_hdr())
    assert resp.status_code == 200
    ids = {c["complaint_id"] for c in resp.json()}
    assert ids == {"c-open"}  # resolved + other-officer excluded
    assert resp.json()[0]["citizen_phone"] == "+919876543210"


def test_allotted_all_includes_resolved(fake_db, client):
    resp = client.get(
        f"/officer/{OFFICER_ID}/complaints",
        params={"status": "all"},
        headers=_hdr(),
    )
    ids = {c["complaint_id"] for c in resp.json()}
    assert ids == {"c-open", "c-done"}


def test_allotted_forbidden_for_other_officer(fake_db, client):
    resp = client.get(
        f"/officer/{OFFICER_ID}/complaints", headers=_hdr(OTHER_OFFICER)
    )
    assert resp.status_code == 403


def test_track_scoped_to_boundary_any_status(fake_db, client):
    resp = client.get(f"/officer/{OFFICER_ID}/track", headers=_hdr())
    ids = {c["complaint_id"] for c in resp.json()}
    # All three share the boundary; track shows every status (incl. other's).
    assert ids == {"c-open", "c-done", "c-other"}


def test_profile_joins_reference_data(fake_db, client):
    resp = client.get(f"/officer/{OFFICER_ID}/profile", headers=_hdr())
    assert resp.status_code == 200
    body = resp.json()
    assert body["department_name"] == "GCC Electrical"
    assert body["designation_name"] == "Junior Engineer"
    assert body["jurisdiction_name"] == "Ward 175"
    assert body["theme_mode"] == "SYSTEM"


def test_officer_preferences_upsert(fake_db, client):
    resp = client.put(
        "/officer/preferences", json={"theme_mode": "DARK"}, headers=_hdr()
    )
    assert resp.status_code == 200
    prefs = fake_db.table("user_preferences").rows
    assert len(prefs) == 1
    assert prefs[0]["owner_type"] == "OFFICER"
    assert prefs[0]["theme_mode"] == "DARK"


# --- Status updates (on the real complaints table) ---------------------------


@pytest.fixture
def with_real_complaint(fake_db):
    fake_db.table("complaints").insert(
        {"complaint_id": "c-open", "assigned_officer_id": OFFICER_ID,
         "status": "SUBMITTED"}
    )
    return fake_db


def test_status_update_moves_forward(with_real_complaint, client):
    resp = client.put(
        "/complaints/c-open/status",
        json={"new_status": "ACKNOWLEDGED"},
        headers=_hdr(),
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ACKNOWLEDGED"
    row = with_real_complaint.table("complaints").rows[0]
    assert row["status"] == "ACKNOWLEDGED"


def test_status_update_attaches_remarks_to_latest_history(
    with_real_complaint, client
):
    # Simulate the trigger having logged a history row for this complaint.
    with_real_complaint.table("complaint_status_history").insert(
        {"complaint_id": "c-open", "status": "ACKNOWLEDGED", "remarks": None,
         "changed_at": "2026-07-11T10:00:00+00:00"}
    )
    resp = client.put(
        "/complaints/c-open/status",
        json={"new_status": "IN_PROGRESS", "remarks": "Crew dispatched"},
        headers=_hdr(),
    )
    assert resp.status_code == 200
    hist = with_real_complaint.table("complaint_status_history").rows[-1]
    assert hist["remarks"] == "Crew dispatched"


def test_status_update_forbidden_for_non_assignee(with_real_complaint, client):
    resp = client.put(
        "/complaints/c-open/status",
        json={"new_status": "RESOLVED"},
        headers=_hdr(OTHER_OFFICER),
    )
    assert resp.status_code == 403


def test_status_update_same_status_rejected(with_real_complaint, client):
    resp = client.put(
        "/complaints/c-open/status",
        json={"new_status": "SUBMITTED"},
        headers=_hdr(),
    )
    assert resp.status_code == 422  # SUBMITTED not an allowed target value


def test_status_update_unknown_complaint_404(fake_db, client):
    resp = client.put(
        "/complaints/nope/status",
        json={"new_status": "ACKNOWLEDGED"},
        headers=_hdr(),
    )
    assert resp.status_code == 404
