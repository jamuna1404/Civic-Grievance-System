from fastapi import APIRouter
from app.api.complaints import router as complaints_router

api_router = APIRouter()

# Register resource routers
api_router.include_router(complaints_router, prefix="/api/complaints", tags=["Complaints"])
