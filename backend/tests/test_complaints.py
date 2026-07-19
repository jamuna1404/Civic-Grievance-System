"""Tests for complaint registration, including officer routing via RPC."""

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_session_token
from app.main import app
from app.routers import complaints as complaints_router
from tests.fake_supabase import FakeSupabase

CITIZEN_ID = "22222222-2222-2222-2222-222222222222"
OFFICER_ID = "33333333-3333-3333-3333-333333333333"


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    db.table("departments").insert(
        {"department_id": "GCC_ELECT", "department_name": "GCC Electrical"}
    )
    monkeypatch.setattr(complaints_router, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def auth_headers():
    return {"Authorization": f"Bearer {create_session_token(CITIZEN_ID)}"}


def _payload(**overrides):
    base = {
        "department_id": "GCC_ELECT",
        "description_text": "Streetlight out on Anna Salai",
        "input_mode": "VOICE",
        "image_urls": ["https://x/img1.jpg", "https://x/img2.jpg"],
        "lat": 13.0827,
        "lon": 80.2707,
        "address_label": "Anna Salai, Chennai",
    }
    base.update(overrides)
    return base


def test_register_requires_auth(fake_db, client):
    assert client.post("/complaints/register", json=_payload()).status_code == 401


def test_register_routes_to_officer_and_stores_everything(
    fake_db, client, auth_headers
):
    fake_db.set_rpc_result(
        "resolve_officer_for_complaint",
        [{"officer_id": OFFICER_ID, "boundary_id": 42, "designation_id": 1}],
    )

    resp = client.post(
        "/complaints/register", json=_payload(), headers=auth_headers
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["status"] == "SUBMITTED"
    assert body["assigned_officer_id"] == OFFICER_ID
    assert body["resolved_boundary_id"] == 42
    assert body["unassigned"] is False
    assert body["routed"] is True

    # Complaint row stored with the authenticated citizen + EWKT location.
    complaint = fake_db.table("complaints").rows[0]
    assert complaint["citizen_id"] == CITIZEN_ID
    assert complaint["description_text"] == "Streetlight out on Anna Salai"
    assert complaint["input_mode"] == "VOICE"
    assert complaint["location"] == "SRID=4326;POINT(80.2707 13.0827)"
    assert complaint["assigned_officer_id"] == OFFICER_ID
    assert complaint["resolved_boundary_id"] == 42

    # Both images attached to the complaint.
    images = fake_db.table("complaint_images").rows
    assert len(images) == 2
    assert {i["image_url"] for i in images} == {
        "https://x/img1.jpg",
        "https://x/img2.jpg",
    }
    assert all(i["complaint_id"] == complaint["complaint_id"] for i in images)


def test_register_with_no_officer_found_still_records_complaint(
    fake_db, client, auth_headers
):
    # RPC returns nothing (routing data gap).
    fake_db.set_rpc_result("resolve_officer_for_complaint", [])

    resp = client.post(
        "/complaints/register",
        json=_payload(image_urls=[]),
        headers=auth_headers,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["assigned_officer_id"] is None
    assert body["unassigned"] is True
    assert body["routed"] is False
    assert len(fake_db.table("complaints").rows) == 1
    assert fake_db.table("complaint_images").rows == []


def test_register_notifies_officer_on_successful_routing(
    fake_db, client, auth_headers, monkeypatch
):
    calls = []
    monkeypatch.setattr(
        complaints_router,
        "notify_officer",
        lambda officer_id, complaint_id: calls.append((officer_id, complaint_id)),
    )
    fake_db.set_rpc_result(
        "resolve_officer_for_complaint",
        [{"officer_id": OFFICER_ID, "boundary_id": 42, "designation_id": 1}],
    )

    resp = client.post(
        "/complaints/register", json=_payload(), headers=auth_headers
    )
    complaint_id = resp.json()["complaint_id"]
    assert calls == [(OFFICER_ID, complaint_id)]


def test_register_does_not_notify_when_unrouted(
    fake_db, client, auth_headers, monkeypatch
):
    calls = []
    monkeypatch.setattr(
        complaints_router,
        "notify_officer",
        lambda officer_id, complaint_id: calls.append((officer_id, complaint_id)),
    )
    fake_db.set_rpc_result("resolve_officer_for_complaint", [])

    client.post("/complaints/register", json=_payload(), headers=auth_headers)
    assert calls == []


def test_register_unknown_department_rejected(fake_db, client, auth_headers):
    resp = client.post(
        "/complaints/register",
        json=_payload(department_id="NOPE"),
        headers=auth_headers,
    )
    assert resp.status_code == 400


def test_list_departments(fake_db, client):
    resp = client.get("/complaints/departments")
    assert resp.status_code == 200
    assert resp.json()[0]["department_id"] == "GCC_ELECT"


def test_register_validates_coordinates(fake_db, client, auth_headers):
    resp = client.post(
        "/complaints/register",
        json=_payload(lat=200),
        headers=auth_headers,
    )
    assert resp.status_code == 422
