"""Citizen authentication routes.

Flow: send-otp -> verify-otp -> (complete-signup for new users).

OTP delivery is a **dummy implementation** for this milestone: a fixed code
is generated and stored, but no SMS is actually sent. See the TODO in
[send_citizen_otp] for where a real SMS gateway call belongs.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, status

from app.core.config import get_settings
from app.core.phone import normalize_indian_phone
from app.core.security import create_session_token
from app.core.supabase_client import get_supabase
from app.schemas.auth import (
    CompleteSignupRequest,
    CompleteSignupResponse,
    SendOtpRequest,
    SendOtpResponse,
    VerifyOtpRequest,
    VerifyOtpResponse,
)
from app.schemas.officer import OfficerVerifyOtpResponse

router = APIRouter(prefix="/auth", tags=["auth"])

# Dummy OTP settings. Replace with real generation once an SMS gateway is wired.
_DUMMY_OTP_CODE = "123456"
_OTP_TTL_MINUTES = 5


def _normalize_or_400(raw_phone: str) -> str:
    try:
        return normalize_indian_phone(raw_phone)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc


def _find_citizen(supabase, phone_number: str) -> dict | None:
    """Return the citizen row for a phone number, or None."""
    result = (
        supabase.table("citizens")
        .select("*")
        .eq("phone_number", phone_number)
        .limit(1)
        .execute()
    )
    return result.data[0] if result.data else None


def _find_officer(supabase, phone: str) -> dict | None:
    """Return the officer row for a phone number, or None."""
    result = (
        supabase.table("officers")
        .select("*")
        .eq("phone", phone)
        .limit(1)
        .execute()
    )
    return result.data[0] if result.data else None


def _store_dummy_otp(supabase, phone_number: str) -> SendOtpResponse:
    """Generate and store the dummy OTP for a number (shared by citizen/officer).

    No SMS is sent yet — see the TODO for where a real gateway call belongs.
    """
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=_OTP_TTL_MINUTES)

    # DUMMY: fixed code, stored but not delivered.
    # TODO: integrate a real SMS gateway here (MSG91 / Twilio / TN govt SMS).
    #   1. otp_code = f"{secrets.randbelow(1_000_000):06d}"
    #   2. send via the gateway API (handle failures / rate limits)
    #   3. only insert the row once the gateway accepts the message.
    supabase.table("otp_verifications").insert(
        {
            "phone_number": phone_number,
            "otp_code": _DUMMY_OTP_CODE,
            "purpose": "LOGIN",
            "is_used": False,
            "expires_at": expires_at.isoformat(),
        }
    ).execute()

    is_prod = get_settings().environment.lower() in {"production", "prod"}
    return SendOtpResponse(
        phone_number=phone_number,
        debug_otp=None if is_prod else _DUMMY_OTP_CODE,
    )


def _consume_valid_otp(supabase, phone_number: str, otp_code: str) -> None:
    """Validate the latest unused OTP and mark it used, or raise HTTP 400."""
    result = (
        supabase.table("otp_verifications")
        .select("*")
        .eq("phone_number", phone_number)
        .eq("is_used", False)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    record = result.data[0] if result.data else None

    if record is None or record["otp_code"] != otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OTP. Please check the code and try again.",
        )

    if datetime.fromisoformat(record["expires_at"]) < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This OTP has expired. Request a new one.",
        )

    supabase.table("otp_verifications").update({"is_used": True}).eq(
        "otp_id", record["otp_id"]
    ).execute()


@router.post("/citizen/send-otp", response_model=SendOtpResponse)
def send_citizen_otp(payload: SendOtpRequest) -> SendOtpResponse:
    """Generate and store a (dummy) OTP for the given phone number.

    Always succeeds for a valid Indian number. No SMS is sent yet.
    """
    phone_number = _normalize_or_400(payload.phone_number)
    return _store_dummy_otp(get_supabase(), phone_number)


@router.post("/citizen/verify-otp", response_model=VerifyOtpResponse)
def verify_citizen_otp(payload: VerifyOtpRequest) -> VerifyOtpResponse:
    """Verify an OTP, consuming it. Reports whether the caller is a new user."""
    phone_number = _normalize_or_400(payload.phone_number)
    supabase = get_supabase()

    _consume_valid_otp(supabase, phone_number, payload.otp_code)

    citizen = _find_citizen(supabase, phone_number)
    if citizen is None:
        return VerifyOtpResponse(new_user=True)

    return VerifyOtpResponse(
        new_user=False,
        session_token=create_session_token(citizen["citizen_id"]),
        full_name=citizen["full_name"],
        citizen_id=citizen["citizen_id"],
    )


@router.post("/citizen/complete-signup", response_model=CompleteSignupResponse)
def complete_citizen_signup(
    payload: CompleteSignupRequest,
) -> CompleteSignupResponse:
    """Create the citizen record for a freshly verified new user."""
    phone_number = _normalize_or_400(payload.phone_number)
    full_name = payload.full_name.strip()
    if not full_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Full name is required.",
        )

    supabase = get_supabase()

    # Guard against a double-submit / race creating two rows.
    existing = _find_citizen(supabase, phone_number)
    if existing is not None:
        return CompleteSignupResponse(
            session_token=create_session_token(existing["citizen_id"]),
            full_name=existing["full_name"],
            citizen_id=existing["citizen_id"],
        )

    result = (
        supabase.table("citizens")
        .insert(
            {
                "phone_number": phone_number,
                "full_name": full_name,
                "is_verified": True,
            }
        )
        .execute()
    )
    citizen = result.data[0]

    return CompleteSignupResponse(
        session_token=create_session_token(citizen["citizen_id"]),
        full_name=citizen["full_name"],
        citizen_id=citizen["citizen_id"],
    )


# --- Officer auth ------------------------------------------------------------
# Same dummy OTP flow as citizens, but verify-otp checks the officers table.


@router.post("/officer/send-otp", response_model=SendOtpResponse)
def send_officer_otp(payload: SendOtpRequest) -> SendOtpResponse:
    """Generate and store a (dummy) OTP for an officer login."""
    phone_number = _normalize_or_400(payload.phone_number)
    return _store_dummy_otp(get_supabase(), phone_number)


@router.post("/officer/verify-otp", response_model=OfficerVerifyOtpResponse)
def verify_officer_otp(payload: VerifyOtpRequest) -> OfficerVerifyOtpResponse:
    """Verify an officer OTP. `new_user: true` means no officer exists yet
    for that number (they should enroll first)."""
    phone_number = _normalize_or_400(payload.phone_number)
    supabase = get_supabase()

    _consume_valid_otp(supabase, phone_number, payload.otp_code)

    officer = _find_officer(supabase, phone_number)
    if officer is None:
        return OfficerVerifyOtpResponse(new_user=True)

    return OfficerVerifyOtpResponse(
        new_user=False,
        session_token=create_session_token(officer["officer_id"]),
        full_name=officer["full_name"],
        status=officer["status"],
        officer_id=officer["officer_id"],
    )
