import logging
import uuid
from datetime import datetime
from typing import Optional, List, Dict, Tuple, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from fastapi import HTTPException, status
from app.models.all_models import Complaint, ComplaintEvent, User, Jurisdiction, Notification

logger = logging.getLogger("workflow_engine")

# Explicit state transitions table (FR-5.1)
# Format: (source_status, target_status, action, allowed_roles)
ALLOWED_TRANSITIONS = [
    ("registered", "assigned", "assign", ["system", "supervisor", "admin"]),
    ("registered", "needs_review", "flag_review", ["system", "supervisor", "admin"]),
    ("needs_review", "assigned", "assign_manually", ["supervisor", "admin"]),
    ("assigned", "in_progress", "start_work", ["officer", "admin"]),
    ("in_progress", "resolved", "mark_resolved", ["officer", "admin"]),
    ("resolved", "closed", "approve", ["supervisor", "admin"]),
    ("resolved", "in_progress", "reject", ["supervisor", "admin"]),
    
    # SLA escalation paths (FR-5.4)
    ("assigned", "escalated", "escalate", ["system", "supervisor", "admin"]),
    ("in_progress", "escalated", "escalate", ["system", "supervisor", "admin"]),
    
    # Administrative escalations
    ("needs_review", "needs_review", "update_details", ["supervisor", "admin"]),
    ("assigned", "needs_review", "revert_review", ["supervisor", "admin"]),
]

async def check_jurisdiction_access(db: AsyncSession, actor: User, complaint: Complaint):
    """
    Validates role-based geographic access rules.
    An officer or supervisor trying to act on a complaint outside their zone/ward gets a 403.
    """
    if actor.role == "admin":
        return  # Admins have global access
        
    if actor.role == "officer":
        # Officer must belong to the exact jurisdiction/office assigned to the complaint
        if complaint.jurisdiction_id != actor.jurisdiction_id:
            logger.warning(f"Forbidden: Officer {actor.id} jurisdiction {actor.jurisdiction_id} does not match complaint jurisdiction {complaint.jurisdiction_id}")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to act on complaints outside your assigned office."
            )
            
    elif actor.role == "supervisor":
        # Supervisor must belong to the same zone as the complaint
        if actor.jurisdiction_id is not None and complaint.jurisdiction_id is not None:
            # Fetch supervisor's zone
            stmt_super = select(Jurisdiction).where(Jurisdiction.id == actor.jurisdiction_id)
            res_super = await db.execute(stmt_super)
            super_j = res_super.scalar_one_or_none()
            
            # Fetch complaint's zone
            stmt_comp = select(Jurisdiction).where(Jurisdiction.id == complaint.jurisdiction_id)
            res_comp = await db.execute(stmt_comp)
            comp_j = res_comp.scalar_one_or_none()
            
            if not super_j or not comp_j or super_j.zone != comp_j.zone:
                logger.warning(f"Forbidden: Supervisor {actor.id} zone {super_j.zone if super_j else None} does not match complaint zone {comp_j.zone if comp_j else None}")
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not have permission to act on complaints outside your assigned administrative zone."
                )

