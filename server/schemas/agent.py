from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, model_validator

_VALID_AUTH_TYPES = frozenset({"api_token", "cli"})
_VALID_CLI_PROVIDERS = frozenset({"claude_cli", "codex_cli", "copilot", "gcloud_adc"})


def _validate_auth_in_settings(settings: Dict[str, Any]) -> None:
    """Raise ValueError for invalid auth_type / cli_provider combinations."""
    auth_type = settings.get("auth_type")
    if auth_type is None:
        return
    if auth_type not in _VALID_AUTH_TYPES:
        raise ValueError(
            f"settings_json.auth_type must be one of {sorted(_VALID_AUTH_TYPES)}"
        )
    provider_token_id = settings.get("provider_token_id")
    cli_provider = settings.get("cli_provider")
    if auth_type == "cli":
        if provider_token_id:
            raise ValueError(
                "settings_json.provider_token_id must be null when auth_type is 'cli'"
            )
        if not cli_provider:
            raise ValueError(
                "settings_json.cli_provider is required when auth_type is 'cli'"
            )
        if cli_provider not in _VALID_CLI_PROVIDERS:
            raise ValueError(
                f"settings_json.cli_provider must be one of {sorted(_VALID_CLI_PROVIDERS)}"
            )


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

    @model_validator(mode="after")
    def check_auth_settings(self) -> "AgentPresetCreate":
        _validate_auth_in_settings(self.settings_json)
        return self


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

    @model_validator(mode="after")
    def check_auth_settings(self) -> "AgentPresetUpdate":
        if self.settings_json is not None:
            _validate_auth_in_settings(self.settings_json)
        return self


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

