from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, model_validator

_VALID_AUTH_TYPES = frozenset({"api_token", "cli"})
_VALID_CLI_PROVIDERS = frozenset({"claude_cli", "codex_cli", "copilot", "gcloud_adc"})

_ALLOWED_DIRS_MAX_COUNT = 20
_ALLOWED_DIRS_PATH_MAX_LEN = 260

import re as _re
_DRIVE_ROOT_RE = _re.compile(r'^[A-Za-z]:\\$')
_ABSOLUTE_PATH_RE = _re.compile(r'^[A-Za-z]:\\')


def _is_absolute_path(path: str) -> bool:
    normalized = path.replace("/", "\\")
    if _ABSOLUTE_PATH_RE.match(normalized):
        return True
    if normalized.startswith("\\\\"):
        return True
    return False


def _is_drive_root_path(path: str) -> bool:
    normalized = path.replace("/", "\\")
    return bool(_DRIVE_ROOT_RE.match(normalized))


def _validate_allowed_dirs_in_settings(settings: Dict[str, Any]) -> None:
    """Raise ValueError for invalid allowed_dirs in settings_json."""
    raw = settings.get("allowed_dirs")
    if raw is None:
        return
    if not isinstance(raw, list):
        raise ValueError("allowed_dirs는 배열이어야 합니다.")
    if len(raw) > _ALLOWED_DIRS_MAX_COUNT:
        raise ValueError(f"allowed_dirs는 최대 {_ALLOWED_DIRS_MAX_COUNT}개까지만 허용됩니다.")
    for item in raw:
        if not isinstance(item, str):
            raise ValueError("각 경로는 문자열이어야 합니다.")
        trimmed = item.strip()
        if len(trimmed) == 0:
            raise ValueError("allowed_dirs에 빈 문자열 경로가 포함되어 있습니다.")
        if len(trimmed) > _ALLOWED_DIRS_PATH_MAX_LEN:
            raise ValueError("allowed_dirs의 경로가 최대 길이(260자)를 초과합니다.")
        if _is_drive_root_path(trimmed):
            raise ValueError("드라이브 루트 경로(예: C:\\, D:\\)는 허용되지 않습니다.")
        if not _is_absolute_path(trimmed):
            raise ValueError("allowed_dirs의 경로가 유효하지 않습니다. 절대경로만 허용됩니다.")
    deduplicated: List[str] = list(dict.fromkeys(item.strip() for item in raw))
    settings["allowed_dirs"] = deduplicated


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
        _validate_allowed_dirs_in_settings(self.settings_json)
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
            _validate_allowed_dirs_in_settings(self.settings_json)
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

