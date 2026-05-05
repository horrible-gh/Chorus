from typing import Any, Dict, Optional

from pydantic import BaseModel, Field


class AgentPresetCreate(BaseModel):
    owner_user_id: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1, max_length=120)
    role_name: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = None
    default_runner: str = "copilot"
    default_model: str = "gpt-5-mini"
    default_grade: str = "0급"
    system_prompt: str = ""
    pinned_context: Optional[str] = None
    settings_json: Dict[str, Any] = Field(default_factory=dict)


class AgentPresetUpdate(BaseModel):
    display_name: Optional[str] = Field(None, min_length=1, max_length=120)
    role_name: Optional[str] = Field(None, min_length=1, max_length=120)
    description: Optional[str] = None
    default_runner: Optional[str] = None
    default_model: Optional[str] = None
    default_grade: Optional[str] = None
    system_prompt: Optional[str] = None
    pinned_context: Optional[str] = None
    settings_json: Optional[Dict[str, Any]] = None
    status: Optional[str] = None


class AgentPreset(BaseModel):
    agent_id: str
    owner_user_id: str
    display_name: str
    role_name: str
    description: Optional[str] = None
    default_runner: str
    default_model: str
    default_grade: str
    system_prompt: str
    pinned_context: Optional[str] = None
    settings_json: Dict[str, Any] = Field(default_factory=dict)
    status: str
    created_at: str
    updated_at: str

