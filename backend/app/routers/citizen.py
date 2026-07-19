"""Citizen profile & preferences routes.

All routes require a valid citizen session (Bearer token). The citizen is
identified from the token, never from the request body, so a caller can only
read/modify their own record.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.deps import get_current_citizen_id
from app.core.supabase_client import get_supabase
from app.schemas.citizen import (
    CitizenProfileResponse,
    UpdatePreferencesRequest,
    UpdatePreferencesResponse,
    UpdateProfileRequest,
    UpdateProfileResponse,
)
from app.schemas.complaint import ComplaintListItem

router = APIRouter(prefix="/citizen", tags=["citizen"])

_OWNER_TYPE = "CITIZEN"


def _load_citizen(supabase, citizen_id: str) -> dict:
    result = (
        supabase.table("citizens")
        .select("*")
        .eq("citizen_id", citizen_id)
        .limit(1)
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Citizen not found."
        )
    return result.data[0]


def _load_theme_mode(supabase, citizen_id: str) -> str:
    result = (
        supabase.table("user_preferences")
        .select("theme_mode")
        .eq("owner_type", _OWNER_TYPE)
        .eq("owner_id", citizen_id)
        .limit(1)
        .execute()
    )
    return result.data[0]["theme_mode"] if result.data else "SYSTEM"


@router.get("/me", response_model=CitizenProfileResponse)
def get_me(
    citizen_id: str = Depends(get_current_citizen_id),
) -> CitizenProfileResponse:
    """Return the signed-in citizen's profile and theme preference."""
    supabase = get_supabase()
    citizen = _load_citizen(supabase, citizen_id)
    return CitizenProfileResponse(
        citizen_id=citizen["citizen_id"],
        full_name=citizen["full_name"],
        phone_number=citizen["phone_number"],
        theme_mode=_load_theme_mode(supabase, citizen_id),
    )


@router.put("/profile", response_model=UpdateProfileResponse)
def update_profile(
    payload: UpdateProfileRequest,
    citizen_id: str = Depends(get_current_citizen_id),
) -> UpdateProfileResponse:
    """Update the citizen's display name."""
    full_name = payload.full_name.strip()
    if not full_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Full name is required.",
        )

    supabase = get_supabase()
    result = (
        supabase.table("citizens")
        .update({"full_name": full_name})
        .eq("citizen_id", citizen_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Citizen not found."
        )
    return UpdateProfileResponse(full_name=result.data[0]["full_name"])


@router.get("/{citizen_id}/complaints", response_model=list[ComplaintListItem])
def list_complaints(
    citizen_id: str,
    token_citizen_id: str = Depends(get_current_citizen_id),
) -> list[ComplaintListItem]:
    """List the citizen's complaints, newest first.

    The path citizen_id must match the authenticated citizen — you can only
    read your own complaints.
    """
    if citizen_id != token_citizen_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only view your own complaints.",
        )

    supabase = get_supabase()
    result = (
        supabase.table("complaint_details")
        .select("*")
        .eq("citizen_id", citizen_id)
        .order("created_at", desc=True)
        .execute()
    )
    return [ComplaintListItem(**row) for row in result.data]


@router.put("/preferences", response_model=UpdatePreferencesResponse)
def update_preferences(
    payload: UpdatePreferencesRequest,
    citizen_id: str = Depends(get_current_citizen_id),
) -> UpdatePreferencesResponse:
    """Persist the citizen's theme preference to `user_preferences`.

    Upserts on the (owner_type, owner_id) primary key so repeated changes
    update the same row.
    """
    supabase = get_supabase()
    supabase.table("user_preferences").upsert(
        {
            "owner_type": _OWNER_TYPE,
            "owner_id": citizen_id,
            "theme_mode": payload.theme_mode,
        },
        on_conflict="owner_type,owner_id",
    ).execute()
    return UpdatePreferencesResponse(theme_mode=payload.theme_mode)
