from typing import Optional

from pydantic import BaseModel, Field


class UserProfileResponse(BaseModel):
    user_id: str
    email_verified: bool
    totp_enabled: bool


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=8)


class TotpSetupResponse(BaseModel):
    secret: str
    qr_uri: str
    qr_image: str   # base64-encoded PNG
    recovery_codes: list[str]


class TotpActivateRequest(BaseModel):
    code: str = Field(..., min_length=6, max_length=8)


class TotpActivateResponse(BaseModel):
    ok: bool


class TotpDisableRequest(BaseModel):
    code: str = Field(..., min_length=6, max_length=8)