async def transition_status(
    db: AsyncSession,
    complaint: Complaint,
    target_status: str,
    action: str,
    actor: Optional[User] = None, # None means system transition
    note: Optional[str] = None,
    evidence_image_url: Optional[str] = None
) -> Complaint:
    """
    Executes a status transition through the Workflow FSM.
    Enforces validation, access control, and records immutable history events.
    Satisfies FR-5.1, FR-5.2, FR-5.3, and FR-5.5.
    """
    source_status = complaint.status
    actor_role = actor.role if actor else "system"
    
    # 1. Validate if this transition is defined in the FSM table (FR-5.1)
    # Quote FR-5.1:
    # "FR-5.1: System shall enforce complaint status transitions via a defined state machine only."
    valid_transition = False
    for src, tgt, act, roles in ALLOWED_TRANSITIONS:
        if src == source_status and tgt == target_status and act == action:
            if actor_role in roles:
                valid_transition = True
                break
                
    if not valid_transition:
        logger.error(f"Invalid transition attempted: {source_status} -> {target_status} via {action} by role {actor_role}")
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Status transition from '{source_status}' to '{target_status}' via '{action}' is not allowed for role '{actor_role}'."
        )

    # 2. Check access controls (officers only assigned, supervisors zone-matched)
    if actor:
        await check_jurisdiction_access(db, actor, complaint)

    # 3. Enforce requirements for specific status transitions (FR-5.2)
    # Quote FR-5.2:
    # "FR-5.2: System shall require evidence and a closing note before a complaint can be marked resolved."
    if target_status == "resolved" and action == "mark_resolved":
        if not evidence_image_url:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Resolving a complaint requires uploading an evidence photograph."
            )
        if not note or len(note.strip()) < 5:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Resolving a complaint requires entering a descriptive closing note."
            )
        complaint.resolved_image_url = evidence_image_url
        complaint.resolved_note = note

    # 4. Update complaint status
    complaint.status = target_status
    
    # If supervisor rejects a resolved complaint, clear out the resolved values to allow officer to retry
    if target_status == "in_progress" and action == "reject":
        complaint.resolved_image_url = None
        complaint.resolved_note = None

    # 5. Log immutable audit history event (FR-5.5)
    # Quote FR-5.5:
    # "FR-5.5: System shall log an immutable record to the complaint_events audit log upon every status transition."
    actor_id = actor.id if actor else uuid.UUID("00000000-0000-0000-0000-000000000000") # System UUID
    event_note = note or f"Status changed from {source_status} to {target_status} via {action}."
    
    audit_event = ComplaintEvent(
        complaint_id=complaint.id,
        actor_id=actor_id,
        action=action,
        note=event_note
    )
    db.add(audit_event)
    await db.commit()
    await db.refresh(complaint)
    
    logger.info(f"Complaint {complaint.id} successfully transitioned {source_status} -> {target_status}")
    return complaint


async def check_sla_breaches(db: AsyncSession) -> int:
    """
    Identifies active complaints that have breached their SLA deadlines and auto-escalates them.
    Satisfies FR-5.4.
    """
    # Quote FR-5.4:
    # "FR-5.4: System shall auto-escalate complaints that breach their SLA deadline."
    now = datetime.utcnow()
    
    stmt = select(Complaint).where(
        Complaint.status.in_(["assigned", "in_progress"]),
        Complaint.sla_deadline < now
    )
    res = await db.execute(stmt)
    breached_complaints = res.scalars().all()
    
    count = 0
    for comp in breached_complaints:
        try:
            logger.info(f"Auto-escalating complaint {comp.id} (SLA deadline was {comp.sla_deadline})")
            # Transition through FSM with system actor
            await transition_status(
                db=db,
                complaint=comp,
                target_status="escalated",
                action="escalate",
                actor=None,
                note=f"Auto-escalated by system: SLA deadline ({comp.sla_deadline}) breached."
            )
            
            # Send notifications (simultaneous officer & supervisor CC)
            # Find assigned officer
            stmt_officer = select(User).where(User.jurisdiction_id == comp.jurisdiction_id, User.role == "officer")
            res_officer = await db.execute(stmt_officer)
            officer = res_officer.scalar_one_or_none()
            
            # Find supervisor for this zone
            if comp.jurisdiction_id:
                stmt_j = select(Jurisdiction).where(Jurisdiction.id == comp.jurisdiction_id)
                res_j = await db.execute(stmt_j)
                comp_j = res_j.scalar_one_or_none()
                if comp_j:
                    stmt_super = select(User).join(Jurisdiction, Jurisdiction.id == User.jurisdiction_id).where(
                        Jurisdiction.zone == comp_j.zone,
                        User.role == "supervisor"
                    )
                    res_super = await db.execute(stmt_super)
                    supervisor = res_super.scalar_one_or_none()
                    
                    if officer:
                        db.add(Notification(
                            user_id=officer.id,
                            complaint_id=comp.id,
                            message=f"CRITICAL: Complaint {comp.id} has breached SLA and has been escalated.",
                            channel="in_app"
                        ))
                    if supervisor:
                        db.add(Notification(
                            user_id=supervisor.id,
                            complaint_id=comp.id,
                            message=f"ESCALATION ALERT: Complaint {comp.id} under officer {officer.name if officer else 'Unassigned'} has breached SLA.",
                            channel="in_app"
                        ))
                        
            await db.commit()
            count += 1
        except Exception as e:
            logger.error(f"Failed to auto-escalate complaint {comp.id}: {str(e)}")
            
    return count
