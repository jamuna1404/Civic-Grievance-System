import uuid
import logging
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from pydantic import BaseModel

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.all_models import User, Notification
from app.schemas.all_schemas import NotificationRead

router = APIRouter()
logger = logging.getLogger("notifications_api")

class NotificationsResponse(BaseModel):
    notifications: List[NotificationRead]
    unread_count: int

@router.get("", response_model=NotificationsResponse)
async def list_notifications(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Retrieve current logged-in user's notifications and unread counts (Module 4.8).
    """
    logger.info(f"Listing notifications for user {current_user.id}")
    
    # Query all notifications for user
    stmt = select(Notification).where(
        Notification.user_id == current_user.id
    ).order_by(Notification.created_at.desc())
    res = await db.execute(stmt)
    notifications = res.scalars().all()
    
    # Query unread count
    stmt_unread = select(func.count(Notification.id)).where(
        Notification.user_id == current_user.id,
        Notification.read_at.is_(None)
    )
    res_unread = await db.execute(stmt_unread)
    unread_count = res_unread.scalar() or 0
    
    return {
        "notifications": notifications,
        "unread_count": unread_count
    }


@router.patch("/{notification_id}/read", response_model=NotificationRead)
async def mark_notification_read(
    notification_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Mark a specific notification as read, triggering a Realtime update (Module 4.8).
    """
    logger.info(f"Marking notification {notification_id} as read for user {current_user.id}")
    
    stmt = select(Notification).where(Notification.id == notification_id)
    res = await db.execute(stmt)
    notification = res.scalar_one_or_none()
    
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found."
        )
        
    if notification.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to modify this notification."
        )
        
    notification.read_at = datetime.utcnow()
    await db.commit()
    await db.refresh(notification)
    
    return notification
