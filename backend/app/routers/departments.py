"""Read-only reference data for officer enrollment: designations, boundary
levels, and boundaries (used by the cascading jurisdiction picker)."""

from fastapi import APIRouter, Query

from app.core.supabase_client import get_supabase
from app.schemas.officer import (
    BoundaryLevelOption,
    BoundaryOption,
    DesignationOption,
)

router = APIRouter(prefix="/departments", tags=["departments"])


@router.get("/{department_id}/designations", response_model=list[DesignationOption])
def list_designations(department_id: str) -> list[DesignationOption]:
    """Designations for a department, lowest rank (first responder) first."""
    supabase = get_supabase()
    result = (
        supabase.table("designations")
        .select("designation_id, designation_name, level_name, rank_order")
        .eq("department_id", department_id)
        .order("rank_order", desc=False)
        .execute()
    )
    return [DesignationOption(**row) for row in result.data]


@router.get(
    "/{department_id}/boundary-levels", response_model=list[BoundaryLevelOption]
)
def list_boundary_levels(department_id: str) -> list[BoundaryLevelOption]:
    """This department's own boundary hierarchy, most granular (rank 1) first."""
    supabase = get_supabase()
    result = (
        supabase.table("boundary_levels")
        .select("level_rank, level_name, display_label")
        .eq("department_id", department_id)
        .order("level_rank", desc=False)
        .execute()
    )
    return [BoundaryLevelOption(**row) for row in result.data]


@router.get("/{department_id}/boundaries", response_model=list[BoundaryOption])
def list_boundaries(
    department_id: str,
    level_name: str = Query(...),
    parent_id: int | None = Query(default=None),
) -> list[BoundaryOption]:
    """Boundaries at a given level for a department.

    When [parent_id] is provided the list is filtered to children of that
    parent boundary (used for each cascade step after the first). The first
    (broadest) cascade level omits it and returns every boundary at that level.
    """
    supabase = get_supabase()
    query = (
        supabase.table("boundaries")
        .select("boundary_id, boundary_name, level_name, parent_boundary_id")
        .eq("department_id", department_id)
        .eq("level_name", level_name)
    )
    if parent_id is not None:
        query = query.eq("parent_boundary_id", parent_id)
    result = query.order("boundary_name", desc=False).execute()
    return [BoundaryOption(**row) for row in result.data]
