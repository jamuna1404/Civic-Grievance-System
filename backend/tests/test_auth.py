"""End-to-end tests for the citizen auth flow, backed by an in-memory fake
Supabase (see fake_supabase.py). No live database required."""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.core.security import verify_session_token
from app.main import app
from app.routers import auth as auth_router
from tests.fake_supabase import FakeSupabase

PHONE = "9876543210"
E164 = "+919876543210"


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeSupabase()
    monkeypatch.setattr(auth_router, "get_supabase", lambda: db)
    return db


@pytest.fixture
def client():
    return TestClient(app)


def test_send_otp_stores_dummy_code_and_normalizes_phone(fake_db, client):
    resp = client.post("/auth/citizen/send-otp", json={"phone_number": PHONE})
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone_number"] == E164
    assert body["debug_otp"] == "123456"

    rows = fake_db.table("otp_verifications").rows
    assert len(rows) == 1
    assert rows[0]["otp_code"] == "123456"
    assert rows[0]["phone_number"] == E164
    assert rows[0]["is_used"] is False


def test_send_otp_rejects_invalid_number(fake_db, client):
    resp = client.post("/auth/citizen/send-otp", json={"phone_number": "12345"})
    assert resp.status_code == 400


def test_verify_new_user_then_complete_signup(fake_db, client):
    client.post("/auth/citizen/send-otp", json={"phone_number": PHONE})

    verify = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    assert verify.status_code == 200
    assert verify.json()["new_user"] is True
    assert verify.json()["session_token"] is None

    # OTP is consumed (single use).
    assert fake_db.table("otp_verifications").rows[0]["is_used"] is True

    signup = client.post(
        "/auth/citizen/complete-signup",
        json={"phone_number": PHONE, "full_name": "  Priya Raman  "},
    )
    assert signup.status_code == 200
    body = signup.json()
    assert body["full_name"] == "Priya Raman"  # trimmed
    assert verify_session_token(body["session_token"]) is not None

    citizen = fake_db.table("citizens").rows[0]
    assert citizen["phone_number"] == E164
    assert citizen["is_verified"] is True


def test_verify_existing_user_returns_token_not_new(fake_db, client):
    fake_db.table("citizens").insert(
        {"phone_number": E164, "full_name": "Existing User", "is_verified": True}
    )
    client.post("/auth/citizen/send-otp", json={"phone_number": PHONE})

    resp = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    body = resp.json()
    assert body["new_user"] is False
    assert body["full_name"] == "Existing User"
    assert verify_session_token(body["session_token"]) is not None


def test_verify_wrong_code_rejected(fake_db, client):
    client.post("/auth/citizen/send-otp", json={"phone_number": PHONE})
    resp = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "000000"},
    )
    assert resp.status_code == 400
    # OTP not consumed on a failed attempt.
    assert fake_db.table("otp_verifications").rows[0]["is_used"] is False


def test_verify_expired_code_rejected(fake_db, client):
    # Insert an already-expired OTP directly.
    fake_db.table("otp_verifications").insert(
        {
            "phone_number": E164,
            "otp_code": "123456",
            "purpose": "LOGIN",
            "is_used": False,
            "expires_at": (
                datetime.now(timezone.utc) - timedelta(minutes=1)
            ).isoformat(),
        }
    )
    resp = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    assert resp.status_code == 400
    assert "expired" in resp.json()["detail"].lower()


def test_used_otp_cannot_be_replayed(fake_db, client):
    client.post("/auth/citizen/send-otp", json={"phone_number": PHONE})
    first = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    assert first.status_code == 200
    # Second attempt with the same (now-used) code fails.
    second = client.post(
        "/auth/citizen/verify-otp",
        json={"phone_number": PHONE, "otp_code": "123456"},
    )
    assert second.status_code == 400
