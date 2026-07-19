"""Shared FastAPI dependencies."""

from fastapi import Header, HTTPException, status

from app.core.security import verify_session_token


def _subject_from_header(authorization: str) -> str:
    """Extract and verify the subject id from a `Bearer <token>` header.

    Session tokens are role-agnostic (they encode an id); the calling endpoint
    is responsible for confirming the id belongs to the expected role.
    """
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    subject = verify_session_token(token)
    if subject is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return subject


def get_current_citizen_id(authorization: str = Header(default="")) -> str:
    """The citizen_id from the Bearer token (401 if missing/invalid)."""
    return _subject_from_header(authorization)


def get_current_officer_id(authorization: str = Header(default="")) -> str:
    """The officer_id from the Bearer token (401 if missing/invalid)."""
    return _subject_from_header(authorization)
