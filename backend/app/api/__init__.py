from fastapi import APIRouter
from app.api.complaints import router as complaints_router
from app.api.notifications import router as notifications_router
from app.api.admin import router as admin_router

api_router = APIRouter()

# Register resource routers
api_router.include_router(complaints_router, prefix="/api/complaints", tags=["Complaints"])
api_router.include_router(notifications_router, prefix="/api/notifications", tags=["Notifications"])
api_router.include_router(admin_router, prefix="/api/admin", tags=["Admin"])


