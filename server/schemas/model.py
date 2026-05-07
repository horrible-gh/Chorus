import re
from typing import Any, Dict, Optional

from pydantic import BaseModel, field_validator

VALID_RUNNERS = {"copilot", "claude", "codex", "gemini"}
VALID_GRADES = {"0급", "0.33급", "1급", "7.5급"}
_MODEL_NAME_RE = re.compile(r"^[a-zA-Z0-9\-\.]+$")


class ModelCreateRequest(BaseModel):
    runner: str
    model_name: str
    grade: str
    is_default: bool = False
    estimated_cost_rank: int
    priority: int = 0
    max_context_tokens: Optional[int] = None
    provider_options_json: Optional[Dict[str, Any]] = None

    @field_validator("runner")
    @classmethod
    def validate_runner(cls, v: str) -> str:
        if v not in VALID_RUNNERS:
            raise ValueError(f"runner must be one of {sorted(VALID_RUNNERS)}")
        return v

    @field_validator("model_name")
    @classmethod
    def validate_model_name(cls, v: str) -> str:
        if not _MODEL_NAME_RE.match(v):
            raise ValueError("model_name must match ^[a-zA-Z0-9\\-\\.]+$")
        return v

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: str) -> str:
        if v not in VALID_GRADES:
            raise ValueError(f"grade must be one of {sorted(VALID_GRADES)}")
        return v


class ModelUpdateRequest(BaseModel):
    grade: Optional[str] = None
    is_active: Optional[bool] = None
    is_default: Optional[bool] = None
    estimated_cost_rank: Optional[int] = None
    priority: Optional[int] = None
    max_context_tokens: Optional[int] = None
    provider_options_json: Optional[Dict[str, Any]] = None

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_GRADES:
            raise ValueError(f"grade must be one of {sorted(VALID_GRADES)}")
        return v


class ModelResponse(BaseModel):
    model_id: str
    runner: str
    model_name: str
    grade: str
    is_active: bool
    is_default: bool
    estimated_cost_rank: int
    priority: int
    max_context_tokens: Optional[int] = None
    provider_options_json: Optional[Dict[str, Any]] = None
    created_at: str
    updated_at: str
    warning: Optional[str] = None
