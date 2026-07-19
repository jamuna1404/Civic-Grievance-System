"""Tests for officer enrollment, the cascade reference endpoints, and login."""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routers import auth as auth_router
from app.routers import departments as departments_router
from app.routers import officer as officer_router
from tests.fake_supabase import FakeSupabase

PHONE = "9876543210"
E164 = "+919876543210"


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    # Reference data for a GCC roads-style department.
    db.table("designations").insert(
        {"designation_id": 1, "department_id": "GCC_ENG_ROADS",
         "designation_name": "Junior Engineer", "level_name": "WARD",
         "rank_order": 1}
    )
    db.table("designations").insert(
        {"designation_id": 3, "department_id": "GCC_ENG_ROADS",
         "designation_name": "Assistant Executive Engineer",
         "level_name": "ZONE", "rank_order": 3}
    )
    db.table("boundary_levels").insert(
        {"department_id": "GCC_ENG_ROADS", "level_rank": 1, "level_name": "WARD",
         "display_label": "Ward"}
    )
    db.table("boundary_levels").insert(
        {"department_id": "GCC_ENG_ROADS", "level_rank": 2, "level_name": "ZONE",
         "display_label": "Zone"}
    )
    db.table("boundaries").insert(
        {"boundary_id": 10, "department_id": "GCC_ENG_ROADS",
         "level_name": "ZONE", "boundary_name": "Adyar",
         "parent_boundary_id": None}
    )
    db.table("boundaries").insert(
        {"boundary_id": 11, "department_id": "GCC_ENG_ROADS",
         "level_name": "WARD", "boundary_name": "Ward 175",
         "parent_boundary_id": 10}
    )
    for mod in (auth_router, departments_router, officer_router):
        monkeypatch.setattr(mod, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


def _enroll_body(**overrides):
    base = {
        "full_name": "R. Kumar",
        "phone_number": PHONE,
        "department_id": "GCC_ENG_ROADS",
        "designation_id": 1,
        "boundary_id": 11,
        "employee_id": "EMP-42",
        "email": "kumar@example.com",
    }
    base.update(overrides)
    return base


# --- Reference endpoints -----------------------------------------------------


def test_designations_ordered_lowest_rank_first(fake_db, client):
    resp = client.get("/departments/GCC_ENG_ROADS/designations")
    assert resp.status_code == 200
    ranks = [d["rank_order"] for d in resp.json()]
    assert ranks == sorted(ranks)
    assert resp.json()[0]["designation_name"] == "Junior Engineer"


def test_boundaries_filtered_by_parent(fake_db, client):
    # Top level (Zone): no parent filter → all zones.
    zones = client.get(
        "/departments/GCC_ENG_ROADS/boundaries", params={"level_name": "ZONE"}
    )
    assert [b["boundary_name"] for b in zones.json()] == ["Adyar"]

    # Wards under zone 10.
    wards = client.get(
        "/departments/GCC_ENG_ROADS/boundaries",
        params={"level_name": "WARD", "parent_id": 10},
    )
    assert [b["boundary_id"] for b in wards.json()] == [11]

    # Wards under a different (nonexistent) parent → none.
    empty = client.get(
        "/departments/GCC_ENG_ROADS/boundaries",
        params={"level_name": "WARD", "parent_id": 999},
    )
    assert empty.json() == []


# --- Enrollment --------------------------------------------------------------


def test_enroll_creates_pending_officer(fake_db, client):
    resp = client.post("/officer/enroll", json=_enroll_body())
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "PENDING_VERIFICATION"
    assert body["full_name"] == "R. Kumar"
    assert body["session_token"]

    officer = fake_db.table("officers").rows[0]
    assert officer["phone"] == E164
    assert officer["employee_id"] == "EMP-42"
    assert officer["boundary_id"] == 11
    assert officer["status"] == "PENDING_VERIFICATION"


def test_enroll_duplicate_position_returns_409(fake_db, client):
    fake_db.table("officers").insert(
        {"officer_id": "off-1", "full_name": "Existing",
         "phone": "+919000000000", "department_id": "GCC_ENG_ROADS",
         "designation_id": 1, "boundary_id": 11, "status": "ACTIVE"}
    )
    resp = client.post("/officer/enroll", json=_enroll_body())
    assert resp.status_code == 409
    assert "already filled" in resp.json()["detail"]


def test_enroll_suspended_seat_can_be_refilled(fake_db, client):
    fake_db.table("officers").insert(
        {"officer_id": "off-1", "full_name": "Old", "phone": "+919000000000",
         "department_id": "GCC_ENG_ROADS", "designation_id": 1,
         "boundary_id": 11, "status": "SUSPENDED"}
    )
    resp = client.post("/officer/enroll", json=_enroll_body())
    assert resp.status_code == 200


def test_enroll_invalid_phone_400(fake_db, client):
    resp = client.post("/officer/enroll", json=_enroll_body(phone_number="123"))
    assert resp.status_code == 400


# --- Officer login -----------------------------------------------------------


def test_officer_login_new_user(fake_db, client):
    client.post("/auth/officer/send-otp", json={"phone_number": PHONE})
    resp = client.post(
        "/auth/officer/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    assert resp.status_code == 200
    assert resp.json()["new_user"] is True


def test_officer_login_existing_returns_token_and_status(fake_db, client):
    fake_db.table("officers").insert(
        {"officer_id": "off-9", "full_name": "R. Kumar", "phone": E164,
         "department_id": "GCC_ENG_ROADS", "designation_id": 1,
         "boundary_id": 11, "status": "ACTIVE"}
    )
    client.post("/auth/officer/send-otp", json={"phone_number": PHONE})
    resp = client.post(
        "/auth/officer/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    body = resp.json()
    assert body["new_user"] is False
    assert body["full_name"] == "R. Kumar"
    assert body["status"] == "ACTIVE"
    assert body["session_token"]
