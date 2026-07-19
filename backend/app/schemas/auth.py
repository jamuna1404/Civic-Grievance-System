"""Request/response models for citizen authentication."""

from pydantic import BaseModel, Field


# --- Requests ---------------------------------------------------------------


class SendOtpRequest(BaseModel):
    phone_number: str = Field(..., examples=["9876543210"])


class VerifyOtpRequest(BaseModel):
    phone_number: str = Field(..., examples=["9876543210"])
    otp_code: str = Field(..., min_length=6, max_length=6, examples=["123456"])


class CompleteSignupRequest(BaseModel):
    phone_number: str = Field(..., examples=["9876543210"])
    full_name: str = Field(..., min_length=1, max_length=120)


# --- Responses --------------------------------------------------------------


class SendOtpResponse(BaseModel):
    success: bool = True
    # Echoed back so the client knows the canonical number the OTP was tied to.
    phone_number: str
    # Present only in non-production to make manual testing easy; never in prod.
    debug_otp: str | None = None


class VerifyOtpResponse(BaseModel):
    new_user: bool
    # Populated only for existing (returning) users; new users must first
    # complete signup before they receive a token.
    session_token: str | None = None
    full_name: str | None = None
    citizen_id: str | None = None


class CompleteSignupResponse(BaseModel):
    session_token: str
    full_name: str
    citizen_id: str
