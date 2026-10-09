"""Complaint registration routes.

Registration is auth-guarded: the citizen is taken from the session token, not
the request body, so a caller can only file complaints as themselves.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.deps import get_current_citizen_id, get_current_officer_id
from app.core.supabase_client import get_supabase
from app.services.complaint_history import attach_remarks_to_latest
from app.services.notifications import notify_officer
from app.schemas.complaint import (
    ComplaintHistoryEntry,
    DepartmentResponse,
    RegisterComplaintRequest,
    RegisterComplaintResponse,
    UpdateStatusRequest,
    UpdateStatusResponse,
)

router = APIRouter(prefix="/complaints", tags=["complaints"])

# The one valid forward move an assigned officer may make from each status.
# RESOLUTION_REQUESTED is a dead end for the officer — only a supervisor
# (not built here) can move it to RESOLVED/REJECTED.
_ALLOWED_OFFICER_TRANSITIONS = {
    "SUBMITTED": "ACKNOWLEDGED",
    "ACKNOWLEDGED": "IN_PROGRESS",
    "IN_PROGRESS": "RESOLUTION_REQUESTED",
}


def _can_view_complaint(supabase, complaint: dict, subject_id: str) -> bool:
    """True if the subject is the owning citizen, the assigned officer, or an
    officer whose jurisdiction boundary matches the complaint."""
    if complaint["citizen_id"] == subject_id:
        return True
    if complaint.get("assigned_officer_id") == subject_id:
        return True
    officer = (
        supabase.table("officers")
        .select("boundary_id")
        .eq("officer_id", subject_id)
        .limit(1)
        .execute()
    )
    if officer.data:
        return officer.data[0]["boundary_id"] == complaint.get(
            "resolved_boundary_id"
        )
    return False


@router.get("/departments", response_model=list[DepartmentResponse])
def list_departments() -> list[DepartmentResponse]:
    """List the departments a complaint can be routed to."""
    supabase = get_supabase()
    result = (
        supabase.table("departments")
        .select("department_id, department_name, jurisdiction_scope")
        .execute()
    )
    return [DepartmentResponse(**row) for row in result.data]


@router.get(
    "/{complaint_id}/history", response_model=list[ComplaintHistoryEntry]
)
def complaint_history(
    complaint_id: str,
    subject_id: str = Depends(get_current_citizen_id),
) -> list[ComplaintHistoryEntry]:
    """Return the status history of a complaint, oldest first.

    Visible to the owning citizen, the assigned officer, or an officer whose
    jurisdiction boundary matches the complaint.
    """
    supabase = get_supabase()

    row = (
        supabase.table("complaint_details")
        .select("citizen_id, assigned_officer_id, resolved_boundary_id")
        .eq("complaint_id", complaint_id)
        .limit(1)
        .execute()
    )
    if not row.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Complaint not found."
        )
    if not _can_view_complaint(supabase, row.data[0], subject_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this complaint.",
        )

    result = (
        supabase.table("complaint_history_view")
        .select("status, remarks, officer_name, changed_at")
        .eq("complaint_id", complaint_id)
        .order("changed_at", desc=False)
        .execute()
    )
    return [ComplaintHistoryEntry(**row) for row in result.data]


@router.put("/{complaint_id}/status", response_model=UpdateStatusResponse)
def update_complaint_status(
    complaint_id: str,
    payload: UpdateStatusRequest,
    officer_id: str = Depends(get_current_officer_id),
) -> UpdateStatusResponse:
    """Move a complaint forward. Only the assigned officer may do this.

    The status UPDATE fires the AFTER-UPDATE trigger that logs a
    complaint_status_history row (with changed_by = assigned officer). If
    remarks are supplied, they're written onto that just-logged entry.
    """
    supabase = get_supabase()

    current = (
        supabase.table("complaints")
        .select("complaint_id, assigned_officer_id, status")
        .eq("complaint_id", complaint_id)
        .limit(1)
        .execute()
    )
    if not current.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Complaint not found."
        )
    complaint = current.data[0]
    if complaint["assigned_officer_id"] != officer_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This complaint isn't assigned to you.",
        )

    if payload.new_status == complaint["status"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The complaint is already in that status.",
        )

    allowed_next = _ALLOWED_OFFICER_TRANSITIONS.get(complaint["status"])
    if payload.new_status != allowed_next:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Can't move from {complaint['status']} to "
                f"{payload.new_status}. Steps can't be skipped."
            ),
        )

    # Update status — the AFTER-UPDATE trigger logs the history row.
    supabase.table("complaints").update({"status": payload.new_status}).eq(
        "complaint_id", complaint_id
    ).execute()

    # Attach remarks to the entry the trigger just created (latest for this
    # complaint).
    attach_remarks_to_latest(supabase, complaint_id, payload.remarks)

    # Closure requests need a reviewing (next-rank) officer notified.
    reviewer_assigned = False
    if payload.new_status == "RESOLUTION_REQUESTED":
        reviewer = supabase.rpc(
            "resolve_reviewing_officer", {"p_complaint_id": complaint_id}
        ).execute()
        if reviewer.data:
            notify_officer(reviewer.data[0]["officer_id"], complaint_id)
            reviewer_assigned = True

    return UpdateStatusResponse(
        complaint_id=complaint_id,
        status=payload.new_status,
        reviewer_assigned=reviewer_assigned,
    )


@router.post("/register", response_model=RegisterComplaintResponse)
def register_complaint(
    payload: RegisterComplaintRequest,
    citizen_id: str = Depends(get_current_citizen_id),
) -> RegisterComplaintResponse:
    """Create a complaint, attach its images, and route it to an officer.

    Steps:
      1. Validate the department exists.
      2. Insert the complaint (the status-history trigger logs SUBMITTED).
      3. Insert each image URL into complaint_images.
      4. Resolve the responsible officer via the PostGIS routing function and
         write assigned_officer_id / resolved_boundary_id back.
    """
    supabase = get_supabase()

    # 1. Department must exist (nicer than a raw FK violation).
    dept = (
        supabase.table("departments")
        .select("department_id")
        .eq("department_id", payload.department_id)
        .limit(1)
        .execute()
    )
    if not dept.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unknown department.",
        )

    # 2. Insert the complaint. PostGIS accepts EWKT for the geometry column.
    location_ewkt = f"SRID=4326;POINT({payload.lon} {payload.lat})"
    inserted = (
        supabase.table("complaints")
        .insert(
            {
                "citizen_id": citizen_id,
                "department_id": payload.department_id,
                "description_text": payload.description_text,
                "input_mode": payload.input_mode,
                "location": location_ewkt,
                "address_label": payload.address_label,
            }
        )
        .execute()
    )
    complaint = inserted.data[0]
    complaint_id = complaint["complaint_id"]

    # 3. Attach images (one row each).
    if payload.image_urls:
        supabase.table("complaint_images").insert(
            [
                {"complaint_id": complaint_id, "image_url": url}
                for url in payload.image_urls
            ]
        ).execute()

    # 4. Route to an officer via the boundary schema's PostGIS function.
    rpc_result = supabase.rpc(
        "resolve_officer_for_complaint",
        {
            "p_department_id": payload.department_id,
            "p_lon": payload.lon,
            "p_lat": payload.lat,
        },
    ).execute()

    assigned_officer_id: str | None = None
    resolved_boundary_id: int | None = None
    if rpc_result.data:
        row = rpc_result.data[0]
        assigned_officer_id = row.get("officer_id")
        resolved_boundary_id = row.get("boundary_id")
        supabase.table("complaints").update(
            {
                "assigned_officer_id": assigned_officer_id,
                "resolved_boundary_id": resolved_boundary_id,
            }
        ).eq("complaint_id", complaint_id).execute()
        notify_officer(assigned_officer_id, complaint_id)

    return RegisterComplaintResponse(
        complaint_id=complaint_id,
        status=complaint.get("status", "SUBMITTED"),
        department_id=payload.department_id,
        assigned_officer_id=assigned_officer_id,
        resolved_boundary_id=resolved_boundary_id,
        unassigned=assigned_officer_id is None,
        routed=assigned_officer_id is not None,
    )
