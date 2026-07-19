"""CivicRoute FastAPI application entry point.

Skeleton only: wires the router modules and a health check. Business logic
lands in later prompts.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.routers import auth, citizen, complaints, departments, officer

settings = get_settings()

app = FastAPI(
    title="CivicRoute API",
    description="Backend for the CivicRoute civic complaint app (Chennai).",
    version="0.1.0",
)

# Permissive CORS for local development; tighten before deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(citizen.router)
app.include_router(officer.router)
app.include_router(complaints.router)
app.include_router(departments.router)


@app.get("/health", tags=["meta"])
def health() -> dict[str, str]:
    """Liveness probe."""
    return {"status": "ok", "environment": settings.environment}
