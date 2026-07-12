import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import settings
from app.core.database import get_db
from app.models.all_models import User

# HTTPBearer extracts authorization header value
security_scheme = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    FastAPI dependency to extract and validate Supabase JWT from Authorization header.
    Resolves the claims to a User record in the application database.
    """
    token = credentials.credentials
    try:
        # Decode and verify Supabase JWT signature locally using shared secret
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False}
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session has expired. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.PyJWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid authorization token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token payload invalid: subject identifier (sub) missing.",
        )

    # Fetch matching user from the local app database
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        # If user exists in Supabase Auth but not synced to our users table yet (e.g. new citizen login)
        email = payload.get("email")
        # Supabase stores phone inside phone or identity data
        phone = payload.get("phone")
        
        user_metadata = payload.get("user_metadata", {})
        name = user_metadata.get("full_name") or user_metadata.get("name") or (email.split("@")[0] if email else "Citizen")
        role = user_metadata.get("role") or "citizen"

        user = User(
            id=user_id,
            name=name,
            role=role,
            phone=phone,
            email=email,
            jurisdiction_id=None
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    return user
