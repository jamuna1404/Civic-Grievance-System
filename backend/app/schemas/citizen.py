"""Request/response models for the citizen profile & preferences routes."""

from typing import Literal

from pydantic import BaseModel, Field

ThemeMode = Literal["LIGHT", "DARK", "SYSTEM"]


class CitizenProfileResponse(BaseModel):
    citizen_id: str
    full_name: str
    phone_number: str
    theme_mode: ThemeMode = "SYSTEM"


class UpdateProfileRequest(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=120)


class UpdateProfileResponse(BaseModel):
    full_name: str


class UpdatePreferencesRequest(BaseModel):
    theme_mode: ThemeMode


class UpdatePreferencesResponse(BaseModel):
    theme_mode: ThemeMode
