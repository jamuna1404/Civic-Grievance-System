"""Officer routes — enrollment (first-time) and related helpers.

Login/OTP lives in the auth router (/auth/officer/*). The officer home
dashboard is a later prompt.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.deps import get_current_officer_id
from app.core.phone import normalize_indian_phone
from app.core.security import create_session_token
from app.core.supabase_client import get_supabase
from app.schemas.citizen import (
    UpdatePreferencesRequest,
    UpdatePreferencesResponse,
)
from app.schemas.complaint import ComplaintListItem
from app.schemas.officer import (
    OfficerEnrollRequest,
    OfficerEnrollResponse,
    OfficerProfileResponse,
)

router = APIRouter(prefix="/officer", tags=["officer"])

_ACTIVE_STATUSES = ["SUBMITTED", "ACKNOWLEDGED", "IN_PROGRESS"]
_OWNER_TYPE = "OFFICER"

_POSITION_TAKEN_DETAIL = (
    "This position is already filled for the selected area. "
    "Please contact your department administrator."
)


def _is_unique_violation(exc: Exception) -> bool:
    """True if the exception is a Postgres unique-constraint violation (23505)."""
    code = getattr(exc, "code", None)
    if code == "23505":
        return True
    # postgrest APIError carries details in its message/args.
    return "23505" in str(exc) or "duplicate key" in str(exc).lower()


@router.post("/enroll", response_model=OfficerEnrollResponse)
def enroll_officer(payload: OfficerEnrollRequest) -> OfficerEnrollResponse:
    """Register a first-time officer with status PENDING_VERIFICATION.

    The (department_id, designation_id, boundary_id) seat is unique among
    non-suspended officers; if it's already taken, respond 409 with a clear,
    non-generic message.
    """
    try:
        phone = normalize_indian_phone(payload.phone_number)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc

    supabase = get_supabase()

    # Pre-check for a clear 409 (the DB unique index is the real guard; this
    # also gives a friendly message without depending on driver error parsing).
    existing = (
        supabase.table("officers")
        .select("officer_id, status")
        .eq("department_id", payload.department_id)
        .eq("designation_id", payload.designation_id)
        .eq("boundary_id", payload.boundary_id)
        .neq("status", "SUSPENDED")
        .limit(1)
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=_POSITION_TAKEN_DETAIL
        )

    row = {
        "full_name": payload.full_name.strip(),
        "phone": phone,
        "email": payload.email,
        "employee_id": payload.employee_id,
        "department_id": payload.department_id,
        "designation_id": payload.designation_id,
        "boundary_id": payload.boundary_id,
        "status": "PENDING_VERIFICATION",
    }

    try:
        result = supabase.table("officers").insert(row).execute()
    except Exception as exc:  # noqa: BLE001 — inspect for the unique violation
        if _is_unique_violation(exc):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_POSITION_TAKEN_DETAIL,
            ) from exc
        raise

    officer = result.data[0]
    return OfficerEnrollResponse(
        officer_id=officer["officer_id"],
        full_name=officer["full_name"],
        status=officer["status"],
        session_token=create_session_token(officer["officer_id"]),
    )


def _load_officer(supabase, officer_id: str) -> dict:
    result = (
        supabase.table("officers")
        .select("*")
        .eq("officer_id", officer_id)
        .limit(1)
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Officer not found."
        )
    return result.data[0]


def _guard_self(path_officer_id: str, token_officer_id: str) -> None:
    if path_officer_id != token_officer_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only access your own account.",
        )


@router.get(
    "/{officer_id}/complaints", response_model=list[ComplaintListItem]
)
def allotted_complaints(
    officer_id: str,
    status_filter: str = Query("active", alias="status"),
    token_officer_id: str = Depends(get_current_officer_id),
) -> list[ComplaintListItem]:
    """Complaints assigned to this officer.

    `status=active` (default) returns open complaints only
    (SUBMITTED / ACKNOWLEDGED / IN_PROGRESS); `status=all` returns everything.
    """
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()

    query = (
        supabase.table("complaint_details")
        .select("*")
        .eq("assigned_officer_id", officer_id)
    )
    if status_filter == "active":
        query = query.in_("status", _ACTIVE_STATUSES)
    result = query.order("created_at", desc=True).execute()
    return [ComplaintListItem(**row) for row in result.data]


@router.get("/{officer_id}/track", response_model=list[ComplaintListItem])
def jurisdiction_complaints(
    officer_id: str,
    token_officer_id: str = Depends(get_current_officer_id),
) -> list[ComplaintListItem]:
    """All complaints in this officer's jurisdiction boundary (any status),
    for reference. Read-only on the client."""
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()
    officer = _load_officer(supabase, officer_id)

    result = (
        supabase.table("complaint_details")
        .select("*")
        .eq("resolved_boundary_id", officer["boundary_id"])
        .order("created_at", desc=True)
        .execute()
    )
    return [ComplaintListItem(**row) for row in result.data]


@router.get("/{officer_id}/profile", response_model=OfficerProfileResponse)
def officer_profile(
    officer_id: str,
    token_officer_id: str = Depends(get_current_officer_id),
) -> OfficerProfileResponse:
    """The officer's read-only profile plus theme preference."""
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()
    officer = _load_officer(supabase, officer_id)

    dept = (
        supabase.table("departments")
        .select("department_name")
        .eq("department_id", officer["department_id"])
        .limit(1)
        .execute()
    )
    desig = (
        supabase.table("designations")
        .select("designation_name")
        .eq("designation_id", officer["designation_id"])
        .limit(1)
        .execute()
    )
    boundary = (
        supabase.table("boundaries")
        .select("boundary_name")
        .eq("boundary_id", officer["boundary_id"])
        .limit(1)
        .execute()
    )
    prefs = (
        supabase.table("user_preferences")
        .select("theme_mode")
        .eq("owner_type", _OWNER_TYPE)
        .eq("owner_id", officer_id)
        .limit(1)
        .execute()
    )

    return OfficerProfileResponse(
        officer_id=officer_id,
        full_name=officer["full_name"],
        phone=officer["phone"],
        email=officer.get("email"),
        employee_id=officer.get("employee_id"),
        department_id=officer["department_id"],
        department_name=dept.data[0]["department_name"] if dept.data else "",
        designation_name=desig.data[0]["designation_name"] if desig.data else "",
        jurisdiction_name=(
            boundary.data[0]["boundary_name"] if boundary.data else ""
        ),
        status=officer["status"],
        theme_mode=prefs.data[0]["theme_mode"] if prefs.data else "SYSTEM",
    )


@router.put("/preferences", response_model=UpdatePreferencesResponse)
def update_officer_preferences(
    payload: UpdatePreferencesRequest,
    officer_id: str = Depends(get_current_officer_id),
) -> UpdatePreferencesResponse:
    """Persist the officer's theme preference (user_preferences, OFFICER)."""
    supabase = get_supabase()
    supabase.table("user_preferences").upsert(
        {
            "owner_type": _OWNER_TYPE,
            "owner_id": officer_id,
            "theme_mode": payload.theme_mode,
        },
        on_conflict="owner_type,owner_id",
    ).execute()
    return UpdatePreferencesResponse(theme_mode=payload.theme_mode)
