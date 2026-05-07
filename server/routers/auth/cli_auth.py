"""CLI authentication API router.

Endpoints:
  GET  /api/auth/cli-status          - Query all provider CLI session statuses
  POST /api/auth/cli-login/{provider} - Execute CLI login command non-blocking (202)
  POST /api/auth/cli-logout/{provider} - Execute CLI logout command blocking
"""

import subprocess
from datetime import datetime, timezone, timedelta
from typing import List, Literal, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

# ── Type definitions ─────────────────────────────────────────────────────

CLIProvider = Literal["claude_cli", "codex_cli", "copilot", "gcloud_adc"]
CLIStatus = Literal["logged_in", "logged_out", "active", "inactive", "unknown"]

VALID_PROVIDERS = {"claude_cli", "codex_cli", "copilot", "gcloud_adc"}

_STATUS_CMD: dict[str, list[str]] = {
    "claude_cli": ["claude", "auth", "status"],
    "codex_cli":  ["codex", "auth", "status"],
    "copilot":    ["copilot", "auth", "status"],
    "gcloud_adc": ["gcloud", "auth", "application-default", "print-access-token"],
}

_LOGIN_CMD: dict[str, list[str]] = {
    "claude_cli": ["claude", "login"],
    "codex_cli":  ["codex", "login"],
    "copilot":    ["copilot", "auth", "login"],
    "gcloud_adc": ["gcloud", "auth", "application-default", "login"],
}

_LOGOUT_CMD: dict[str, list[str]] = {
    "claude_cli": ["claude", "logout"],
    "codex_cli":  ["codex", "logout"],
    "copilot":    ["copilot", "auth", "logout"],
    "gcloud_adc": ["gcloud", "auth", "application-default", "revoke", "--quiet"],
}

# gcloud_adc status values are active/inactive; others use logged_in/logged_out
_POSITIVE_STATUS: dict[str, CLIStatus] = {
    "claude_cli": "logged_in",
    "codex_cli":  "logged_in",
    "copilot":    "logged_in",
    "gcloud_adc": "active",
}

_NEGATIVE_STATUS: dict[str, CLIStatus] = {
    "claude_cli": "logged_out",
    "codex_cli":  "logged_out",
    "copilot":    "logged_out",
    "gcloud_adc": "inactive",
}


# ── Pydantic schemas ───────────────────────────────────────────────

class CLIProviderStatus(BaseModel):
    provider: str
    status: str
    checked_at: str
    logout_supported: bool


class CLILoginResponse(BaseModel):
    provider: str
    result: Literal["login_started"]
    message: str


class CLILogoutResponse(BaseModel):
    provider: str
    result: Literal["logged_out"]


# ── Helpers ─────────────────────────────────────────────────────────

def _now_iso() -> str:
    """Return current time as an ISO 8601 string (fixed +09:00 offset)."""
    tz_kst = timezone(timedelta(hours=9))
    return datetime.now(tz=tz_kst).isoformat(timespec="seconds")


def _check_provider_status(provider: str) -> CLIProviderStatus:
    """Query CLI status for a single provider and return CLIProviderStatus."""
    checked_at = _now_iso()
    cmd = _STATUS_CMD[provider]
    try:
        result = subprocess.run(
            cmd,
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            status = _POSITIVE_STATUS[provider]
        else:
            status = _NEGATIVE_STATUS[provider]
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        status = "unknown"

    return CLIProviderStatus(
        provider=provider,
        status=status,
        checked_at=checked_at,
        logout_supported=(status != "unknown"),
    )


# ── Endpoints ────────────────────────────────────────────────────────

@router.get("/cli-status", response_model=List[CLIProviderStatus])
async def get_cli_status():
    """Query all CLI provider session statuses. Each provider has a 10-second timeout."""
    return [_check_provider_status(p) for p in ("claude_cli", "codex_cli", "copilot", "gcloud_adc")]


@router.post("/cli-login/{provider}", status_code=202, response_model=CLILoginResponse)
async def cli_login(provider: str):
    """Execute CLI login command non-blocking. Starts the browser OAuth flow and returns 202 immediately."""
    if provider not in VALID_PROVIDERS:
        raise HTTPException(status_code=400, detail="unknown provider")

    cmd = _LOGIN_CMD[provider]
    try:
        subprocess.Popen(cmd)
    except (FileNotFoundError, OSError) as exc:
        raise HTTPException(
            status_code=500,
            detail=f"failed to start login process: {exc}",
        )

    return CLILoginResponse(
        provider=provider,
        result="login_started",
        message="Login command executed. Refresh status after completing auth in the server browser.",
    )


@router.post("/cli-logout/{provider}", response_model=CLILogoutResponse)
async def cli_logout(provider: str):
    """Execute CLI logout command blocking. 30-second timeout."""
    if provider not in VALID_PROVIDERS:
        raise HTTPException(status_code=400, detail="unknown provider")

    cmd = _LOGOUT_CMD[provider]
    try:
        result = subprocess.run(
            cmd,
            timeout=30,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="logout timed out")
    except (FileNotFoundError, OSError) as exc:
        raise HTTPException(
            status_code=500,
            detail=f"failed to start logout process: {exc}",
        )

    if result.returncode != 0:
        stderr_snippet = (result.stderr or "")[:500]
        raise HTTPException(
            status_code=500,
            detail=f"logout failed: {stderr_snippet}",
        )

    return CLILogoutResponse(provider=provider, result="logged_out")
