"""Tests for the "Manage Team" surfaces: manages_team detection, the
team-complaints list, and the review (approve/send-back) decision."""

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_session_token
from app.main import app
from app.routers import auth as auth_router
from app.routers import complaints as complaints_router
from app.routers import officer as officer_router
from tests.fake_supabase import FakeSupabase

SUPERVISOR_ID = "off-super"
JUNIOR_ID = "off-junior"
OUTSIDER_ID = "off-outsider"
WARD_BOUNDARY = 11
ZONE_BOUNDARY = 10


def _complaint(cid, status_, *, assigned=JUNIOR_ID, boundary=WARD_BOUNDARY):
    return {
        "complaint_id": cid,
        "assigned_officer_id": assigned,
        "resolved_boundary_id": boundary,
        "status": status_,
        "department_id": "GCC_ELECT",
        "description_text": "Light out",
        "input_mode": "TEXT",
        "location": "SRID=4326;POINT(80.0 13.0)",
    }


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    db.table("departments").insert(
        {"department_id": "GCC_ELECT", "department_name": "GCC Electrical"}
    )
    db.table("designations").insert(
        {"designation_id": 1, "department_id": "GCC_ELECT",
         "designation_name": "Junior Engineer", "level_name": "WARD",
         "rank_order": 1}
    )
    db.table("designations").insert(
        {"designation_id": 2, "department_id": "GCC_ELECT",
         "designation_name": "Assistant Engineer", "level_name": "ZONE",
         "rank_order": 2}
    )
    db.table("boundaries").insert(
        {"boundary_id": ZONE_BOUNDARY, "department_id": "GCC_ELECT",
         "level_name": "ZONE", "boundary_name": "Adyar",
         "parent_boundary_id": None}
    )
    db.table("boundaries").insert(
        {"boundary_id": WARD_BOUNDARY, "department_id": "GCC_ELECT",
         "level_name": "WARD", "boundary_name": "Ward 175",
         "parent_boundary_id": ZONE_BOUNDARY}
    )
    db.table("officers").insert(
        {"officer_id": SUPERVISOR_ID, "full_name": "S. Devi", "phone": "+919000000002",
         "department_id": "GCC_ELECT", "designation_id": 2,
         "boundary_id": ZONE_BOUNDARY, "status": "ACTIVE"}
    )
    db.table("officers").insert(
        {"officer_id": JUNIOR_ID, "full_name": "R. Kumar", "phone": "+919000000001",
         "department_id": "GCC_ELECT", "designation_id": 1,
         "boundary_id": WARD_BOUNDARY, "status": "ACTIVE"}
    )
    db.table("officers").insert(
        {"officer_id": OUTSIDER_ID, "full_name": "K. Raja", "phone": "+919000000003",
         "department_id": "GCC_ELECT", "designation_id": 1,
         "boundary_id": WARD_BOUNDARY, "status": "ACTIVE"}
    )
    for mod in (auth_router, officer_router, complaints_router):
        monkeypatch.setattr(mod, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


def _hdr(officer_id):
    return {"Authorization": f"Bearer {create_session_token(officer_id)}"}


def test_manages_team_true_for_supervisor(fake_db):
    from app.routers.officer import _load_officer, officer_manages_team

    officer = _load_officer(fake_db, SUPERVISOR_ID)
    assert officer_manages_team(fake_db, officer) is True


def test_manages_team_false_for_junior(fake_db):
    from app.routers.officer import _load_officer, officer_manages_team

    officer = _load_officer(fake_db, JUNIOR_ID)
    assert officer_manages_team(fake_db, officer) is False


def test_login_response_carries_manages_team(fake_db, client):
    fake_db.table("otp_verifications").insert(
        {"phone_number": "+919000000002", "otp_code": "123456",
         "is_used": False, "expires_at": "2099-01-01T00:00:00+00:00"}
    )
    resp = client.post(
        "/auth/officer/verify-otp",
        json={"phone_number": "9000000002", "otp_code": "123456"},
    )
    assert resp.status_code == 200
    assert resp.json()["manages_team"] is True


def test_team_complaints_scoped_to_subordinates(fake_db, client):
    fake_db.set_rpc_result(
        "team_complaints_for_officer",
        [
            {
                **_complaint("c-req", "RESOLUTION_REQUESTED"),
                "department_name": "GCC Electrical", "address_label": None,
                "lat": 13.0, "lon": 80.0, "image_urls": [],
                "created_at": "2026-07-10T10:00:00+00:00",
                "officer_name": "R. Kumar", "officer_designation_name": "Junior Engineer",
            },
            {
                **_complaint("c-progress", "IN_PROGRESS"),
                "department_name": "GCC Electrical", "address_label": None,
                "lat": 13.0, "lon": 80.0, "image_urls": [],
                "created_at": "2026-07-09T10:00:00+00:00",
                "officer_name": "R. Kumar", "officer_designation_name": "Junior Engineer",
            },
        ],
    )
    resp = client.get(
        f"/officer/{SUPERVISOR_ID}/team-complaints", headers=_hdr(SUPERVISOR_ID)
    )
    assert resp.status_code == 200
    body = resp.json()
    assert [c["complaint_id"] for c in body] == ["c-req", "c-progress"]
    assert body[0]["officer_name"] == "R. Kumar"
    assert "citizen_name" not in body[0]


def test_team_complaints_forbidden_for_other_officer(fake_db, client):
    resp = client.get(
        f"/officer/{SUPERVISOR_ID}/team-complaints", headers=_hdr(JUNIOR_ID)
    )
    assert resp.status_code == 403


def test_team_boundary_scope_returns_descendants(fake_db, client):
    fake_db.set_rpc_result(
        "get_boundary_descendants",
        [{"boundary_id": ZONE_BOUNDARY}, {"boundary_id": WARD_BOUNDARY}],
    )
    resp = client.get(
        f"/officer/{SUPERVISOR_ID}/team-boundary-scope", headers=_hdr(SUPERVISOR_ID)
    )
    assert resp.status_code == 200
    assert set(resp.json()) == {ZONE_BOUNDARY, WARD_BOUNDARY}


def test_team_boundary_scope_forbidden_for_other_officer(fake_db, client):
    resp = client.get(
        f"/officer/{SUPERVISOR_ID}/team-boundary-scope", headers=_hdr(JUNIOR_ID)
    )
    assert resp.status_code == 403


@pytest.fixture
def with_resolution_requested(fake_db):
    fake_db.table("complaints").insert(_complaint("c-req", "RESOLUTION_REQUESTED"))
    fake_db.set_rpc_result(
        "get_boundary_descendants", [{"boundary_id": ZONE_BOUNDARY}, {"boundary_id": WARD_BOUNDARY}]
    )
    return fake_db


def test_review_approve_resolves(with_resolution_requested, client):
    resp = client.put(
        "/officer/complaints/c-req/review",
        json={"decision": "APPROVE"},
        headers=_hdr(SUPERVISOR_ID),
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "RESOLVED"
    row = with_resolution_requested.table("complaints").rows[0]
    assert row["status"] == "RESOLVED"


def test_review_send_back_requires_remarks(with_resolution_requested, client):
    resp = client.put(
        "/officer/complaints/c-req/review",
        json={"decision": "SEND_BACK"},
        headers=_hdr(SUPERVISOR_ID),
    )
    assert resp.status_code == 400


def test_review_send_back_with_remarks_moves_to_in_progress(
    with_resolution_requested, client
):
    with_resolution_requested.table("complaint_status_history").insert(
        {"complaint_id": "c-req", "status": "RESOLUTION_REQUESTED", "remarks": None,
         "changed_at": "2026-07-11T10:00:00+00:00"}
    )
    resp = client.put(
        "/officer/complaints/c-req/review",
        json={"decision": "SEND_BACK", "remarks": "Missing before/after photo"},
        headers=_hdr(SUPERVISOR_ID),
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "IN_PROGRESS"
    hist = with_resolution_requested.table("complaint_status_history").rows[-1]
    assert hist["remarks"] == "Missing before/after photo"


def test_review_forbidden_for_non_outranking_officer(
    with_resolution_requested, client
):
    # OUTSIDER_ID is rank 1, same as the assignee — can't review a peer.
    resp = client.put(
        "/officer/complaints/c-req/review",
        json={"decision": "APPROVE"},
        headers=_hdr(OUTSIDER_ID),
    )
    assert resp.status_code == 403


def test_review_rejects_non_resolution_requested_complaint(fake_db, client):
    fake_db.table("complaints").insert(_complaint("c-open", "IN_PROGRESS"))
    resp = client.put(
        "/officer/complaints/c-open/review",
        json={"decision": "APPROVE"},
        headers=_hdr(SUPERVISOR_ID),
    )
    assert resp.status_code == 400
