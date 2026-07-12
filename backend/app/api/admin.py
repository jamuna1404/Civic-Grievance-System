import logging
from datetime import datetime, timedelta
from typing import List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from geoalchemy2.functions import ST_AsGeoJSON

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.all_models import User, Jurisdiction, Complaint, Department

router = APIRouter()
logger = logging.getLogger("admin_api")

def enforce_admin(user: User = Depends(get_current_user)):
    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to administrators only."
        )

@router.get("/jurisdictions", dependencies=[Depends(enforce_admin)])
async def get_admin_jurisdictions(db: AsyncSession = Depends(get_db)):
    """
    Returns all jurisdictions with their boundary polygons serialized to GeoJSON,
    plus counts of open complaints in each (FR-8.2).
    """
    logger.info("Admin fetching jurisdiction boundaries with open counts")
    
    # 1. Fetch open complaint counts grouped by jurisdiction
    stmt_counts = select(
        Complaint.jurisdiction_id,
        func.count(Complaint.id)
    ).where(
        Complaint.status.in_(["registered", "assigned", "in_progress", "escalated"])
    ).group_by(Complaint.jurisdiction_id)
    res_counts = await db.execute(stmt_counts)
    counts = {row[0]: row[1] for row in res_counts.all() if row[0] is not None}

    # 2. Fetch jurisdictions with GeoJSON boundaries
    stmt_j = select(
        Jurisdiction,
        func.ST_AsGeoJSON(Jurisdiction.boundary).label("geojson")
    )
    res_j = await db.execute(stmt_j)
    rows = res_j.all()

    results = []
    for row in rows:
        j, geojson_str = row
        results.append({
            "id": j.id,
            "zone": j.zone,
            "ward": j.ward,
            "area_name": j.area_name,
            "office_name": j.office_name,
            "officer_contact": j.officer_contact,
            "geojson": geojson_str, # String representation of GeoJSON
            "open_count": counts.get(j.id, 0)
        })

    return results


@router.get("/stats", dependencies=[Depends(enforce_admin)])
async def get_admin_stats(db: AsyncSession = Depends(get_db)):
    """
    Returns analytics summary statistics (FR-8.2 / SRS Section 8.2).
    - Total complaints this month
    - Top 3 departments by volume
    - Top 3 wards by escalation rate
    """
    logger.info("Admin fetching analytics summary stats")
    
    # 1. Total complaints in last 30 days
    last_30_days = datetime.utcnow() - timedelta(days=30)
    stmt_total = select(func.count(Complaint.id)).where(Complaint.created_at >= last_30_days)
    res_total = await db.execute(stmt_total)
    total_this_month = res_total.scalar() or 0

    # 2. Top 3 departments by volume
    stmt_depts = select(
        Department.name,
        func.count(Complaint.id)
    ).join(
        Complaint, Complaint.department_id == Department.id
    ).group_by(
        Department.name
    ).order_by(
        func.count(Complaint.id).desc()
    ).limit(3)
    res_depts = await db.execute(stmt_depts)
    top_departments = [{"name": row[0], "count": row[1]} for row in res_depts.all()]

    # 3. Top 3 wards by escalation rate
    stmt_wards = select(
        Jurisdiction.id,
        Jurisdiction.ward,
        Complaint.status
    ).join(
        Complaint, Complaint.jurisdiction_id == Jurisdiction.id
    )
    res_wards = await db.execute(stmt_wards)
    rows = res_wards.all()

    ward_stats = {}
    for row in rows:
        j_id, ward, status = row
        if ward not in ward_stats:
            ward_stats[ward] = {"total": 0, "escalated": 0}
        ward_stats[ward]["total"] += 1
        if status == "escalated":
            ward_stats[ward]["escalated"] += 1

    ward_rates = []
    for ward, stats in ward_stats.items():
        rate = (stats["escalated"] / stats["total"]) * 100 if stats["total"] > 0 else 0.0
        ward_rates.append({"ward": ward, "rate": rate})

    ward_rates.sort(key=lambda x: x["rate"], reverse=True)
    top_wards = ward_rates[:3]

    return {
        "total_this_month": total_this_month,
        "top_departments": top_departments,
        "top_wards": top_wards
    }
