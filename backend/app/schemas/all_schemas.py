from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field

# --- DEPARTMENT SCHEMAS ---
class DepartmentBase(BaseModel):
    name: str
    category: str
    sla_hours: int

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    sla_hours: Optional[int] = None

class DepartmentRead(DepartmentBase):
    id: int
    model_config = ConfigDict(from_attributes=True)


# --- JURISDICTION SCHEMAS ---
class JurisdictionBase(BaseModel):
    zone: str
    ward: str
    area_name: str
    boundary: Any  # Can be GeoJSON dict or WKT string
    department_id: int
    office_name: str
    officer_contact: str

class JurisdictionCreate(JurisdictionBase):
    pass

class JurisdictionUpdate(BaseModel):
    zone: Optional[str] = None
    ward: Optional[str] = None
    area_name: Optional[str] = None
    boundary: Optional[Any] = None
    department_id: Optional[int] = None
    office_name: Optional[str] = None
    officer_contact: Optional[str] = None

class JurisdictionRead(JurisdictionBase):
    id: int
    model_config = ConfigDict(from_attributes=True)


# --- USER SCHEMAS ---
class UserBase(BaseModel):
    name: str
    role: str  # citizen / officer / supervisor / admin
    phone: Optional[str] = None
    email: Optional[str] = None
    jurisdiction_id: Optional[int] = None

class UserCreate(UserBase):
    id: UUID  # Must match Supabase Auth UID

class UserUpdate(BaseModel):
    name: Optional[str] = None
    role: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    jurisdiction_id: Optional[int] = None

class UserRead(UserBase):
    id: UUID
    model_config = ConfigDict(from_attributes=True)


# --- COMPLAINT SCHEMAS ---
class ComplaintBase(BaseModel):
    raw_text: Optional[str] = None
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    transcribed_text: Optional[str] = None
    detected_language: Optional[str] = None
    nlp_confidence: Optional[float] = None
    cv_label: Optional[str] = None
    cv_confidence: Optional[float] = None
    cv_severity: Optional[str] = None
    cv_conflict: bool = False



    category: Optional[str] = None
    subcategory: Optional[str] = None
    department_id: Optional[int] = None
    jurisdiction_id: Optional[int] = None
    gis_resolution_method: Optional[str] = None
    jurisdiction_uncertain: bool = False

    priority_score: Optional[int] = None
    priority_label: Optional[str] = None
    priority_breakdown: Optional[dict] = None
    resolved_image_url: Optional[str] = None
    resolved_note: Optional[str] = None


    status: str = "registered"
    address_text: Optional[str] = None
    cluster_id: Optional[UUID] = None
    sla_deadline: Optional[datetime] = None

class ComplaintCreate(BaseModel):
    raw_text: Optional[str] = None
    address_text: Optional[str] = None
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None

class ComplaintUpdate(BaseModel):
    raw_text: Optional[str] = None
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    transcribed_text: Optional[str] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    department_id: Optional[int] = None
    jurisdiction_id: Optional[int] = None
    priority_score: Optional[int] = None
    priority_label: Optional[str] = None
    status: Optional[str] = None
    address_text: Optional[str] = None
    cluster_id: Optional[UUID] = None
    sla_deadline: Optional[datetime] = None

class ComplaintRead(ComplaintBase):
    id: UUID
    citizen_id: UUID
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    created_at: datetime
    
    # We can handle custom serialization configuration for Pydantic
    model_config = ConfigDict(from_attributes=True)


# --- COMPLAINT EVENT SCHEMAS ---
class ComplaintEventBase(BaseModel):
    complaint_id: UUID
    action: str
    note: Optional[str] = None

class ComplaintEventCreate(ComplaintEventBase):
    pass

class ComplaintEventRead(ComplaintEventBase):
    id: UUID
    actor_id: UUID
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


# --- NOTIFICATION SCHEMAS ---
class NotificationBase(BaseModel):
    user_id: UUID
    complaint_id: Optional[UUID] = None
    message: str
    channel: str

class NotificationCreate(NotificationBase):
    pass

class NotificationUpdate(BaseModel):
    read_at: Optional[datetime] = None

class NotificationRead(NotificationBase):
    id: UUID
    read_at: Optional[datetime] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
