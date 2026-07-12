import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from fastapi import HTTPException, status
from app.models.all_models import Complaint, User, Department, Jurisdiction, Notification
from app.services.workflow_engine import transition_status

logger = logging.getLogger("routing_engine")

CRITICAL_SLA_MULTIPLIER = 0.5  # shortened for Critical priority via a configured multiplier (FR-4.4)

async def route_complaint(db: AsyncSession, complaint: Complaint) -> Complaint:
    """
    Routes a resolved complaint to the appropriate field officer and notifies stakeholders.
    Satisfies FR-4.3, FR-4.4, and calls FSM to assign.
    """
    logger.info(f"Routing complaint {complaint.id}...")
    
    # 1. Match officer by jurisdiction_id + role (Module 4.4 / 4.6)
    # The resolved jurisdiction_id uniquely maps to a ward office and department.
    stmt_officer = select(User).where(
        User.jurisdiction_id == complaint.jurisdiction_id,
        User.role == "officer"
    )
    res_officer = await db.execute(stmt_officer)
    officer = res_officer.scalar_one_or_none()
    
    # 2. Find supervisor for the same administrative zone
    supervisor = None
    office_name = "Department Office"
    if complaint.jurisdiction_id:
        stmt_j = select(Jurisdiction).where(Jurisdiction.id == complaint.jurisdiction_id)
        res_j = await db.execute(stmt_j)
        comp_j = res_j.scalar_one_or_none()
        if comp_j:
            office_name = comp_j.office_name
            # Find supervisor supervising this zone
            stmt_super = select(User).join(Jurisdiction, Jurisdiction.id == User.jurisdiction_id).where(
                Jurisdiction.zone == comp_j.zone,
                User.role == "supervisor"
            )
            res_super = await db.execute(stmt_super)
            supervisor = res_super.scalar_one_or_none()

    # 3. Compute SLA Deadline (FR-4.4)
    # Quote FR-4.4:
    # "FR-4.4: System shall set an SLA deadline based on department and priority at assignment time."
    sla_hours = 48  # Default fallback SLA
    if complaint.department_id:
        stmt_dept = select(Department).where(Department.id == complaint.department_id)
        res_dept = await db.execute(stmt_dept)
        dept = res_dept.scalar_one_or_none()
        if dept:
            sla_hours = dept.sla_hours
            
    # Apply Critical multiplier if applicable
    if complaint.priority_label == "Critical":
        sla_hours = int(sla_hours * CRITICAL_SLA_MULTIPLIER)
        logger.info(f"Critical priority detected. SLA deadline shortened to {sla_hours} hours (Multiplier: {CRITICAL_SLA_MULTIPLIER})")
        
    complaint.sla_deadline = datetime.utcnow() + timedelta(hours=sla_hours)

    # 4. Transition status from registered -> assigned via Workflow FSM (FR-5.1)
    await transition_status(
        db=db,
        complaint=complaint,
        target_status="assigned",
        action="assign",
        actor=None, # System transition
        note=f"Complaint automatically routed to {office_name}."
    )

    # 5. Create notification rows simultaneously for citizen, officer, and supervisor (FR-4.3)
    # Quote FR-4.3:
    # "FR-4.3: System shall simultaneously notify the assigned officer and their supervisor upon routing."
    
    # Notification for Citizen
    db.add(Notification(
        user_id=complaint.citizen_id,
        complaint_id=complaint.id,
        message=f"Your complaint has been assigned to the {office_name}.",
        channel="in_app"
    ))
    
    # Notification for Officer
    if officer:
        db.add(Notification(
            user_id=officer.id,
            complaint_id=complaint.id,
            message=f"New complaint {complaint.id} has been assigned to you for resolution.",
            channel="in_app"
        ))
        logger.info(f"Queued notification for assigned officer: {officer.name}")
    else:
        logger.warning(f"No officer found for jurisdiction {complaint.jurisdiction_id}. Left unassigned.")

    # Notification for Supervisor
    if supervisor:
        db.add(Notification(
            user_id=supervisor.id,
            complaint_id=complaint.id,
            message=f"routed complaint {complaint.id} to officer {officer.name if officer else 'Unassigned'} in your zone.",
            channel="in_app"
        ))
        logger.info(f"Queued notification for supervising authority: {supervisor.name}")
        
    await db.commit()
    logger.info(f"Routing and notifications complete for complaint {complaint.id}")
    return complaint


async def route_manually_assigned(db: AsyncSession, complaint: Complaint) -> Complaint:
    """
    Sets SLA and routes a manually triaged complaint, notifying citizen, officer, and supervisor simultaneously (FR-4.3).
    """
    logger.info(f"Routing manually assigned complaint {complaint.id}...")
    
    # 1. Match officer by jurisdiction_id + role
    stmt_officer = select(User).where(
        User.jurisdiction_id == complaint.jurisdiction_id,
        User.role == "officer"
    )
    res_officer = await db.execute(stmt_officer)
    officer = res_officer.scalar_one_or_none()
    
    # 2. Find supervisor for the same zone
    supervisor = None
    office_name = "Department Office"
    if complaint.jurisdiction_id:
        stmt_j = select(Jurisdiction).where(Jurisdiction.id == complaint.jurisdiction_id)
        res_j = await db.execute(stmt_j)
        comp_j = res_j.scalar_one_or_none()
        if comp_j:
            office_name = comp_j.office_name
            stmt_super = select(User).join(Jurisdiction, Jurisdiction.id == User.jurisdiction_id).where(
                Jurisdiction.zone == comp_j.zone,
                User.role == "supervisor"
            )
            res_super = await db.execute(stmt_super)
            supervisor = res_super.scalar_one_or_none()

    # 3. Compute SLA Deadline (FR-4.4)
    sla_hours = 48
    if complaint.department_id:
        stmt_dept = select(Department).where(Department.id == complaint.department_id)
        res_dept = await db.execute(stmt_dept)
        dept = res_dept.scalar_one_or_none()
        if dept:
            sla_hours = dept.sla_hours
            
    if complaint.priority_label == "Critical":
        sla_hours = int(sla_hours * CRITICAL_SLA_MULTIPLIER)
        
    complaint.sla_deadline = datetime.utcnow() + timedelta(hours=sla_hours)

    # 4. Create notifications simultaneously (FR-4.3)
    db.add(Notification(
        user_id=complaint.citizen_id,
        complaint_id=complaint.id,
        message=f"Your complaint has been assigned to the {office_name}.",
        channel="in_app"
    ))
    
    if officer:
        db.add(Notification(
            user_id=officer.id,
            complaint_id=complaint.id,
            message=f"New complaint {complaint.id} has been assigned to you for resolution.",
            channel="in_app"
        ))
        
    if supervisor:
        db.add(Notification(
            user_id=supervisor.id,
            complaint_id=complaint.id,
            message=f"routed complaint {complaint.id} to officer {officer.name if officer else 'Unassigned'} in your zone.",
            channel="in_app"
        ))
        
    await db.commit()
    logger.info(f"Manual routing notifications sent for complaint {complaint.id}")
    return complaint

