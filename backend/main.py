from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import api_router

app = FastAPI(
    title="CivicRoute API",
    description="Intelligent Government Complaint Routing and Resolution System backend.",
    version="1.0"
)

# Enable CORS for Flutter Web client access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health", tags=["System"])
def health_check():
    """
    Simple health check endpoint returning 200 OK.
    """
    return {"status": "ok"}

# Include API routes
app.include_router(api_router)
