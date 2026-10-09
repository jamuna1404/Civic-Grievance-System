"""Request/response models for officer enrollment, auth, and the cascading
department → designation → boundary pickers."""

from pydantic import BaseModel, Field


# --- Reference data for the enrollment pickers -------------------------------


class DesignationOption(BaseModel):
    designation_id: int
    designation_name: str
    level_name: str
    rank_order: int


class BoundaryLevelOption(BaseModel):
    level_rank: int
    level_name: str
    display_label: str


class BoundaryOption(BaseModel):
    boundary_id: int
    boundary_name: str
    level_name: str
    parent_boundary_id: int | None = None


# --- Enrollment --------------------------------------------------------------


class OfficerEnrollRequest(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=120)
    phone_number: str = Field(..., examples=["9876543210"])
    department_id: str
    designation_id: int
    boundary_id: int
    employee_id: str | None = None
    email: str | None = None


class OfficerEnrollResponse(BaseModel):
    officer_id: str
    full_name: str
    status: str
    session_token: str


# --- Auth (login) ------------------------------------------------------------


class OfficerVerifyOtpResponse(BaseModel):
    new_user: bool
    session_token: str | None = None
    full_name: str | None = None
    status: str | None = None
    officer_id: str | None = None
    # True if any designation in this officer's department ranks below
    # theirs — i.e. they have subordinates and should see "Manage Team".
    manages_team: bool = False


# --- Profile -----------------------------------------------------------------


class OfficerProfileResponse(BaseModel):
    officer_id: str
    full_name: str
    phone: str
    email: str | None = None
    employee_id: str | None = None
    department_id: str
    department_name: str
    designation_name: str
    jurisdiction_name: str
    status: str
    theme_mode: str = "SYSTEM"
    manages_team: bool = False
