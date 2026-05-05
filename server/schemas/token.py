from typing import Literal, Optional

from pydantic import BaseModel, Field


class ProviderTokenCreate(BaseModel):
    owner_user_id: str = Field(..., min_length=1)
    alias: str = Field(..., min_length=1)
    provider: Literal["copilot", "openai", "anthropic", "google"]
    token_value: str = Field(..., min_length=1)
    status: Literal["active", "inactive"] = "active"


class ProviderTokenUpdate(BaseModel):
    alias: Optional[str] = Field(None, min_length=1)
    provider: Optional[Literal["copilot", "openai", "anthropic", "google"]] = None
    token_value: Optional[str] = Field(None, min_length=1)
    status: Optional[Literal["active", "inactive", "archived"]] = None


class ProviderToken(BaseModel):
    token_id: str
    owner_user_id: str
    alias: str
    provider: str
    token_value: str
    status: str
    created_at: str
    updated_at: str
