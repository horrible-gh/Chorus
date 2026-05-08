"""Provider Management API router.

Endpoints:
  GET   /auth/providers/status                      - All provider connection states
  PATCH /auth/providers/{provider}/executable-path  - Save executable path
  POST  /auth/providers/{provider}/verify           - Active self-check A+B

Internal:
  mark_provider_available(provider)                 - Passive Available update
"""

import json
import os
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import LogAssist.log as logger
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from modules.chat_manager import ChorusStore

router = APIRouter()

JST = timezone(timedelta(hours=9))

VALID_PROVIDERS = {"copilot", "claude", "codex", "gemini"}

_DEFAULT_COMMAND: dict[str, str] = {
    "copilot": "copilot",
    "claude":  "claude",
    "codex":   "codex",
    "gemini":  "gemini",
}

# Self-check B: minimal non-interactive command confirming the provider CLI works
_VERIFY_ARGS: dict[str, list[str]] = {
    "copilot": ["--version"],
    "claude":  ["--version"],
    "codex":   ["--version"],
    "gemini":  ["--version"],
}

_SCOPE = "provider_management"
_KEY2  = "connection"
_KEY3  = ""


# ── DB helpers ────────────────────────────────────────────────────────────────

class _ProviderConfigStore(ChorusStore):
    """Thin extension of ChorusStore for provider_management server_config access."""

    def get_provider_config(self, provider: str) -> dict:
        row = self._fetch_one(
            "SELECT value FROM server_config"
            " WHERE scope = ? AND key1 = ? AND key2 = ? AND key3 = ?",
            [_SCOPE, provider, _KEY2, _KEY3],
        )
        if row and row.get("value"):
            try:
                return json.loads(row["value"])
            except Exception:
                pass
        return {
            "executable_path": "",
            "status": "unverified",
            "resolved_path": None,
            "last_checked_at": None,
            "last_available_at": None,
            "last_error": None,
        }

    def save_provider_config(self, provider: str, data: dict) -> None:
        value_str = json.dumps(data, ensure_ascii=False)
        now = _now_iso()
        existing = self._fetch_one(
            "SELECT value FROM server_config"
            " WHERE scope = ? AND key1 = ? AND key2 = ? AND key3 = ?",
            [_SCOPE, provider, _KEY2, _KEY3],
        )
        if existing is not None:
            self._execute(
                "UPDATE server_config SET value = ?, updated_at = ?"
                " WHERE scope = ? AND key1 = ? AND key2 = ? AND key3 = ?",
                [value_str, now, _SCOPE, provider, _KEY2, _KEY3],
            )
        else:
            self._execute(
                "INSERT INTO server_config (scope, key1, key2, key3, value, updated_at)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                [_SCOPE, provider, _KEY2, _KEY3, value_str, now],
            )


_STORE = _ProviderConfigStore()


# ── Utilities ─────────────────────────────────────────────────────────────────

def _now_iso() -> str:
    return datetime.now(JST).isoformat(timespec="seconds")


def _resolve_path(provider: str, configured_path: str) -> tuple[Optional[str], str]:
    """Return (resolved_path, path_source).

    path_source is 'configured' when the user supplied a path, 'shutil_which'
    when the server resolved it automatically.
    """
    if configured_path:
        return configured_path, "configured"

    cmd = _DEFAULT_COMMAND[provider]
    found = shutil.which(cmd)

    if found and provider == "copilot":
        # Copilot special case: VS Code copilotCli path → prefer npm copilot.CMD
        if "vscode" in found.lower() or "copilotcli" in found.lower():
            npm_path = os.path.expandvars(r"%APPDATA%\npm\copilot.CMD")
            if os.path.isfile(npm_path):
                return npm_path, "shutil_which"
            npm_dir = os.path.expandvars(r"%APPDATA%\npm")
            npm_alt = shutil.which("copilot", path=npm_dir)
            if npm_alt:
                return npm_alt, "shutil_which"

    if found:
        return found, "shutil_which"
    return None, "shutil_which"


def _build_item(provider: str, cfg: dict) -> dict:
    configured_path = cfg.get("executable_path") or ""
    resolved_path, path_source = _resolve_path(provider, configured_path)
    return {
        "provider": provider,
        "status": cfg.get("status", "unverified"),
        "executable_path": configured_path,
        "path_source": path_source,
        "resolved_path": resolved_path,
        "last_checked_at": cfg.get("last_checked_at"),
        "last_available_at": cfg.get("last_available_at"),
        "last_error": cfg.get("last_error"),
    }


# ── Schemas ───────────────────────────────────────────────────────────────────

class ProviderStatusItem(BaseModel):
    provider: str
    status: str
    executable_path: str
    path_source: str
    resolved_path: Optional[str]
    last_checked_at: Optional[str]
    last_available_at: Optional[str]
    last_error: Optional[str]


