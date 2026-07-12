import uuid
from datetime import datetime
from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Index, func, Float, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from geoalchemy2 import Geometry

from app.core.database import Base

class Department(Base):
    __tablename__ = "departments"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    name = Column(String, nullable=False)
    category = Column(String, nullable=False)
    sla_hours = Column(Integer, nullable=False)

    # Relationships
    jurisdictions = relationship("Jurisdiction", back_populates="department")
    complaints = relationship("Complaint", back_populates="department")


class Jurisdiction(Base):
    __tablename__ = "jurisdictions"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    zone = Column(String, nullable=False)
    ward = Column(String, nullable=False)
    area_name = Column(String, nullable=False)
    # boundary as a PostGIS Polygon column
    boundary = Column(Geometry(geometry_type="POLYGON", srid=4326), nullable=False)
    department_id = Column(Integer, ForeignKey("departments.id"), nullable=False)
    office_name = Column(String, nullable=False)
    officer_contact = Column(String, nullable=False)

    # Relationships
    department = relationship("Department", back_populates="jurisdictions")
    users = relationship("User", back_populates="jurisdiction")
    complaints = relationship("Complaint", back_populates="jurisdiction")


class User(Base):
    __tablename__ = "users"

    # UUID matches Supabase Auth user ID (sub claim)
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False)
    role = Column(String, nullable=False)  # citizen / officer / supervisor / admin
    phone = Column(String, nullable=True)
    email = Column(String, nullable=True)
    jurisdiction_id = Column(Integer, ForeignKey("jurisdictions.id"), nullable=True)

    # Relationships
    jurisdiction = relationship("Jurisdiction", back_populates="users")
    complaints = relationship("Complaint", back_populates="citizen", foreign_keys="[Complaint.citizen_id]")
    events = relationship("ComplaintEvent", back_populates="actor")
    notifications = relationship("Notification", back_populates="user")


class Complaint(Base):
    __tablename__ = "complaints"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    citizen_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    raw_text = Column(String, nullable=True)
    image_url = Column(String, nullable=True)
    audio_url = Column(String, nullable=True)
    transcribed_text = Column(String, nullable=True)
    detected_language = Column(String, nullable=True)
    nlp_confidence = Column(Float, nullable=True)
    cv_label = Column(String, nullable=True)
    cv_confidence = Column(Float, nullable=True)
    cv_severity = Column(String, nullable=True)
    cv_conflict = Column(Boolean, default=False)



    category = Column(String, nullable=True)
    subcategory = Column(String, nullable=True)
    department_id = Column(Integer, ForeignKey("departments.id"), nullable=True)
    jurisdiction_id = Column(Integer, ForeignKey("jurisdictions.id"), nullable=True)
    gis_resolution_method = Column(String, nullable=True)
    jurisdiction_uncertain = Column(Boolean, default=False)

    priority_score = Column(Integer, nullable=True)
    priority_label = Column(String, nullable=True)
    status = Column(String, nullable=False, default="registered")  # registered, assigned, in_progress, resolved, closed, escalated
    # location as a PostGIS Point column
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=True)
    address_text = Column(String, nullable=True)
    cluster_id = Column(UUID(as_uuid=True), nullable=True)
    sla_deadline = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=func.now())

    # Relationships
    citizen = relationship("User", back_populates="complaints", foreign_keys=[citizen_id])
    department = relationship("Department", back_populates="complaints")
    jurisdiction = relationship("Jurisdiction", back_populates="complaints")
    events = relationship("ComplaintEvent", back_populates="complaint")
    notifications = relationship("Notification", back_populates="complaint")


class ComplaintEvent(Base):
    __tablename__ = "complaint_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    complaint_id = Column(UUID(as_uuid=True), ForeignKey("complaints.id"), nullable=False)
    actor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    action = Column(String, nullable=False)
    note = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, default=func.now())

    # Relationships
    complaint = relationship("Complaint", back_populates="events")
    actor = relationship("User", back_populates="events")


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    complaint_id = Column(UUID(as_uuid=True), ForeignKey("complaints.id"), nullable=True)
    message = Column(String, nullable=False)
    channel = Column(String, nullable=False)  # push, email, SMS, in_app
    read_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=func.now())

    # Relationships
    user = relationship("User", back_populates="notifications")
    complaint = relationship("Complaint", back_populates="notifications")


# Let's clean up indices as requested by the prompt (indexes on complaints.status, complaints.department_id, complaints.jurisdiction_id)
# Alembic creates them, but we can also declare them in the models or migration. Declaring them in the models is clean.
# Also spatial indices for boundary and location are automatically handled by GeoAlchemy2 (using gist).
Index("idx_complaints_status", Complaint.status)
Index("idx_complaints_department_id", Complaint.department_id)
Index("idx_complaints_jurisdiction_id", Complaint.jurisdiction_id)
