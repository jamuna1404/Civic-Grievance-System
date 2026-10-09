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
from app.schemas.complaint import (
    ComplaintListItem,
    ReviewDecisionRequest,
    ReviewDecisionResponse,
    TeamComplaintItem,
)
from app.schemas.officer import (
    OfficerEnrollRequest,
    OfficerEnrollResponse,
    OfficerProfileResponse,
)
from app.services.complaint_history import attach_remarks_to_latest

router = APIRouter(prefix="/officer", tags=["officer"])

_ACTIVE_STATUSES = [
    "SUBMITTED", "ACKNOWLEDGED", "IN_PROGRESS", "RESOLUTION_REQUESTED",
]
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


def officer_manages_team(supabase, officer: dict) -> bool:
    """True if any designation in this officer's department ranks below
    theirs — i.e. they have subordinates, so "Manage Team" should show.

    Checked against the designation ladder itself, not filled officer
    seats, so the tab appears even if a subordinate slot is currently
    vacant.
    """
    own = (
        supabase.table("designations")
        .select("rank_order")
        .eq("department_id", officer["department_id"])
        .eq("designation_id", officer["designation_id"])
        .limit(1)
        .execute()
    )
    if not own.data:
        return False
    lower = (
        supabase.table("designations")
        .select("designation_id")
        .eq("department_id", officer["department_id"])
        .lt("rank_order", own.data[0]["rank_order"])
        .limit(1)
        .execute()
    )
    return bool(lower.data)


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
    (SUBMITTED / ACKNOWLEDGED / IN_PROGRESS / RESOLUTION_REQUESTED);
    `status=all` returns everything.

    Reads from `v_officer_complaints`, never `complaint_details` — that view
    joins the citizens table, and officer-facing endpoints must never fetch
    citizen identity.
    """
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()

    query = (
        supabase.table("v_officer_complaints")
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
        supabase.table("v_officer_complaints")
        .select("*")
        .eq("resolved_boundary_id", officer["boundary_id"])
        .order("created_at", desc=True)
        .execute()
    )
    return [ComplaintListItem(**row) for row in result.data]


@router.get(
    "/{officer_id}/team-complaints", response_model=list[TeamComplaintItem]
)
def team_complaints(
    officer_id: str,
    token_officer_id: str = Depends(get_current_officer_id),
) -> list[TeamComplaintItem]:
    """Complaints assigned to this officer's subordinates, anywhere in their
    boundary (and its descendants), RESOLUTION_REQUESTED items first.

    Delegates the boundary-descendant walk + rank comparison to
    team_complaints_for_officer() — see civicroute_manage_team.sql.
    """
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()
    result = supabase.rpc(
        "team_complaints_for_officer", {"p_officer_id": officer_id}
    ).execute()
    return [TeamComplaintItem(**row) for row in result.data]


@router.get("/{officer_id}/team-boundary-scope", response_model=list[int])
def team_boundary_scope(
    officer_id: str,
    token_officer_id: str = Depends(get_current_officer_id),
) -> list[int]:
    """The boundary_ids this officer manages: their own boundary plus every
    boundary below it. Used by the client's realtime closure-request filter
    (same scope team_complaints_for_officer restricts to)."""
    _guard_self(officer_id, token_officer_id)
    supabase = get_supabase()
    officer = _load_officer(supabase, officer_id)
    result = supabase.rpc(
        "get_boundary_descendants", {"p_boundary_id": officer["boundary_id"]}
    ).execute()
    return [row["boundary_id"] for row in result.data]


@router.put(
    "/complaints/{complaint_id}/review", response_model=ReviewDecisionResponse
)
def review_complaint(
    complaint_id: str,
    payload: ReviewDecisionRequest,
    reviewing_officer_id: str = Depends(get_current_officer_id),
) -> ReviewDecisionResponse:
    """A manager's decision on a subordinate's closure request.

    APPROVE -> RESOLVED. SEND_BACK -> IN_PROGRESS, and requires remarks
    (the subordinate needs to know what's still missing). Only valid from
    RESOLUTION_REQUESTED — the reviewer must actually outrank the assignee
    within the reviewer's own boundary scope, so a peer or unrelated
    officer with review-endpoint access can't approve someone else's item.
    """
    supabase = get_supabase()

    current = (
        supabase.table("complaints")
        .select("complaint_id, assigned_officer_id, resolved_boundary_id, status")
        .eq("complaint_id", complaint_id)
        .limit(1)
        .execute()
    )
    if not current.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Complaint not found."
        )
    complaint = current.data[0]

    if complaint["status"] != "RESOLUTION_REQUESTED":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only complaints awaiting review can be decided.",
        )

    if payload.decision == "SEND_BACK" and not (
        payload.remarks and payload.remarks.strip()
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Remarks are required when sending a complaint back.",
        )

    reviewer = _load_officer(supabase, reviewing_officer_id)
    assignee = _load_officer(supabase, complaint["assigned_officer_id"])

    reviewer_rank = (
        supabase.table("designations")
        .select("rank_order")
        .eq("department_id", reviewer["department_id"])
        .eq("designation_id", reviewer["designation_id"])
        .limit(1)
        .execute()
    )
    assignee_rank = (
        supabase.table("designations")
        .select("rank_order")
        .eq("department_id", assignee["department_id"])
        .eq("designation_id", assignee["designation_id"])
        .limit(1)
        .execute()
    )
    outranks = (
        bool(reviewer_rank.data)
        and bool(assignee_rank.data)
        and reviewer_rank.data[0]["rank_order"] > assignee_rank.data[0]["rank_order"]
    )
    in_scope = complaint["resolved_boundary_id"] in {
        row["boundary_id"]
        for row in supabase.rpc(
            "get_boundary_descendants", {"p_boundary_id": reviewer["boundary_id"]}
        ).execute().data
    }
    if not (outranks and in_scope):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You aren't the reviewing officer for this complaint.",
        )

    new_status = "RESOLVED" if payload.decision == "APPROVE" else "IN_PROGRESS"
    supabase.table("complaints").update({"status": new_status}).eq(
        "complaint_id", complaint_id
    ).execute()
    attach_remarks_to_latest(supabase, complaint_id, payload.remarks)

    return ReviewDecisionResponse(complaint_id=complaint_id, status=new_status)


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
        manages_team=officer_manages_team(supabase, officer),
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