class ExecutablePathRequest(BaseModel):
    executable_path: str


class ExecutablePathResponse(BaseModel):
    provider: str
    executable_path: str
    path_source: str
    resolved_path: Optional[str]


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/providers/status", response_model=list[ProviderStatusItem])
async def get_providers_status():
    """Return connection status and path info for all supported providers."""
    return [
        _build_item(p, _STORE.get_provider_config(p))
        for p in ("copilot", "claude", "codex", "gemini")
    ]


@router.patch("/providers/{provider}/executable-path", response_model=ExecutablePathResponse)
async def set_executable_path(provider: str, body: ExecutablePathRequest):
    """Save the executable path for a provider. Empty string clears the configured path."""
    if provider not in VALID_PROVIDERS:
        raise HTTPException(status_code=400, detail={"code": "UNKNOWN_PROVIDER"})

    path = body.executable_path.strip()

    if path:
        if not os.path.isabs(path):
            raise HTTPException(status_code=422, detail={"code": "INVALID_EXECUTABLE_PATH"})
        if os.path.isdir(path):
            raise HTTPException(status_code=422, detail={"code": "INVALID_EXECUTABLE_PATH"})

    try:
        cfg = _STORE.get_provider_config(provider)
        cfg["executable_path"] = path
        _STORE.save_provider_config(provider, cfg)
    except Exception as exc:
        logger.error(f"[provider_management] save_provider_config failed: {exc}")
        raise HTTPException(status_code=500, detail={"code": "PROVIDER_CONFIG_SAVE_FAILED"})

    resolved_path, path_source = _resolve_path(provider, path)
    return ExecutablePathResponse(
        provider=provider,
        executable_path=path,
        path_source=path_source,
        resolved_path=resolved_path,
    )


@router.post("/providers/{provider}/verify", response_model=ProviderStatusItem)
async def verify_provider(provider: str):
    """Run active self-check A+B for a provider and persist the result."""
    if provider not in VALID_PROVIDERS:
        raise HTTPException(status_code=400, detail={"code": "UNKNOWN_PROVIDER"})

    cfg = _STORE.get_provider_config(provider)
    configured_path = cfg.get("executable_path") or ""
    resolved_path, _ = _resolve_path(provider, configured_path)
    now = _now_iso()

    # ── Self-check A: executable exists / is callable ─────────────────────
    check_a = False
    if resolved_path:
        check_a = os.path.isfile(resolved_path) or bool(shutil.which(resolved_path))

    if not check_a:
        cfg.update({
            "status": "unavailable",
            "last_checked_at": now,
            "last_error": "executable not found",
        })
        _STORE.save_provider_config(provider, cfg)
        return _build_item(provider, cfg)

    # ── Self-check B: minimal provider invocation ─────────────────────────
    if provider == "copilot":
        project_root = str(Path(__file__).parents[3])
        verify_cmd = [resolved_path, "--allow-all", "--model", "claude-haiku-4.5", "-p", "ping"]
        _run_kw: dict = dict(cwd=project_root, capture_output=True, timeout=30, encoding="utf-8")
    else:
        verify_cmd = [resolved_path] + _VERIFY_ARGS[provider]
        _run_kw = dict(timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        result = subprocess.run(verify_cmd, **_run_kw)
        check_b = result.returncode == 0
        last_error = None if check_b else f"command exited with code {result.returncode}"
    except subprocess.TimeoutExpired:
        check_b = False
        last_error = "timeout"
    except (FileNotFoundError, OSError) as exc:
        check_b = False
        last_error = str(exc)

    if check_b:
        cfg.update({
            "status": "available",
            "resolved_path": resolved_path,
            "last_checked_at": now,
            "last_available_at": now,
            "last_error": None,
        })
    else:
        cfg.update({
            "status": "unavailable",
            "resolved_path": resolved_path,
            "last_checked_at": now,
            "last_error": last_error,
        })

    _STORE.save_provider_config(provider, cfg)
    return _build_item(provider, cfg)


# ── Internal hook ─────────────────────────────────────────────────────────────

def mark_provider_available(provider: str) -> None:
    """Mark a provider Available after a successful agent communication (passive update).

    Never raises — failures are logged and the caller's response is unaffected.
    """
    if provider not in VALID_PROVIDERS:
        return
    try:
        cfg = _STORE.get_provider_config(provider)
        cfg.update({
            "status": "available",
            "last_available_at": _now_iso(),
            "last_error": None,
        })
        _STORE.save_provider_config(provider, cfg)
        logger.debug(f"[provider_management] passive available: {provider}")
    except Exception as exc:
        logger.warning(f"[provider_management] mark_provider_available failed [{provider}]: {exc}")
