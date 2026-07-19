"""Tests for the auth-guarded citizen profile & preferences routes."""

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_session_token
from app.main import app
from app.routers import citizen as citizen_router
from tests.fake_supabase import FakeSupabase

CITIZEN_ID = "11111111-1111-1111-1111-111111111111"
E164 = "+919876543210"


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    db.table("citizens").insert(
        {
            "citizen_id": CITIZEN_ID,
            "phone_number": E164,
            "full_name": "Priya Raman",
            "is_verified": True,
        }
    )
    monkeypatch.setattr(citizen_router, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def auth_headers():
    return {"Authorization": f"Bearer {create_session_token(CITIZEN_ID)}"}


def test_requires_auth(fake_db, client):
    assert client.get("/citizen/me").status_code == 401
    assert (
        client.put(
            "/citizen/preferences", json={"theme_mode": "DARK"}
        ).status_code
        == 401
    )


def test_rejects_invalid_token(fake_db, client):
    resp = client.get(
        "/citizen/me", headers={"Authorization": "Bearer not-a-real-token"}
    )
    assert resp.status_code == 401


def test_get_me_returns_profile_with_default_theme(fake_db, client, auth_headers):
    resp = client.get("/citizen/me", headers=auth_headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["full_name"] == "Priya Raman"
    assert body["phone_number"] == E164
    assert body["theme_mode"] == "SYSTEM"


def test_update_profile_name(fake_db, client, auth_headers):
    resp = client.put(
        "/citizen/profile",
        json={"full_name": "  Priya R  "},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["full_name"] == "Priya R"  # trimmed
    assert fake_db.table("citizens").rows[0]["full_name"] == "Priya R"


def test_update_preferences_upserts_single_row(fake_db, client, auth_headers):
    first = client.put(
        "/citizen/preferences", json={"theme_mode": "DARK"}, headers=auth_headers
    )
    assert first.status_code == 200
    assert first.json()["theme_mode"] == "DARK"

    second = client.put(
        "/citizen/preferences",
        json={"theme_mode": "LIGHT"},
        headers=auth_headers,
    )
    assert second.json()["theme_mode"] == "LIGHT"

    prefs = fake_db.table("user_preferences").rows
    assert len(prefs) == 1  # upsert, not a second insert
    assert prefs[0]["theme_mode"] == "LIGHT"
    assert prefs[0]["owner_type"] == "CITIZEN"
    assert prefs[0]["owner_id"] == CITIZEN_ID

    # And /me now reflects the stored preference.
    me = client.get("/citizen/me", headers=auth_headers)
    assert me.json()["theme_mode"] == "LIGHT"


def test_invalid_theme_mode_rejected(fake_db, client, auth_headers):
    resp = client.put(
        "/citizen/preferences",
        json={"theme_mode": "PURPLE"},
        headers=auth_headers,
    )
    assert resp.status_code == 422
