"""Request/response models for complaint registration."""

from typing import Literal

from pydantic import BaseModel, Field

InputMode = Literal["TEXT", "VOICE"]


class DepartmentResponse(BaseModel):
    department_id: str
    department_name: str
    jurisdiction_scope: str | None = None


class RegisterComplaintRequest(BaseModel):
    department_id: str
    description_text: str = Field(..., min_length=1)
    input_mode: InputMode = "TEXT"
    image_urls: list[str] = Field(default_factory=list)
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    address_label: str | None = None


class ComplaintListItem(BaseModel):
    complaint_id: str
    department_id: str
    department_name: str
    description_text: str
    input_mode: str
    status: str
    address_label: str | None = None
    lat: float | None = None
    lon: float | None = None
    image_urls: list[str] = Field(default_factory=list)
    created_at: str
    # Citizen contact — used by officers for follow-up (null-safe for citizens).
    citizen_name: str | None = None
    citizen_phone: str | None = None


class UpdateStatusRequest(BaseModel):
    new_status: Literal[
        "ACKNOWLEDGED", "IN_PROGRESS", "RESOLVED", "REJECTED"
    ]
    remarks: str | None = None
    # Accepted for API-contract completeness but the acting officer is taken
    # from the session token, not the body.
    changed_by_officer_id: str | None = None


class UpdateStatusResponse(BaseModel):
    complaint_id: str
    status: str


class ComplaintHistoryEntry(BaseModel):
    status: str
    remarks: str | None = None
    officer_name: str | None = None
    changed_at: str


class RegisterComplaintResponse(BaseModel):
    complaint_id: str
    status: str
    department_id: str
    assigned_officer_id: str | None = None
    resolved_boundary_id: int | None = None
    # True when routing found no officer for this location (data gap) — the
    # complaint is still recorded, just unassigned.
    unassigned: bool = False
    # True when an officer was actually assigned. Kept alongside `unassigned`
    # so the caller doesn't have to negate it to know assignment succeeded.
    routed: bool = False
